<#
.SYNOPSIS
    Scans music folder structures and validates them against expected naming conventions.
    Identifies folders with good structure, bad structure, or structural issues.
    Automatically logs results to a timestamped file in $env:TEMP\MusicFolderChecker\ if no log path is specified.

.DESCRIPTION
    Find-BadMusicFolderStructure recursively scans a starting directory and validates music folder structures.
    It checks for proper artist/album/year organization and identifies folders that need restructuring.

    Expected folder structure:
    - ArtistName\YYYY - AlbumName\NN - TrackName.ext
    - ArtistName\YYYY - AlbumName\Disc X\NN - TrackName.ext (for multi-disc albums)

    The function can skip specific paths to exclude entire directory trees from scanning.
    FoldersToSkip supports both comma-separated strings and PowerShell arrays.

.PARAMETER StartingPath
    The root directory path to begin scanning. This parameter is mandatory and accepts pipeline input.

.PARAMETER Good
    Switch parameter. When specified, returns only folders with good structure.

.PARAMETER LogTo
    Optional path to save scan results. If not specified, automatically creates a timestamped log file
    in $env:TEMP\MusicFolderChecker\. Supports both JSON and text formats.

.PARAMETER WhatToLog
    Specifies which types of folders to log. Valid values: 'Good', 'Bad', 'All'. Default is 'All'.

.PARAMETER LogFormat
    Format for the log file. Valid values: 'Text', 'JSON'. Default is 'JSON'.

.PARAMETER Quiet
    Switch parameter. When specified, suppresses console output during scanning.

.PARAMETER FoldersToSkip
    Array of paths to exclude from scanning. Supports both comma-separated strings and PowerShell arrays.
    When a folder path starts with any skipped path, the entire subtree is skipped.

.PARAMETER Simple
    Switch parameter for backward compatibility. Returns boolean results instead of detailed objects.

.INPUTS
    System.String
    You can pipe folder paths to Find-BadMusicFolderStructure.

.OUTPUTS
    PSCustomObject or System.Boolean
    Returns detailed validation objects with Path, IsValid, Reason, Details, and Status properties.
    With -Simple switch, returns boolean values.

.EXAMPLE
    Find-BadMusicFolderStructure -StartingPath 'E:\Music'
    Scans the E:\Music directory and returns detailed validation results for all folders.

.EXAMPLE
    Find-BadMusicFolderStructure -StartingPath 'E:\Music' -Good -Quiet
    Scans for good folders only, suppressing console output.

.EXAMPLE
    Find-BadMusicFolderStructure -StartingPath 'E:\Music' -FoldersToSkip 'E:\Music\Various Artists','E:\Music\_Archive'
    Scans E:\Music but excludes the specified artist folders and their subfolders.

.EXAMPLE
    Find-BadMusicFolderStructure -StartingPath 'E:\Music' -LogTo 'C:\Temp\scan_results.json' -LogFormat JSON
    Scans and saves detailed JSON results to the specified file.

.EXAMPLE
    Get-ChildItem 'E:\Music' -Directory | Find-BadMusicFolderStructure -Simple
    Uses pipeline input and returns simple boolean results for backward compatibility.

.NOTES
    Author: MusicFolderChecker Module
    Requires TagLib-Sharp.dll for audio file validation
    Automatically creates log directory if it doesn't exist
    FoldersToSkip comparison is case-insensitive and handles trailing slashes
