function Write-LogEntry {
    param(
        [string]$Path,
        [string]$Value
    )
    # Ensure we start on a new line by checking if file ends with newline
    if (Test-Path $Path) {
        $fileInfo = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        if ($fileInfo -and -not $fileInfo.EndsWith("`n")) {
            # File doesn't end with newline, add one before appending
            [System.IO.File]::AppendAllText($Path, "`n", [System.Text.Encoding]::UTF8)
        }
    }
    # Use .NET method to bypass PowerShell WhatIf system
    [System.IO.File]::AppendAllText($Path, $Value, [System.Text.Encoding]::UTF8)
}

function Get-DestinationPath {
    param (
        [Parameter(Mandatory)]
        [string]$SourcePath,
        
        [Parameter(Mandatory)]
        [string]$DestinationFolder
    )
    
    # Extract artist and album from the path (same logic as Move-GoodFolders)
    $parentPath = Split-Path $SourcePath -Parent
    $artist = Split-Path $parentPath -Leaf

    # Handle different path scenarios
    if ($parentPath -match '^[A-Za-z]:\\$') {
        # Parent is drive root (e.g., "E:\") - current folder is the artist
        $artist = Split-Path $SourcePath -Leaf
        $album = ""  # No album subfolder
    } elseif ($artist -match '^([A-Za-z]):\\(.+)$') {
        $artist = $matches[2]
        $album = Split-Path $SourcePath -Leaf
    } else {
        $album = Split-Path $SourcePath -Leaf
    }

    $artistDest = Join-Path $DestinationFolder $artist
    if ($album) {
        $destinationPath = Join-Path $artistDest $album
    } else {
        $destinationPath = $artistDest
    }
    
    return $destinationPath
}

<#
.SYNOPSIS
    Checks music folder structures for compliance with expected naming conventions.
    Automatically logs results to $env:TEMP\MusicFolderChecker\ if no log path is specified.

.DESCRIPTION
    This function recursively scans a starting path for music folders and determines if they follow
    the expected structure: Artist\Year - Album\Track - Title.ext or with Disc folders.
    It returns folders that have bad structure or good structure based on the -Good switch.
    
    When no -LogTo path is provided, results are automatically saved to a timestamped JSON log file
    in $env:TEMP\MusicFolderChecker\ (e.g., MusicFolderStructureScan_20250910_082317.log).
    The log location is displayed at the end of execution.

.PARAMETER StartingPath
    The root path to start scanning for music folders. This can be a directory path.

.PARAMETER Good
    Switch to return only folders with good structure instead of bad ones.

.PARAMETER LogTo
    Optional path to a log file where results will be written. If not specified, logs are automatically
    saved to $env:TEMP\MusicFolderChecker\MusicFolderStructureScan_YYYYMMDD_HHMMSS.log in JSON format.

.PARAMETER WhatToLog
    Specifies what types of folders to log. Options are 'Good', 'Bad', or 'All'. Default is 'All'.

.PARAMETER LogFormat
    Specifies the format for log output. Options are 'Text' or 'JSON'. Default is 'Text' when -LogTo is specified,
    'JSON' when using automatic logging.

.PARAMETER Quiet
    Suppresses verbose output and WhatIf messages for logging operations during scanning.

.PARAMETER Blacklist
    Array of folder paths to exclude from scanning. Supports partial path matching to exclude entire directory trees.

.EXAMPLE
    Find-BadMusicFolderStructure -StartingPath "C:\Music"
    Returns all folders with bad music structure under C:\Music and logs results to automatic temp location.

.EXAMPLE
    Find-BadMusicFolderStructure -StartingPath "C:\Music" -Good
    Returns all folders with good music structure under C:\Music and logs to automatic temp location.

.EXAMPLE
    Get-ChildItem "C:\Music" | Where-Object { $_.PSIsContainer } | Find-BadMusicFolderStructure -LogTo "C:\Logs\structure.log"
    Pipes directories to check and logs results to specified file.

.EXAMPLE
    Find-BadMusicFolderStructure -StartingPath "C:\Music" -LogTo "C:\Logs\good.log" -WhatToLog Good
    Logs only folders with good structure to the specified log file.

.EXAMPLE
    Find-BadMusicFolderStructure -StartingPath "C:\Music" -LogTo "C:\Logs\structure.json" -LogFormat JSON
    Logs results in JSON format to the specified file.

.EXAMPLE
    Find-BadMusicFolderStructure -StartingPath "E:\Music" -WhatToLog Bad
    Scans E:\Music for bad structures and automatically logs to $env:TEMP\MusicFolderChecker\MusicFolderStructureScan_YYYYMMDD_HHMMSS.log

.EXAMPLE
    Find-BadMusicFolderStructure -StartingPath "E:\Music" -WhatToLog Bad -Quiet -WhatIf
    Scans E:\Music quietly, suppressing logging WhatIf messages but showing move WhatIf messages

.EXAMPLE
    Find-BadMusicFolderStructure -StartingPath "E:\allmymusic" -Blacklist "E:\allmymusic\CorrectedMusic", "E:\allmymusic\Archive"
    Scans E:\allmymusic but skips the CorrectedMusic and Archive folders and all their subfolders.

