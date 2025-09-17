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
    The root directory path(s) to begin scanning. This parameter is mandatory and accepts pipeline input.
    Can be a single path or multiple paths.

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

.PARAMETER AnalysisMode
    Controls the depth of structure analysis when -AnalyzeStructure is used. Valid values: 'Basic', 'Deep'.
    - Basic: Standard analysis (default)
    - Deep: Enables consensus-based hints and alternative BoxSet detection for ambiguous/nested collections

.INPUTS
    System.String
    You can pipe folder paths to Find-BadMusicFolderStructure.

.OUTPUTS
    PSCustomObject or System.Boolean
    Returns detailed validation objects with Path, IsValid, Reason, Details, and Status properties.
    With -Simple switch, returns boolean values.

.EXAMPLE
    Find-BadMusicFolderStructure -StartingPath 'E:\Music','E:\MoreMusic'
    Scans multiple directories and returns detailed validation results for all folders.

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
        [string[]]$StartingPath,

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

        [switch]$AnalyzeStructure,  # Enhanced analysis with structure type detection

        [ValidateSet('Basic','Deep')]
        [string]$AnalysisMode = 'Basic'
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
        # Filter out files from StartingPath - only process folders
        $startingFolders = @()
        foreach ($path in $StartingPath) {
            if (Test-Path -LiteralPath $path) {
                $item = Get-Item -LiteralPath $path
                if ($item.PSIsContainer) {
                    $startingFolders += $path
                } else {
                    Write-Warning "Skipping file (not a folder): $path"
                }
            } else {
                Write-Warning "Path not found: $path"
            }
        }

        if ($startingFolders.Count -eq 0) {
            Write-Warning "No valid folders found to process"
            return
        }

        $folders = @($startingFolders) + (Get-ChildItem -LiteralPath $startingFolders -Recurse | Where-Object { $_.PSIsContainer } | Sort-Object -Unique | ForEach-Object { $_.FullName }) | Select-Object -Unique

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

            # Skip obvious collection root folders
            $folderName = Split-Path $folder -Leaf
            if ($folderName -match '^(?i)(music|audio|collection|library|media|sound|mp3|flac)$' -or 
                $folder -match '^[A-Za-z]:\\$') {
                $validationResult.Reason = "CollectionRoot"
                $validationResult.Details = "Appears to be a collection root folder - should not be validated individually"
                $validationResult.Status = "Skipped"
                $results += $validationResult
                continue
            }

            # Basic folder existence/emptiness checks
            if (-not (Test-Path -LiteralPath $folder)) {
                $validationResult.Reason = "NotFound"
                $validationResult.Details = "Folder does not exist"
                $validationResult.Status = "Error"
                $results += $validationResult
                continue
            }

            $allItems = Get-ChildItem -LiteralPath $folder -ErrorAction SilentlyContinue
            if (-not $allItems -or $allItems.Count -eq 0) {
                $validationResult.Reason = "Empty"
                $validationResult.Details = "Folder contains no files or subfolders"
                $validationResult.Status = "Bad"
                $results += $validationResult
                continue
            }

            # Authoritative classification via analyzer
            try {
                if ($AnalysisMode -eq 'Deep') {
                    $structureAnalysis = Get-FolderStructureAnalysis -Path $folder -UseConsensusHints:$true
                } else {
                    $structureAnalysis = Get-FolderStructureAnalysis -Path $folder
                }
            } catch {
                $validationResult.Reason = "AnalysisFailed"
                $validationResult.Details = $_.ToString()
                $validationResult.Status = "Error"
                $results += $validationResult
                continue
            }

            # Map StructureType -> Good/Bad/Skipped
            $st = $structureAnalysis.StructureType
            switch ($st) {
                'ArtistFolder' {
                    $validationResult.IsValid = $true
                    $validationResult.Status = 'Good'
                    $validationResult.Reason = 'ArtistFolder'
                    $validationResult.Details = ($structureAnalysis.Details -join '; ')
                }
                'SimpleAlbum' {
                    $validationResult.IsValid = $true
                    $validationResult.Status = 'Good'
                    $validationResult.Reason = 'SimpleAlbum'
                    $validationResult.Details = ($structureAnalysis.Details -join '; ')
                }
                'MultiDiscAlbum' {
                    $validationResult.IsValid = $true
                    $validationResult.Status = 'Good'
                    $validationResult.Reason = 'MultiDiscAlbum'
                    $validationResult.Details = ($structureAnalysis.Details -join '; ')
                }
                'CompilationFolder' {
                    $validationResult.IsValid = $true
                    $validationResult.Status = 'Good'
                    $validationResult.Reason = 'CompilationFolder'
                    $validationResult.Details = ($structureAnalysis.Details -join '; ')
                }
                'BoxSet' {
                    $validationResult.IsValid = $true
                    $validationResult.Status = 'Good'
                    $validationResult.Reason = 'BoxSet'
                    $validationResult.Details = ($structureAnalysis.Details -join '; ')
                }
                'MixedAlbum' {
                    $validationResult.IsValid = $false
                    $validationResult.Status = 'Bad'
                    $validationResult.Reason = 'MixedAlbum'
                    $validationResult.Details = ($structureAnalysis.Details -join '; ')
                }
                'AmbiguousStructure' {
                    $validationResult.IsValid = $false
                    $validationResult.Status = 'Bad'
                    $validationResult.Reason = 'AmbiguousStructure'
                    $validationResult.Details = ($structureAnalysis.Details -join '; ')
                }
                'NonMusicFolder' {
                    $validationResult.IsValid = $false
                    $validationResult.Status = 'Bad'
                    $validationResult.Reason = 'NonMusicFolder'
                    $validationResult.Details = ($structureAnalysis.Details -join '; ')
                }
                default {
                    $validationResult.IsValid = $false
                    $validationResult.Status = 'Bad'
                    $validationResult.Reason = $st
                    $validationResult.Details = ($structureAnalysis.Details -join '; ')
                }
            }

            # Naming conformance (regex) as a note for album types
            try {
                $firstAudio = Get-ChildItem -LiteralPath $folder -Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object { $audioExtensions -contains $_.Extension.ToLower() } | Select-Object -First 1
                if ($firstAudio) {
                    $fullPath = $firstAudio.FullName
                    $conforms = ($fullPath -match $patternMain -or $fullPath -match $patternDisc)
                    if (-not $conforms -and ($st -in @('SimpleAlbum','MultiDiscAlbum'))) {
                        $validationResult.Details = ((@($validationResult.Details) + 'NamingNonConformant') -join '; ')
                    }
                }
            } catch { }

            # Attach analyzer fields when AnalyzeStructure is requested
            if ($AnalyzeStructure) {
                $validationResult | Add-Member -MemberType NoteProperty -Name 'StructureType' -Value $structureAnalysis.StructureType -Force
                $validationResult | Add-Member -MemberType NoteProperty -Name 'Confidence' -Value $structureAnalysis.Confidence -Force
                $validationResult | Add-Member -MemberType NoteProperty -Name 'StructureDetails' -Value ($structureAnalysis.Details -join '; ') -Force
                $validationResult | Add-Member -MemberType NoteProperty -Name 'Recommendations' -Value ($structureAnalysis.Recommendations -join '; ') -Force
                $validationResult | Add-Member -MemberType NoteProperty -Name 'Metadata' -Value $structureAnalysis.Metadata -Force
            }

            $results += $validationResult
            continue
        }
    }

    end {
        # If AnalyzeStructure is requested, enhance results with structure analysis
        if ($AnalyzeStructure) {
            $enhancedResults = @()
            foreach ($result in $results) {
                if ($result.Status -ne "Skipped" -and $result.Status -ne "Error") {
                    try {
                        # If already has structure fields, skip re-analysis
                        if ($result.PSObject.Properties['StructureType']) {
                            $enhancedResults += $result
                            continue
                        }
                        # Forward depth mode to analyzer; Deep enables consensus-based hints
                        if ($AnalysisMode -eq 'Deep') { $structureAnalysis = Get-FolderStructureAnalysis -Path $result.Path -UseConsensusHints:$true }
                        else { $structureAnalysis = Get-FolderStructureAnalysis -Path $result.Path }
                        
                        # Skip only if analysis says it's a file, or if it explicitly says it doesn't exist
                        $isFile = $false; $notExists = $false
                        try { if ($structureAnalysis.Metadata.IsFile) { $isFile = $true } } catch { }
                        try { if ($structureAnalysis.Metadata.ContainsKey('Exists') -and -not $structureAnalysis.Metadata.Exists) { $notExists = $true } } catch { }
                        if ($isFile -or $notExists) {
                            # Don't enhance results for files or non-existent paths
                            $enhancedResults += $result
                            continue
                        }
                        
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

                        $logEntryJson = $logEntry | ConvertTo-Json -Depth 8 -Compress
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

                        $logEntryJson = $logEntry | ConvertTo-Json -Depth 8 -Compress
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