#>
function Find-BadMusicFolderStructure {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]$StartingPath,

        [switch]$Good,

        [string]$LogTo,

        [Parameter()]
        [ValidateSet('Good', 'Bad', 'All')]
        [string]$WhatToLog = 'All',

        [Parameter()]
        [ValidateSet('Text', 'JSON')]
        [string]$LogFormat = 'JSON',

        [switch]$Quiet,

        [Parameter()]
        [string[]]$FoldersToSkip,  # Comma-separated list of paths to exclude from scanning

        [switch]$Simple,  # New parameter for backward compatibility

        [switch]$AnalyzeStructure  # Enhanced analysis with structure type detection
    )

    begin {
        $audioExtensions = @(".mp3", ".wav", ".flac", ".aac", ".ogg", ".wma")
        $patternMain = '(?i).*\\([^\\]+)\\\d{4} - (?!.*(?:CD|Disc)\d+)[^\\]+\\(?:\d+-\d{2}|\d{2}) - .+\.[a-z0-9]+$'
        $patternDisc = '(?i).*\\([^\\]+)\\\d{4} - [^\\]+(?:\\(?:Disc|CD)\\s*\\d+|- (?:Disc|CD)\\d+|)\\(?:\\d+-\\d{2}|\\d{2}) - .+\\.[a-z0-9]+$'
        $results = @()

        # Set default log path if not provided
        if (-not $LogTo) {
            $defaultDir = Join-Path $env:TEMP "MusicFolderChecker"
            if (-not (Test-Path $defaultDir)) {
                New-Item -ItemType Directory -Path $defaultDir -Force | Out-Null
            }
            $LogTo = Join-Path $defaultDir "MusicFolderStructureScan_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
            # Default to JSON format for auto-generated logs
            $LogFormat = 'JSON'
        }

        if ($LogTo) {
            $logDir = Split-Path -Path $LogTo -Parent
            if (-not (Test-Path -Path $logDir)) {
                New-Item -ItemType Directory -Path $logDir -Force -WhatIf:$false | Out-Null
            }
            # Initialize a fresh log file
            "" | Out-File -FilePath $LogTo -Encoding UTF8 -WhatIf:$false
        }
    }

    process {
        $folders = @($StartingPath) + (Get-ChildItem -LiteralPath $StartingPath -Recurse | Where-Object { $_.PSIsContainer } | Sort-Object -Unique | ForEach-Object { $_.FullName }) | Select-Object -Unique

        foreach ($folder in $folders) {
            $validationResult = [PSCustomObject]@{
                Path = $folder
                IsValid = $false
                Reason = "Unknown"
                Details = ""
                Status = "Unknown"
            }

            # Check if folder is in folders to skip
            if ($FoldersToSkip) {
                # Handle both array and comma-separated string formats
                $foldersToSkipArray = @()
                foreach ($item in $FoldersToSkip) {
                    if ($item -match ',') {
                        # Comma-separated string
                        $foldersToSkipArray += $item -split ',' | ForEach-Object { $_.Trim() }
                    } else {
                        # Array element
                        $foldersToSkipArray += $item
                    }
                }
                # Remove duplicates
                $foldersToSkipArray = $foldersToSkipArray | Select-Object -Unique
                
                $isSkipped = $false
                foreach ($skippedPath in $foldersToSkipArray) {
                    # Normalize paths for comparison (handle trailing slashes, case sensitivity)
                    $normalizedFolder = $folder.TrimEnd('\').ToLower()
                    $normalizedSkipped = $skippedPath.TrimEnd('\').ToLower()

                    # Check if folder path starts with skipped path (skips entire subtree)
                    if ($normalizedFolder.StartsWith($normalizedSkipped)) {
                        $isSkipped = $true
                        break
                    }
                }
                if ($isSkipped) {
                    $validationResult.Reason = "Skipped"
                    $validationResult.Details = "Folder is in folders to skip"
                    $validationResult.Status = "Skipped"
                    $results += $validationResult
                    continue
                }
            }

            if (-not $Quiet) {
                Write-Host "� Checking folder: $folder"
            }

            # Check if folder exists and is accessible
            if (-not (Test-Path -LiteralPath $folder)) {
                $validationResult.Reason = "NotFound"
                $validationResult.Details = "Folder does not exist"
                $validationResult.Status = "Error"
                $results += $validationResult
                continue
            }

            # Check if folder is empty
            $allItems = Get-ChildItem -LiteralPath $folder -ErrorAction SilentlyContinue
            if (-not $allItems -or $allItems.Count -eq 0) {
                $validationResult.Reason = "Empty"
                $validationResult.Details = "Folder contains no files or subfolders"
                $validationResult.Status = "Bad"
                $results += $validationResult
                continue
            }

            # Check if this is an artist folder containing album subfolders
            $subfolders = Get-ChildItem -LiteralPath $folder -Directory -ErrorAction SilentlyContinue
            $albumSubfolders = @()
            foreach ($subfolder in $subfolders) {
                if ($subfolder.Name -match '^\d{4} - .+$') {
                    $albumSubfolders += $subfolder
                }
            }

            if ($albumSubfolders) {
                # This is an artist folder - check if any album subfolder contains music files
                $hasMusicFiles = $false
                foreach ($albumFolder in $albumSubfolders) {
                    foreach ($extension in $audioExtensions) {
                        $musicFiles = Get-ChildItem -LiteralPath $albumFolder.FullName -File -Filter "*$extension" -ErrorAction SilentlyContinue
                        if ($musicFiles.Count -gt 0) {
                            $hasMusicFiles = $true
                            $firstAudioFile = $musicFiles | Select-Object -First 1
                            break
                        }
                    }
                    if ($hasMusicFiles) { break }
                }

                if (-not $hasMusicFiles) {
                    $validationResult.Reason = "NoMusicFiles"
                    $validationResult.Details = "No supported audio files found in album subfolders ($($audioExtensions -join ', '))"
                    $validationResult.Status = "Bad"
                    $results += $validationResult
                    continue
                }
            } else {
                # This is an album folder - look for music files directly
                $firstAudioFile = $null
                foreach ($extension in $audioExtensions) {
                    $firstAudioFile = Get-ChildItem -LiteralPath $folder -File -Filter "*$extension" -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($firstAudioFile) { break }
                }

                if (-not $firstAudioFile) {
                    $validationResult.Reason = "NoMusicFiles"
                    $validationResult.Details = "No supported audio files found ($($audioExtensions -join ', '))"
                    $validationResult.Status = "Bad"
                    $results += $validationResult
                    continue
                }
            }

            # Try to read the audio file to check for corruption
            try {
                # TagLib is already loaded at module level, just validate the file
                [TagLib.File]::Create($firstAudioFile.FullName) | Out-Null
                # File is readable
            }
            catch {
                $validationResult.Reason = "CorruptedFile"
                $validationResult.Details = "Audio file appears corrupted: $($firstAudioFile.Name) - $_"
                $validationResult.Status = "Bad"
                $results += $validationResult
                continue
            }

            $fullPath = $firstAudioFile.FullName
            if ($fullPath -match $patternMain -or $fullPath -match $patternDisc) {
                $validationResult.IsValid = $true
                $validationResult.Reason = "Valid"
                $validationResult.Details = "Matches expected folder structure"
                $validationResult.Status = "Good"
                $results += $validationResult
            }
            else {
                $validationResult.Reason = "BadStructure"
                $validationResult.Details = "Audio files found but folder structure doesn't match expected pattern"
                $validationResult.Status = "Bad"
                $results += $validationResult
            }
        }
    }

    end {
        # If AnalyzeStructure is requested, enhance results with structure analysis
        if ($AnalyzeStructure) {
            $enhancedResults = @()
            foreach ($result in $results) {
                if ($result.Status -ne "Skipped" -and $result.Status -ne "Error") {
                    try {
                        $structureAnalysis = Get-FolderStructureAnalysis -Path $result.Path
                        $enhancedResult = $result | Select-Object *,
                            @{Name="StructureType"; Expression={$structureAnalysis.StructureType}},
                            @{Name="Confidence"; Expression={$structureAnalysis.Confidence}},
                            @{Name="StructureDetails"; Expression={$structureAnalysis.Details -join "; "}},
                            @{Name="Recommendations"; Expression={$structureAnalysis.Recommendations -join "; "}},
                            @{Name="Metadata"; Expression={$structureAnalysis.Metadata}}
                        $enhancedResults += $enhancedResult
                    }
                    catch {
                        # If analysis fails, return original result
                        $enhancedResults += $result
                    }
                } else {
                    $enhancedResults += $result
                }
            }
            $results = $enhancedResults
        }

        # Log results after all processing is complete (including structure analysis)
        if ($LogTo) {
            $loggedGood = @{}
            $loggedBad = @{}

            foreach ($result in $results) {
                if ($result.Status -eq "Good" -and ($WhatToLog -eq 'Good' -or $WhatToLog -eq 'All') -and -not $loggedGood.ContainsKey($result.Path)) {
                    $loggedGood[$result.Path] = $true
                    if ($LogFormat -eq 'JSON') {
                        $logEntry = @{
                            Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                            Status = $result.Status
                            Path = $result.Path
                            Function = 'Find-BadMusicFolderStructure'
                            Type = 'ArtistFolder'
                            Reason = $result.Reason
                            Details = $result.Details
                        }

                        # Add structure analysis fields if available
                        if ($result.StructureType) {
                            $logEntry.StructureType = $result.StructureType
                            $logEntry.Confidence = $result.Confidence
                            $logEntry.StructureDetails = $result.StructureDetails
                            $logEntry.Recommendations = $result.Recommendations
                            $logEntry.Metadata = $result.Metadata
                        }

                        $logEntryJson = $logEntry | ConvertTo-Json -Compress
                        Write-LogEntry -Path $LogTo -Value "$logEntryJson`r`n"
                    } else {
                        Write-LogEntry -Path $LogTo -Value "GoodFolder $($result.Path)`r`n"
                    }
                }
                elseif ($result.Status -eq "Bad" -and ($WhatToLog -eq 'Bad' -or $WhatToLog -eq 'All') -and -not $loggedBad.ContainsKey($result.Path)) {
                    $loggedBad[$result.Path] = $true
                    $folderName = Split-Path $result.Path -Leaf
                    $badType = if ($folderName -match '^\d{4} - .+$') { 'AlbumFolder' } else { 'ArtistFolder' }

                    if ($LogFormat -eq 'JSON') {
                        $logEntry = @{
                            Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                            Status = $result.Status
                            Path = $result.Path
                            Function = 'Find-BadMusicFolderStructure'
                            Type = $badType
                            Reason = $result.Reason
                            Details = $result.Details
                        }

                        # Add structure analysis fields if available
                        if ($result.StructureType) {
                            $logEntry.StructureType = $result.StructureType
                            $logEntry.Confidence = $result.Confidence
                            $logEntry.StructureDetails = $result.StructureDetails
                            $logEntry.Recommendations = $result.Recommendations
                            $logEntry.Metadata = $result.Metadata
                        }

                        $logEntryJson = $logEntry | ConvertTo-Json -Compress
                        Write-LogEntry -Path $LogTo -Value "$logEntryJson`r`n"
                    } else {
                        Write-LogEntry -Path $LogTo -Value "BadFolder $($result.Path) ($($result.Reason))`r`n"
                    }
                }
            }
        }

        if ($Simple) {
            # Backward compatibility: return boolean result
            $uniqueResults = $results | Group-Object -Property Path | ForEach-Object {
                [PSCustomObject]@{ Status = $_.Group[0].Status; Path = $_.Name }
            }

            if ($Good) {
                $uniqueResults | Where-Object { $_.Status -eq 'Good' } | Select-Object -ExpandProperty Path
            }
            else {
                $uniqueResults | Where-Object { $_.Status -eq 'Bad' } | Select-Object -ExpandProperty Path
            }
        }
        else {
            # New detailed result format
            $results
        }

        if ($LogTo) {
            if (-not $Quiet) {
                Write-Host "✅ Measurement complete. Logs Saved at $LogTo"
            }
        }
    }
}