.NOTES
    Supported audio extensions: .mp3, .wav, .flac, .aac, .ogg, .wma
    Automatic logs are saved in JSON format for easy programmatic parsing
    Log location is always displayed at the end of execution
    -Quiet suppresses logging WhatIf messages when used with -WhatIf
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
        $patternDisc = '(?i).*\\([^\\]+)\\\d{4} - [^\\]+(?:\\\\(?:Disc|CD)\\s*\\d+|- (?:Disc|CD)\\d+|)\\\\(?:\\d+-\\d{2}|\\d{2}) - .+\\.[a-z0-9]+$'
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
                    if ($normalizedFolder -eq $normalizedBlacklist -or $normalizedFolder.StartsWith($normalizedBlacklist + '\')) {
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
            if (-not (Test-Path $folder)) {
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
                $artistFolderPath = ($fullPath -split '\\')[0..(($fullPath -split '\\').IndexOf($artistFolderName))] -join '\'
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

<#
.SYNOPSIS
    Saves metadata tags to music files in folders with good structure.

.DESCRIPTION
    This function processes music folders that have good structure (as determined by Find-BadMusicFolderStructure)
    and updates the ID3 tags of audio files based on the folder and file naming conventions.
    It outputs the paths of successfully processed folders to the pipeline.

.PARAMETER FolderPath
    The path to the music folder to process. Accepts pipeline input.

.PARAMETER LogTo
    Optional path to a log file where any errors or issues will be written.

.PARAMETER LogFormat
    Specifies the format for log output. Options are 'Text' or 'JSON'. Default is 'Text'.

.PARAMETER Quiet
    Suppresses verbose output during tagging operations and WhatIf messages for logging.

.PARAMETER hideTags
    Suppresses detailed tag information display in WhatIf mode, showing only the file path.

.PARAMETER Blacklist
    Array of folder paths to exclude from scanning. Supports partial path matching to exclude entire directory trees.

.EXAMPLE
    Save-TagsFromGoodMusicFolders -FolderPath "C:\Music\Artist\2020 - Album"
    Processes the specified folder and tags its music files.

.EXAMPLE
    Find-BadMusicFolderStructure -StartingPath "C:\Music" -Good | Save-TagsFromGoodMusicFolders -LogTo "C:\Logs\tagging.log"
    Finds good folders and pipes them to be tagged, with logging.

.EXAMPLE
    Save-TagsFromGoodMusicFolders -FolderPath "C:\Music\Album" -WhatIf
    Shows what would be tagged without actually making changes.

.EXAMPLE
    Save-TagsFromGoodMusicFolders -FolderPath "C:\Music" -LogTo "C:\Logs\tagging.json" -LogFormat JSON
    Tags music files and logs any errors in JSON format.

.EXAMPLE
    Save-TagsFromGoodMusicFolders -FolderPath "C:\Music" -Quiet -WhatIf
    Shows what would be tagged without verbose output cluttering the results.

.EXAMPLE
    Save-TagsFromGoodMusicFolders -FolderPath "E:\allmymusic" -Blacklist "E:\allmymusic\CorrectedMusic" -WhatIf
    Processes folders in E:\allmymusic but skips the CorrectedMusic folder and all its subfolders.

.NOTES
    Requires TagLib-Sharp.dll in the module's lib directory.
    Only processes folders with compliant structure.
    Outputs successfully processed folder paths.
    Creates CORRUPT_FILES.txt in folders with problematic audio files for easy tracking.
#>
function Save-TagsFromGoodMusicFolders {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$FolderPath,

        [string]$LogTo,

        [Parameter()]
        [ValidateSet('Text', 'JSON')]
        [string]$LogFormat = 'JSON',

        [switch]$Quiet,

        [switch]$hideTags,

        [Parameter()]
        [string[]]$Blacklist
    )

    begin {
        $dllPath = Join-Path $PSScriptRoot "lib\taglib-sharp.dll"
        if (-not (Test-Path $dllPath)) {
            throw "TagLib-Sharp.dll not found at $dllPath. Please ensure the DLL is placed in the module's lib directory."
        }
        Add-Type -Path $dllPath
        [TagLib.Id3v2.Tag]::DefaultVersion = 4
        [TagLib.Id3v2.Tag]::ForceDefaultVersion = $true

        $musicExtensions = @('.mp3', '.flac', '.m4a', '.ogg', '.wav', '.aac')

        $badFolders = @{}
        $goodFolders = @()
        $allCorruptFiles = @{}

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
        # Safety: verify compliance before tagging
        $validationResults = Find-BadMusicFolderStructure -StartingPath $FolderPath -Good -Quiet:$Quiet -Blacklist:$Blacklist -Simple:$false
        
        # Handle both old and new result formats for backward compatibility
        if ($validationResults -is [array] -and $validationResults.Count -gt 0 -and $validationResults[0].PSObject.Properties.Name -contains 'IsValid') {
            # New detailed result format
            $validationResult = $validationResults | Where-Object { $_.Path -eq $FolderPath } | Select-Object -First 1
            
            if (-not $validationResult -or -not $validationResult.IsValid) {
                $reason = if ($validationResult) { $validationResult.Reason } else { "Unknown" }
                $details = if ($validationResult) { $validationResult.Details } else { "Validation failed" }
                
                # Provide specific, user-friendly messages based on failure reason
                switch ($reason) {
                    "Empty" {
                        if (-not $Quiet) {
                            Write-Host "ℹ️  Skipping empty folder: $FolderPath"
                        }
                    }
                    "NoMusicFiles" {
                        if (-not $Quiet) {
                            Write-Host "ℹ️  No music files found in: $FolderPath"
                        }
                    }
                    "CorruptedFile" {
                        Write-Host "WARNING: Corrupted audio file in: $FolderPath - $details" -ForegroundColor Red
                    }
                    "BadStructure" {
                        if (-not $Quiet) {
                            Write-Host "ℹ️  Folder structure doesn't match expected pattern: $FolderPath"
                        }
                    }
                    "Blacklisted" {
                        if (-not $Quiet) {
                            Write-Host "🚫 Skipping blacklisted folder: $FolderPath"
                        }
                    }
                    "NotFound" {
                        Write-Host "WARNING: Folder not found: $FolderPath" -ForegroundColor Red
                    }
                    default {
                        Write-Host "WARNING: Skipping folder ($reason): $FolderPath" -ForegroundColor Red
                    }
                }
                
                if ($LogTo) { 
                    $badFolders[$FolderPath] = @($reason)
                }
                return
            }
        }
        else {
            # Old boolean result format (backward compatibility)
            $isGoodMusic = $validationResults
            if (-not $isGoodMusic) {
                if (-not $Quiet) {
                    Write-Host "ℹ️  Skipping folder (validation failed): $FolderPath"
                }
                if ($LogTo) { $badFolders[$FolderPath] = @("NonCompliant") }
                return
            }
        }

        $musicFiles = Get-ChildItem -LiteralPath $FolderPath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $musicExtensions -contains $_.Extension.ToLower() }

        foreach ($file in $musicFiles) {
            $parts = $file.FullName -split '\\'

            # Extract album info - handle both nested and direct album structures
            $albumIndex = -1
            $year = ""
            $album = ""
            $albumArtist = ""

            for ($i = 1; $i -lt $parts.Count; $i++) {
                if ($parts[$i] -match '^(\d{4})\s*-\s*(.+)$') {
                    $albumIndex = $i
                    $year = $matches[1]
                    $album = $matches[2]
                    # Get artist from the previous part
                    if ($i -gt 1) {
                        $albumArtist = $parts[$i - 1]
                    }
                    break
                }
            }

            # If no album folder found in path, check if current folder is the album folder
            if ($albumIndex -eq -1) {
                $currentFolder = Split-Path $file.DirectoryName -Leaf
                if ($currentFolder -match '^(\d{4})\s*-\s*(.+)$') {
                    $albumIndex = $parts.Count - 1  # Point to the file's directory
                    $year = $matches[1]
                    $album = $matches[2]
                    # Get artist from parent directory
                    $parentDir = Split-Path $file.DirectoryName -Parent
                    $albumArtist = Split-Path $parentDir -Leaf
                }
            }

            if ($albumIndex -ge 1 -and $year -and $album) {
                $albumArtist = $albumArtist  # Already set above
                $fileName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)

                # Extract disc number from directory if it's a CD folder
                $directory = Split-Path $file.FullName -Parent
                $discNumber = 1
                if ($directory -match ".*\\$year - $album - CD(\d+)$") {
                    $discNumber = [uint]$matches[1]
                }

                if ($fileName -match '^([\d-]+)\s*-\s*(.+)$') {
                    $trackNumber = $matches[1]
                    $title = $matches[2].Trim()

                    if ($trackNumber -match '^(?:CD)?(\d+)[.-](\d+)$') {
                        if ($discNumber -eq 1) { $discNumber = [uint]$matches[1] }
                        $trackNumber = [uint]$matches[2]
                    }
                    else {
                        $trackNumber = [uint]$trackNumber
                    }

                    try {
                        $tagFile = [TagLib.File]::Create($file.FullName)
                        $existingGenres = $tagFile.Tag.Genres

                        if ($WhatIfPreference) {
                            if (-not $Quiet -and -not $hideTags) {
                                Write-Host "🔍 [WhatIf] Would tag: $($file.FullName)"
                                if (-not $hideTags) {
                                    Write-Host ("    👥 Album Artist : {0}" -f $albumArtist)
                                    Write-Host ("    🎤 Track Artist : {0}" -f $albumArtist)
                                    Write-Host ("    💿 Album        : {0}" -f $album)
                                    Write-Host ("    📅 Year         : {0}" -f $year)
                                    Write-Host ("    💽 Disc         : {0}" -f $discNumber)
                                    Write-Host ("    🔢 Track        : {0}" -f $trackNumber)
                                    Write-Host ("    🎵 Title        : {0}" -f $title)
                                    Write-Host ("    🎼 Genres       : {0}" -f (($existingGenres -join ', ') -replace '^\s*$', '<none>'))
                                }
                            }
                        }


                        
                        elseif ($PSCmdlet.ShouldProcess($file.FullName, "Update tags")) {
                            
                            
                            # Actual tagging
                            $tagFile.Tag.Title = ""
                            $tagFile.Tag.Performers = @()
                            $tagFile.Tag.AlbumArtists = @()
                            $tagFile.Tag.Album = ""
                            $tagFile.Tag.Comment = ""
                            $tagFile.Tag.Year = 0
                            $tagFile.Tag.Track = 0
                            $tagFile.Tag.Disc = 0
                            $tagFile.Tag.Composers = @()

                            if ($existingGenres) { $tagFile.Tag.Genres = $existingGenres }

                            $tagFile.Tag.Performers = @($albumArtist)
                            $tagFile.Tag.AlbumArtists = @($albumArtist)
                            $tagFile.Tag.Album = $album
                            $tagFile.Tag.Year = [uint]$year
                            $tagFile.Tag.Track = [uint]$trackNumber
                            $tagFile.Tag.Disc = [uint]$discNumber
                            $tagFile.Tag.Title = $title

                            $tagFile.Save()
                            if (-not $Quiet) {
                                Write-Host "✅ Retagged: $($file.Name)"
                            }
                            
                        }
                    }
                    catch {
                        Write-Host "WARNING: ⚠️ Failed to tag: $($file.FullName) — $_" -ForegroundColor Red
                        if (-not $allCorruptFiles.ContainsKey($FolderPath)) {
                            $allCorruptFiles[$FolderPath] = @()
                        }
                        $allCorruptFiles[$FolderPath] += [PSCustomObject]@{
                            FilePath = $file.FullName
                            Error = $_.Exception.Message
                            Reason = "TagLibError"
                        }
                        if ($LogTo) { $badFolders[$FolderPath] += "FailedTagging" }
                    }
                }
                else {
                    Write-Host "WARNING: ❌ Bad filename format: $fileName" -ForegroundColor Red
                    if (-not $allCorruptFiles.ContainsKey($FolderPath)) {
                        $allCorruptFiles[$FolderPath] = @()
                    }
                    $allCorruptFiles[$FolderPath] += [PSCustomObject]@{
                        FilePath = $file.FullName
                        Error = "Bad filename format: $fileName"
                        Reason = "BadFilename"
                    }
                    if ($LogTo) { $badFolders[$FolderPath] += "WrongTitleFormat" }
                }
            }
            else {
                Write-Host "WARNING: ❌ No album folder found: $($file.FullName)" -ForegroundColor Red
                if (-not $allCorruptFiles.ContainsKey($FolderPath)) {
                    $allCorruptFiles[$FolderPath] = @()
                }
                $allCorruptFiles[$FolderPath] += [PSCustomObject]@{
                    FilePath = $file.FullName
                    Error = "No album folder found in path structure"
                    Reason = "NoAlbumFolder"
                }
                if ($LogTo) { $badFolders[$FolderPath] += "ShallowPath" }
            }
        }
        
        # If no errors for this folder, mark as good
        if (-not $badFolders.ContainsKey($FolderPath)) {
            $goodFolders += $FolderPath
        }
    }

    end {
        if ($LogTo -and $badFolders.Count -gt 0) {
            foreach ($folder in $badFolders.Keys) {
                $reasons = ($badFolders[$folder] | Sort-Object -Unique) -join ", "
                if ($LogFormat -eq 'JSON') {
                    $logEntry = @{
                        Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                        Status = 'Error'
                        Path = $folder
                        Function = 'Save-TagsFromGoodMusicFolders'
                        Reasons = $reasons
                        Type = 'TaggingError'
                    } | ConvertTo-Json -Compress
                    Write-LogEntry -Path $LogTo -Value "$logEntry`r`n"
                } else {
                    Write-LogEntry -Path $LogTo -Value "$reasons`: $folder`r`n"
                }
            }
            if (-not $Quiet) {
                Write-Host "📝 Bad folders logged to: $LogTo"
            }
        }
        
        # Output successfully processed folders and corrupt files info
        [PSCustomObject]@{
            GoodFolders = $goodFolders
            CorruptFiles = $allCorruptFiles
        }
    }
}

