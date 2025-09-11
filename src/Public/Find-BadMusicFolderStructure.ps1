<#
.SYNOPSIS
    Checks music folder structures for compliance with expected naming conventions.
    Automatically logs results to $env:TEMP\MusicFolderChecker\ if no log path is specified.
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
        [string]$LogFormat = 'Text',

        [switch]$Quiet,

        [Parameter()]
        [string[]]$Blacklist,

        [switch]$Simple  # New parameter for backward compatibility
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
        $loggedGood = @{}
        $loggedBad = @{}
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

            # Check if folder is in blacklist
            if ($Blacklist) {
                $isBlacklisted = $false
                foreach ($blacklistedPath in $Blacklist) {
                    # Normalize paths for comparison (handle trailing slashes, case sensitivity)
                    $normalizedFolder = $folder.TrimEnd('\').ToLower()
                    $normalizedBlacklist = $blacklistedPath.TrimEnd('\').ToLower()

                    # Check if folder path starts with blacklisted path (handles subfolders)
                    if ($normalizedFolder -eq $normalizedBlacklist -or $normalizedFolder.StartsWith($normalizedBlacklist + '\\')) {
                        $isBlacklisted = $true
                        break
                    }
                }
                if ($isBlacklisted) {
                    $validationResult.Reason = "Blacklisted"
                    $validationResult.Details = "Folder is in blacklist"
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
                $dllPath = Join-Path $PSScriptRoot "lib\taglib-sharp.dll"
                if (Test-Path $dllPath) {
                    Add-Type -Path $dllPath -ErrorAction SilentlyContinue
                    [TagLib.File]::Create($firstAudioFile.FullName) | Out-Null
                    # File is readable
                }
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
                $artistFolderName = $matches[1]
                $artistFolderPath = ($fullPath -split '\\')[0..(($fullPath -split '\\').IndexOf($artistFolderName))] -join '\\'
                $validationResult.IsValid = $true
                $validationResult.Reason = "Valid"
                $validationResult.Details = "Matches expected folder structure"
                $validationResult.Status = "Good"
                $results += $validationResult

                if ($LogTo -and ($WhatToLog -eq 'Good' -or $WhatToLog -eq 'All') -and -not $loggedGood.ContainsKey($artistFolderPath)) {
                    $loggedGood[$artistFolderPath] = $true
                    if ($LogFormat -eq 'JSON') {
                        $logEntry = @{
                            Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                            Status = 'Good'
                            Path = $artistFolderPath
                            Function = 'Find-BadMusicFolderStructure'
                            Type = 'ArtistFolder'
                        } | ConvertTo-Json -Compress
                        Write-LogEntry -Path $LogTo -Value "$logEntry`r`n"
                    } else {
                        Write-LogEntry -Path $LogTo -Value "GoodFolder $artistFolderPath`r`n"
                    }
                }
            }
            else {
                $badFolder = $firstAudioFile.DirectoryName
                $validationResult.Reason = "BadStructure"
                $validationResult.Details = "Audio files found but folder structure doesn't match expected pattern"
                $validationResult.Status = "Bad"
                $results += $validationResult

                if ($LogTo -and ($WhatToLog -eq 'Bad' -or $WhatToLog -eq 'All') -and -not $loggedBad.ContainsKey($badFolder)) {
                    $loggedBad[$badFolder] = $true
                    # Determine the type based on folder name
                    $folderName = Split-Path $badFolder -Leaf
                    $badType = if ($folderName -match '^\d{4} - .+$') { 'AlbumFolder' } else { 'ArtistFolder' }
                    if ($LogFormat -eq 'JSON') {
                        $logEntry = @{
                            Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                            Status = 'Bad'
                            Path = $badFolder
                            Function = 'Find-BadMusicFolderStructure'
                            Type = $badType
                            Reason = $validationResult.Reason
                            Details = $validationResult.Details
                        } | ConvertTo-Json -Compress
                        Write-LogEntry -Path $LogTo -Value "$logEntry`r`n"
                    } else {
                        Write-LogEntry -Path $LogTo -Value "BadFolder $badFolder ($($validationResult.Reason))`r`n"
                    }
                }
            }
        }
    }

    end {
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