<#
.SYNOPSIS
    Moves music folders to a specified destination.

.DESCRIPTION
    This function moves music folders from their current location to a destination folder.
    It preserves the folder name and supports pipeline input for batch operations.

.PARAMETER FolderPath
    The path to the folder to move. Accepts pipeline input.

.PARAMETER DestinationFolder
    The destination directory where folders will be moved.

.EXAMPLE
    Move-GoodFolders -FolderPath "C:\Music\Processed\Album1" -DestinationFolder "C:\Archive"
    Moves the specified folder to the archive directory.

.EXAMPLE
    Save-TagsFromGoodMusicFolders -FolderPath "C:\Music" | Move-GoodFolders -DestinationFolder "C:\Processed"
    Tags folders and then moves the successfully processed ones.

.EXAMPLE
    Move-GoodFolders -FolderPath "C:\Music\Album" -DestinationFolder "C:\Backup" -WhatIf
    Shows what would be moved without actually performing the move.

.NOTES
    Creates the destination folder if it doesn't exist.
    Supports -WhatIf and -Confirm parameters.
#>
function Move-GoodFolders {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$FolderPath,

        [Parameter(Mandatory)]
        [string]$DestinationFolder,

        [switch]$Quiet
    )

    begin {
        if (-not (Test-Path $DestinationFolder)) {
            New-Item -ItemType Directory -Path $DestinationFolder -Force -WhatIf:$false | Out-Null
        }
        $movedFoldersByArtist = @{}
    }

    process {
        # Check if this is an artist folder containing album subfolders
        $subfolders = Get-ChildItem -LiteralPath $FolderPath -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer }
        $albumSubfolders = @()
        foreach ($subfolder in $subfolders) {
            if ($subfolder.Name -match '^\d{4} - .+$') {
                $albumSubfolders += $subfolder.FullName
            }
        }

        if ($albumSubfolders) {
            # This is an artist folder, validate and move only good album subfolders
            foreach ($albumFolder in $albumSubfolders) {
                # Re-validate each album subfolder
                $validationResults = Find-BadMusicFolderStructure -StartingPath $albumFolder -Good -Quiet:$Quiet -Simple:$false
                $validationResult = $validationResults | Where-Object { $_.Path -eq $albumFolder } | Select-Object -First 1
                
                if ($validationResult -and $validationResult.IsValid) {
                    # Recursively call Move-GoodFolders on each good album folder
                    $albumFolder | Move-GoodFolders -DestinationFolder $DestinationFolder -WhatIf:$WhatIfPreference -Quiet:$Quiet
                } else {
                    $reason = if ($validationResult) { $validationResult.Reason } else { "Unknown" }
                    if (-not $Quiet) {
                        Write-Host "ℹ️  Skipping album folder ($reason): $albumFolder"
                    }
                }
            }
            return
        }

        # Extract artist and album from the path
        $parentPath = Split-Path $FolderPath -Parent
        $artist = Split-Path $parentPath -Leaf

        # Handle different path scenarios
        if ($parentPath -match '^[A-Za-z]:\\$') {
            # Parent is drive root (e.g., "E:\") - current folder is the artist
            $artist = Split-Path $FolderPath -Leaf
            $album = ""  # No album subfolder
        } elseif ($artist -match '^([A-Za-z]):\\(.+)$') {
            $artist = $matches[2]
            $album = Split-Path $FolderPath -Leaf
        } else {
            $album = Split-Path $FolderPath -Leaf
        }

        $artistDest = Join-Path $DestinationFolder $artist
        if (-not (Test-Path $artistDest)) {
            New-Item -ItemType Directory -Path $artistDest -Force -WhatIf:$false | Out-Null
        }

        if ($album) {
            $destinationPath = Join-Path $artistDest $album
        } else {
            $destinationPath = $artistDest
        }

        if ($WhatIfPreference) {
            Write-Host "What if: Moving `"$FolderPath`"`nto `"$destinationPath`"" -ForegroundColor Yellow
        } elseif ($PSCmdlet.ShouldProcess($destinationPath, "Move")) {
            Move-Item -Path $FolderPath -Destination $destinationPath
            if (-not $Quiet) {
                Write-Host "✅ Moved: $FolderPath to $destinationPath"
            }
            # Track moved folders for summary
            if (-not $movedFoldersByArtist.ContainsKey($artist)) {
                $movedFoldersByArtist[$artist] = @()
            }
            if ($album) {
                $movedFoldersByArtist[$artist] += $album
            } else {
                $movedFoldersByArtist[$artist] += $artist
            }
        }
    }

    end {
        if ($movedFoldersByArtist.Count -gt 0) {
            Write-Host "`n📦 Move Summary:"
            foreach ($artist in ($movedFoldersByArtist.Keys | Sort-Object)) {
                $albums = $movedFoldersByArtist[$artist] | Sort-Object -Unique
                if ($albums.Count -eq 1 -and $albums[0] -eq $artist) {
                    Write-Host ("  - Artist: {0} (entire folder moved)" -f $artist)
                } else {
                    Write-Host ("  - Artist: {0}" -f $artist)
                    foreach ($album in $albums) {
                        Write-Host ("      • {0}" -f $album)
                    }
                }
            }
            Write-Host ""
        }
    }
}

<#
.SYNOPSIS
    Merges album folders into artist subfolders based on metadata.

.DESCRIPTION
    This function reads the album artist from audio files in the provided folders
    and moves each folder into the appropriate artist subfolder in the destination.
    Supports pipeline input and -WhatIf for safe operation.

.PARAMETER FolderPath
    The path to the album folder to process. Accepts pipeline input.

.PARAMETER DestinationFolder
    The destination directory where artist folders will be created.

.EXAMPLE
    Merge-AlbumInArtistFolder -FolderPath "C:\Music\Album1" -DestinationFolder "C:\Organized"
    Moves the folder based on its album artist metadata.

.EXAMPLE
    Get-ChildItem "C:\Music" | Where-Object { $_.PSIsContainer } | Merge-AlbumInArtistFolder -DestinationFolder "C:\Organized" -WhatIf
    Previews moving all album folders to artist-organized structure.

.NOTES
    Requires TagLib-Sharp.dll for reading audio metadata.
    If no album artist is found, the folder is skipped with a warning.
#>
function Merge-AlbumInArtistFolder {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$FolderPath,

        [Parameter(Mandatory)]
        [string]$DestinationFolder
    )

    begin {
        $dllPath = Join-Path $PSScriptRoot "lib\taglib-sharp.dll"
        if (-not (Test-Path $dllPath)) {
            throw "TagLib-Sharp.dll not found at $dllPath. Please ensure the DLL is placed in the module's lib directory."
        }
        Add-Type -Path $dllPath
        [TagLib.Id3v2.Tag]::DefaultVersion = 4
        [TagLib.Id3v2.Tag]::ForceDefaultVersion = $true

        $musicExtensions = @('.mp3', '.flac', '.m4a', '.ogg', '.wav', '.aac')

        if (-not (Test-Path $DestinationFolder)) {
            New-Item -ItemType Directory -Path $DestinationFolder -Force -WhatIf:$false | Out-Null
        }
    }

    process {
        # Find the first audio file in the folder
        $firstAudioFile = $null
        foreach ($extension in $musicExtensions) {
            $firstAudioFile = Get-ChildItem -LiteralPath $FolderPath -File -Filter "*$extension" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($firstAudioFile) { break }
        }

        if (-not $firstAudioFile) {
            Write-Host "WARNING: No audio files found in: $FolderPath" -ForegroundColor Red
            return
        }

        # Read the album artist from the file
        try {
            $tagFile = [TagLib.File]::Create($firstAudioFile.FullName)
            $albumArtist = $tagFile.Tag.AlbumArtists
            if (-not $albumArtist -or $albumArtist.Count -eq 0) {
                $albumArtist = $tagFile.Tag.Performers
            }
            if (-not $albumArtist -or $albumArtist.Count -eq 0) {
                Write-Host "WARNING: No album artist found in: $($firstAudioFile.FullName)" -ForegroundColor Red
                return
            }
            $albumArtist = $albumArtist[0]  # Take the first one
        }
        catch {
            Write-Host "WARNING: Failed to read tags from: $($firstAudioFile.FullName) — $_" -ForegroundColor Red
            return
        }

        if (-not (Test-Path $artistDest)) {
            if ($WhatIfPreference) {
                Write-Host "What if: Creating directory `"$artistDest`"`nand moving `"$FolderPath`" to `"$destinationPath`"" -ForegroundColor Yellow
            } elseif ($PSCmdlet.ShouldProcess($artistDest, "Create directory")) {
                New-Item -ItemType Directory -Path $artistDest -Force -WhatIf:$false | Out-Null
            }
        }

        $folderName = Split-Path $FolderPath -Leaf
        $destinationPath = Join-Path $artistDest $folderName

        if ($WhatIfPreference) {
            Write-Host "What if: Moving `"$FolderPath`"`nto `"$destinationPath`"" -ForegroundColor Yellow
        } elseif ($PSCmdlet.ShouldProcess($destinationPath, "Move")) {
            Move-Item -Path $FolderPath -Destination $destinationPath
            Write-Host "✅ Merged: $FolderPath to $destinationPath"
        }
    }
}

<#
.SYNOPSIS
    Imports and processes music folders from a log file by tagging and moving them.

.DESCRIPTION
    This function reads a log file (JSON or text format) containing folder information,
    filters the entries by status, and processes the folders by tagging their music files
    and moving them to a destination folder. Much cleaner than complex pipeline commands.

    SPECIAL FEATURE: Folders that cannot be processed (due to missing files, permission issues,
    or other problems) are automatically marked as 'CheckThisGoodOne' in the log file. This
    prevents them from being re-processed on subsequent runs, allowing you to focus on
    folders that can be handled automatically while keeping track of problematic ones for
    manual review.

.PARAMETER LogFile
    Path to the log file to process. Supports both JSON and text formats.

.PARAMETER Status
    Filter entries by status. Options are 'Good', 'Bad', 'CheckThisGoodOne', or 'All'. Default is 'Good'.
    'CheckThisGoodOne' entries are folders that were marked for manual review after processing failed.

.PARAMETER DestinationFolder
    The destination directory where processed folders will be moved.

.PARAMETER MaxItems
    Maximum number of folders to process. Default is to process all matching entries.

.PARAMETER LogFormat
    Format of the log file. Options are 'Auto' (detect automatically), 'JSON', or 'Text'. Default is 'Auto'.

.PARAMETER Quiet
    Suppresses verbose output during tagging operations and WhatIf messages for logging.

.PARAMETER hideTags
    Suppresses detailed tag information display in WhatIf mode, showing only the file path.

.PARAMETER DetailedLog
    Enables detailed logging during dry runs (-WhatIf), showing specific reasons for folder processing outcomes.

.EXAMPLE
    Import-LoggedFolders -LogFile "C:\Logs\structure.json" -DestinationFolder "E:\CorrectedMusic" -DetailedLog -WhatIf
    Processes folders with detailed logging to see specific validation results for each folder.

.EXAMPLE
    Import-LoggedFolders -LogFile "C:\Logs\structure.json" -DestinationFolder "E:\CorrectedMusic" -Quiet -WhatIf
    Processes folders quietly, showing only essential moving information.

.EXAMPLE
    Import-LoggedFolders -LogFile "C:\Logs\structure.json" -Status "CheckThisGoodOne" -WhatIf
    Shows all folders that were marked for manual review after processing failed.

.EXAMPLE
    Import-LoggedFolders -LogFile "C:\Logs\structure.json" -Status "All" -DestinationFolder "E:\CorrectedMusic" -MaxItems 5
    Processes up to 5 folders of any status (Good, Bad, or CheckThisGoodOne).

.EXAMPLE
    Import-LoggedFolders -LogFile "C:\Logs\structure.json" -Status "Good" -DestinationFolder "E:\CorrectedMusic" -DetailedLog
    Processes only Good folders with detailed logging. Problematic folders get marked as CheckThisGoodOne.

.NOTES
    Automatically detects log format if set to 'Auto'.
    Supports -WhatIf and -Confirm parameters for safe operation.
    Requires TagLib-Sharp.dll for tagging operations.

    IMPORTANT: You may notice duplicate "🔍 Checking folder" and "✅ Measurement complete"
    messages for the same folder. This is normal behavior - the function performs layered
    validation for safety by checking folder structure both before tagging AND before moving.
    This double-checking ensures data integrity and is not an error.

    CHECKTHISGOODONE WORKFLOW:
    - Folders that can't be processed are marked as 'CheckThisGoodOne' in the log
    - These entries are skipped on subsequent runs (when Status='Good')
    - Use Status='CheckThisGoodOne' to view folders needing manual attention
    - Use Status='All' to process everything including marked folders
    - This helps you focus on automatable folders while tracking problematic ones
    
    CORRUPT FILES TRACKING:
    - When audio files can't be tagged, they're listed in CORRUPT_FILES.txt in the destination folder
    - This file contains detailed error information for each problematic file
    - The file is automatically moved with the folder for easy reference
#>
function Import-LoggedFolders {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [string]$LogFile,

        [Parameter()]
        [ValidateSet('Good', 'Bad', 'CheckThisGoodOne', 'All')]
        [string]$Status = 'Good',

        [Parameter(Mandatory)]
        [string]$DestinationFolder,

        [Parameter()]
        [int]$MaxItems,

        [Parameter()]
        [ValidateSet('Auto', 'JSON', 'Text')]
        [string]$LogFormat = 'Auto',

        [switch]$Quiet,

        [switch]$hideTags,

        [switch]$DetailedLog  # New parameter for detailed logging during dry runs
    )

    # Validate log file exists
    if (-not (Test-Path $LogFile)) {
        throw "Log file not found: $LogFile"
    }

    # Read and parse log file
    try {
        $logContent = Get-Content -Path $LogFile -Raw

        if ($LogFormat -eq 'Auto') {
            # Try to detect format
            if ($logContent.TrimStart().StartsWith('{')) {
                $LogFormat = 'JSON'
            } else {
                $LogFormat = 'Text'
            }
        }

        if ($LogFormat -eq 'JSON') {
            # Parse JSON (one object per line)
            $logEntries = $logContent -split "`n" | Where-Object { $_ -match '\S' } | ForEach-Object {
                try {
                    $_ | ConvertFrom-Json
                } catch {
                    Write-Host "WARNING: Skipping malformed JSON line: $_" -ForegroundColor Red
                    $null
                }
            } | Where-Object { $_ -ne $null }
        } else {
            # Parse text format
            $logEntries = $logContent -split "`n" | Where-Object { $_ -match '\S' } | ForEach-Object {
                $line = $_.Trim()
                if ($line -match '^(GoodFolder|BadFolder|CheckThisGoodOne)\s+(.+)$') {
                    [PSCustomObject]@{
                        Status = if ($matches[1] -eq 'GoodFolder') { 'Good' } elseif ($matches[1] -eq 'CheckThisGoodOne') { 'CheckThisGoodOne' } else { 'Bad' }
                        Path = $matches[2]
                        Function = 'Find-BadMusicFolderStructure'
                        Type = if ($matches[1] -eq 'GoodFolder' -or $matches[1] -eq 'CheckThisGoodOne') { 'ArtistFolder' } else { 'AlbumFolder' }
                    }
                } elseif ($line -match '^GoodFolder\s+(.+)$') {
                    # Handle lines that might have extra spaces or formatting issues
                    [PSCustomObject]@{
                        Status = 'Good'
                        Path = $matches[1]
                        Function = 'Find-BadMusicFolderStructure'
                        Type = 'ArtistFolder'
                    }
                } else {
                    if (-not $Quiet -and $line -notmatch '^\s*$') {
                        Write-Host "WARNING: Skipping malformed text line: '$line'" -ForegroundColor Red
                    }
                    $null
                }
            } | Where-Object { $_ -ne $null }
        }
    }
    catch {
        throw "Failed to read log file: $_"
    }

    # Filter entries by status
    if ($Status -ne 'All') {
        $logEntries = $logEntries | Where-Object { $_.Status -eq $Status }
    }

    # Limit number of items if specified
    if ($MaxItems -and $MaxItems -gt 0) {
        $logEntries = $logEntries | Select-Object -First $MaxItems
    }

    if (-not $logEntries -or $logEntries.Count -eq 0) {
        if (-not $Quiet) {
        Write-Host "No matching entries found in log file."
    }
        return
    }

    if (-not $Quiet) {
        Write-Host "Found $($logEntries.Count) folders to process..."
    }

    # Process each folder
    $processedCount = 0
    $processedEntries = @()
    foreach ($entry in $logEntries) {
        $folderPath = $entry.Path

        if (-not (Test-Path $folderPath)) {
            Write-Host "WARNING: Folder not found, skipping: $folderPath" -ForegroundColor Red
            continue
        }

        if (-not $Quiet) {
            Write-Host "Processing: $folderPath"
        }

        try {
            # Tag the folder (this will validate it's still good)
            $taggingResult = Save-TagsFromGoodMusicFolders -FolderPath $folderPath -WhatIf:$WhatIfPreference -Quiet:$Quiet -hideTags:$hideTags
            $taggedFolders = $taggingResult.GoodFolders
            $corruptFiles = $taggingResult.CorruptFiles
            
            if (-not $Quiet) {
                Write-Host "DEBUG: taggedFolders result for $folderPath = '$taggedFolders'" -ForegroundColor Cyan
                if ($corruptFiles.ContainsKey($folderPath)) {
                    Write-Host "DEBUG: Found $($corruptFiles[$folderPath].Count) corrupt files in $folderPath" -ForegroundColor Yellow
                }
            }

            if ($taggedFolders) {
                # Move the successfully tagged folder
                $taggedFolders | Move-GoodFolders -DestinationFolder $DestinationFolder -WhatIf:$WhatIfPreference -Quiet:$Quiet
                
                # Create corrupt files log in destination if any corrupt files were found
                if ($corruptFiles.ContainsKey($folderPath) -and $corruptFiles[$folderPath].Count -gt 0 -and -not $WhatIfPreference) {
                    # Get the destination path for this folder
                    $destinationPath = Get-DestinationPath -SourcePath $folderPath -DestinationFolder $DestinationFolder
                    
                    if (Test-Path $destinationPath) {
                        $corruptFilePath = Join-Path $destinationPath "CORRUPT_FILES.txt"
                        $corruptContent = @"
CORRUPT OR PROBLEMATIC FILES FOUND
==================================
Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Source Folder: $folderPath
Destination Folder: $destinationPath
Total files with issues: $($corruptFiles[$folderPath].Count)

DETAILS:
"@
                        foreach ($corruptFile in $corruptFiles[$folderPath]) {
                            # Convert source path to destination path for the corrupt file
                            $relativePath = $corruptFile.FilePath -replace [regex]::Escape($folderPath), ""
                            $destFilePath = Join-Path $destinationPath $relativePath.TrimStart('\')
                            
                            $corruptContent += @"

FILE: $($destFilePath)
REASON: $($corruptFile.Reason)
ERROR: $($corruptFile.Error)
"@
                        }
                        
                        $corruptContent += @"

==================================
These files could not be processed automatically.
Please check and fix them manually before re-processing.
"@
                        
                        try {
                            $corruptContent | Out-File -FilePath $corruptFilePath -Encoding UTF8 -WhatIf:$false
                            if (-not $Quiet) {
                                Write-Host "📝 Created corrupt files log: $corruptFilePath" -ForegroundColor Yellow
                            }
                        }
                        catch {
                            Write-Host "WARNING: Failed to create corrupt files log: $_" -ForegroundColor Red
                        }
                    }
                }
                
                $processedCount++
                $processedEntries += $entry
                
                if ($DetailedLog -and $WhatIfPreference) {
                    Write-Host "📝 [DetailedLog] Successfully processed: $folderPath" -ForegroundColor Green
                }
            } else {
                # Save-TagsFromGoodMusicFolders already provided specific error messages
                # Only show generic message if DetailedLog is requested
                if (-not $Quiet) {
                    Write-Host "DEBUG: Entering CheckThisGoodOne marking block for $folderPath" -ForegroundColor Magenta
                }
                if ($DetailedLog) {
                    Write-Host "📝 [DetailedLog] No files processed in: $folderPath" -ForegroundColor Yellow
                }
                
                # Mark this entry as needing manual review by appending "CheckThisGoodOne" entry
                # and removing the original "GoodFolder" entry
                # Note: We do this even during -WhatIf since it's just updating the log file metadata
                try {
                    if (-not $Quiet) {
                        Write-Host "DEBUG: Starting log file update process" -ForegroundColor Magenta
                    }
                    
                    # First, remove the original "GoodFolder" entry
                    $updatedContent = $logContent
                    if ($LogFormat -eq 'JSON') {
                        # For JSON, find and remove the original entry
                        if (-not $Quiet) {
                            Write-Host "DEBUG: Removing original JSON entry for $folderPath" -ForegroundColor Cyan
                        }
                        $originalEntry = @{
                            Timestamp = $entry.Timestamp
                            Status = 'Good'
                            Path = $folderPath
                            Function = $entry.Function
                            Type = $entry.Type
                        } | ConvertTo-Json -Compress
                        $updatedContent = $updatedContent -replace [regex]::Escape("$originalEntry`r`n"), ""
                        $updatedContent = $updatedContent -replace [regex]::Escape("$originalEntry`n"), ""
                        $updatedContent = $updatedContent -replace [regex]::Escape($originalEntry), ""
                    } else {
                        # For text format, remove the original "GoodFolder" line
                        if (-not $Quiet) {
                            Write-Host "DEBUG: Removing original text entry for $folderPath" -ForegroundColor Cyan
                        }

                        # More robust line removal - split into lines, remove matching line, rejoin
                        $lines = $updatedContent -split "`n"
                        $targetLine = "GoodFolder $folderPath"
                        $lines = $lines | Where-Object {
                            $_.Trim() -ne $targetLine -and
                            $_.Trim() -ne "$targetLine`r" -and
                            $_ -ne $targetLine
                        }
                        $updatedContent = $lines -join "`n"
                    }
                    
                    # Write back the updated content (removing original entry)
                    if ($updatedContent.Trim() -ne $logContent.Trim()) {
                        [System.IO.File]::WriteAllText($LogFile, $updatedContent.Trim(), [System.Text.Encoding]::UTF8)
                        if (-not $Quiet) {
                            Write-Host "DEBUG: Removed original entry for $folderPath" -ForegroundColor Green
                        }
                    }
                    
                    # Then append the new CheckThisGoodOne entry
                    if ($LogFormat -eq 'JSON') {
                        # For JSON format, create a new CheckThisGoodOne entry
                        if (-not $Quiet) {
                            Write-Host "DEBUG: Appending CheckThisGoodOne JSON entry for $folderPath" -ForegroundColor Cyan
                        }
                        $checkThisEntry = @{
                            Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                            Status = 'CheckThisGoodOne'
                            Path = $folderPath
                            Function = 'Import-LoggedFolders'
                            Type = 'ArtistFolder'
                        } | ConvertTo-Json -Compress
                        Write-LogEntry -Path $LogFile -Value "$checkThisEntry`r`n"
                    } else {
                        # For text format, append the CheckThisGoodOne entry
                        if (-not $Quiet) {
                            Write-Host "DEBUG: Appending CheckThisGoodOne text entry for $folderPath" -ForegroundColor Cyan
                        }
                        Write-LogEntry -Path $LogFile -Value "CheckThisGoodOne $folderPath`r`n"
                    }
                    
                    if (-not $Quiet) {
                        if ($WhatIfPreference) {
                            Write-Host "📝 [WhatIf] Would mark folder for manual review: $folderPath" -ForegroundColor Cyan
                        } else {
                            Write-Host "📝 Marked folder for manual review: $folderPath"
                        }
                    }
                }
                catch {
                    Write-Host "WARNING: Failed to append log entry for manual review: $_" -ForegroundColor Red
                }
            }
        }
        catch {
            Write-Host "WARNING: Error processing folder $folderPath`: $_" -ForegroundColor Red
            if ($DetailedLog) {
                Write-Host "📝 [DetailedLog] Exception details: $_" -ForegroundColor Red
            }
        }
    }

    # Remove processed entries from log file
    if ($processedEntries.Count -gt 0 -and -not $WhatIfPreference) {
        try {
            $updatedContent = $logContent
            foreach ($processedEntry in $processedEntries) {
                if ($LogFormat -eq 'JSON') {
                    # For JSON, find and remove the line containing this entry
                    $entryJson = $processedEntry | ConvertTo-Json -Compress
                    $updatedContent = $updatedContent -replace [regex]::Escape("$entryJson`r`n"), ""
                    $updatedContent = $updatedContent -replace [regex]::Escape("$entryJson`n"), ""
                    $updatedContent = $updatedContent -replace [regex]::Escape($entryJson), ""
                } else {
                    # For text format, remove the line using robust line-by-line approach
                    $lines = $updatedContent -split "`n"
                    $targetLines = @(
                        "GoodFolder $($processedEntry.Path)",
                        "CheckThisGoodOne $($processedEntry.Path)"
                    )
                    $lines = $lines | Where-Object {
                        $line = $_.Trim()
                        -not ($targetLines | Where-Object { $line -eq $_ -or $line -eq "$_`r" -or $_ -eq $line })
                    }
                    $updatedContent = $lines -join "`n"
                }
            }
            
            # Write back the updated content
            if ($updatedContent.Trim() -ne $logContent.Trim()) {
                # Use .NET method to bypass PowerShell's WhatIf mechanism for log file updates
                [System.IO.File]::WriteAllText($LogFile, $updatedContent.Trim(), [System.Text.Encoding]::UTF8)
                if (-not $Quiet) {
                    Write-Host "📝 Removed $($processedEntries.Count) processed entries from log file"
                }
            }
        }
        catch {
            Write-Host "WARNING: Failed to update log file: $_" -ForegroundColor Red
        }
    }

    if (-not $Quiet) {
        Write-Host "✅ Completed processing $processedCount folders."
    }
}