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

.EXAMPLE
    Find-BadMusicFolderStructure -StartingPath "C:\Music"
    Returns all folders with bad music structure under C:\Music and logs results to automatic temp location.

.EXAMPLE
    Find-BadMusicFolderStructure -StartingPath "C:\Music" -Good
    Returns all folders with good music structure under C:\Music and logs to automatic temp location.

.EXAMPLE
    Get-ChildItem "C:\Music" -Directory | Find-BadMusicFolderStructure -LogTo "C:\Logs\structure.log"
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

.NOTES
    Supported audio extensions: .mp3, .wav, .flac, .aac, .ogg, .wma
    Automatic logs are saved in JSON format for easy programmatic parsing
    Log location is always displayed at the end of execution
#>
function Find-BadMusicFolderStructure {
    [CmdletBinding()]
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
        [string]$LogFormat = 'Text'
    )

    begin {
        $audioExtensions = @(".mp3", ".wav", ".flac", ".aac", ".ogg", ".wma")
        $patternMain = '(?i).*\\([^\\]+)\\\d{4} - (?!.*(?:CD|Disc)\d+)[^\\]+\\\d{2} - .+\.[a-z0-9]+$'
        $patternDisc = '(?i).*\\([^\\]+)\\\d{4} - [^\\]+(?:\\Disc \d+|- CD\d+)\\\d{2} - .+\.[a-z0-9]+$'
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
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }
            # Don't initialize with empty string to avoid malformed JSON
        }
    }

    process {
        $folders = @($StartingPath) + (Get-ChildItem -LiteralPath $StartingPath -Recurse -Directory | Sort-Object -Unique | ForEach-Object { $_.FullName })

        foreach ($folder in $folders) {
            Write-Host "🔍 Checking folder: $folder"

            $firstAudioFile = $null
            foreach ($extension in $audioExtensions) {
                $firstAudioFile = Get-ChildItem -LiteralPath $folder -File -Filter "*$extension" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($firstAudioFile) { break }
            }
            if (-not $firstAudioFile) { continue }

            $fullPath = $firstAudioFile.FullName
            if ($fullPath -match $patternMain -or $fullPath -match $patternDisc) {
                $artistFolderName = $matches[1]
                $artistFolderPath = ($fullPath -split '\\')[0..(($fullPath -split '\\').IndexOf($artistFolderName))] -join '\'
                $results += [PSCustomObject]@{ Status = 'Good'; StartingPath = $folder }
                if ($LogTo -and ($WhatToLog -eq 'Good' -or $WhatToLog -eq 'All')) {
                    if ($LogFormat -eq 'JSON') {
                        $logEntry = @{
                            Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                            Status = 'Good'
                            Path = $artistFolderPath
                            Function = 'Find-BadMusicFolderStructure'
                            Type = 'ArtistFolder'
                        } | ConvertTo-Json -Compress
                        Add-Content -Path $LogTo -Value $logEntry
                    } else {
                        Add-Content -Path $LogTo -Value ("GoodFolder " + ($artistFolderPath))
                    }
                }
            }
            else {
                $badFolder = $firstAudioFile.DirectoryName
                $results += [PSCustomObject]@{ Status = 'Bad'; StartingPath = $badFolder }
                if ($LogTo -and ($WhatToLog -eq 'Bad' -or $WhatToLog -eq 'All')) {
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
                        } | ConvertTo-Json -Compress
                        Add-Content -Path $LogTo -Value $logEntry
                    } else {
                        Add-Content -Path $LogTo -Value ("BadFolder " + ($badFolder))
                    }
                }
            }
        }
    }

    end {
        $uniqueResults = $results | Group-Object -Property StartingPath | ForEach-Object {
            [PSCustomObject]@{ Status = $_.Group[0].Status; StartingPath = $_.Name }
        }

        if ($Good) {
            $uniqueResults | Where-Object { $_.Status -eq 'Good' } | Select-Object StartingPath
        }
        else {
            $uniqueResults | Where-Object { $_.Status -eq 'Bad' } | Select-Object StartingPath
        }
        if ($LogTo) {
            Write-Host "✅ Measurement complete. Logs Saved at $LogTo"
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
    Suppresses verbose output during tagging operations.

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

.NOTES
    Requires TagLib-Sharp.dll in the module's lib directory.
    Only processes folders with compliant structure.
    Outputs successfully processed folder paths.
#>
function Save-TagsFromGoodMusicFolders {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$FolderPath,

        [string]$LogTo,

        [Parameter()]
        [ValidateSet('Text', 'JSON')]
        [string]$LogFormat = 'Text',

        [switch]$Quiet
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

        if ($LogTo) {
            $logDir = Split-Path -Path $LogTo -Parent
            if (-not (Test-Path -Path $logDir)) {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }
            # Initialize a fresh log file
            "" | Out-File -FilePath $LogTo -Encoding UTF8
        }
    }

    process {
        # Safety: verify compliance before tagging
        $isGoodMusic = Find-BadMusicFolderStructure -StartingPath $FolderPath -Good
        if (-not $isGoodMusic) {
            Write-Warning "Skipping non-compliant folder: $FolderPath"
            if ($LogTo) { $badFolders[$FolderPath] = @("NonCompliant") }
            return
        }

        $musicFiles = Get-ChildItem -LiteralPath $FolderPath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $musicExtensions -contains $_.Extension.ToLower() }

        foreach ($file in $musicFiles) {
            $parts = $file.FullName -split '\\'

            # Extract album info
            $albumIndex = -1
            for ($i = 1; $i -lt $parts.Count; $i++) {
                if ($parts[$i] -match '^(\d{4}) - (.+)$') {
                    $albumIndex = $i
                    $year = $matches[1]
                    $album = $matches[2]
                    break
                }
            }

            if ($albumIndex -ge 1) {
                $albumArtist = $parts[$albumIndex - 1]
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
                            if (-not $Quiet) {
                                Write-Host "🔍 [WhatIf] Would tag: $($file.FullName)"
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
                        Write-Warning "⚠️ Failed to tag: $($file.FullName) — $_"
                        if ($LogTo) { $badFolders[$FolderPath] += "FailedTagging" }
                    }
                }
                else {
                    Write-Warning "❌ Bad filename format: $fileName"
                    if ($LogTo) { $badFolders[$FolderPath] += "WrongTitleFormat" }
                }
            }
            else {
                Write-Warning "❌ No album folder found: $($file.FullName)"
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
                    [System.IO.File]::AppendAllText($LogTo, "$logEntry`r`n", [System.Text.Encoding]::UTF8)
                } else {
                    [System.IO.File]::AppendAllText($LogTo, "$reasons`: $folder`r`n", [System.Text.Encoding]::UTF8)
                }
            }
            Write-Host "📝 Bad folders logged to: $LogTo"
        }
        
        # Output successfully processed folders
        Write-Output $goodFolders
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
            New-Item -ItemType Directory -Path $DestinationFolder -Force | Out-Null
        }
        $movedFoldersByArtist = @{}
    }

    process {
        # Check if this is an artist folder containing album subfolders
        $subfolders = Get-ChildItem -LiteralPath $FolderPath -Directory -ErrorAction SilentlyContinue
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
                $isGoodAlbum = Find-BadMusicFolderStructure -StartingPath $albumFolder -Good
                if ($isGoodAlbum) {
                    # Recursively call Move-GoodFolders on each good album folder
                    $albumFolder | Move-GoodFolders -DestinationFolder $DestinationFolder -WhatIf:$WhatIfPreference -Quiet:$Quiet
                } else {
                    Write-Warning "Skipping bad album folder: $albumFolder"
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
            New-Item -ItemType Directory -Path $artistDest -Force | Out-Null
        }

        if ($album) {
            $destinationPath = Join-Path $artistDest $album
        } else {
            $destinationPath = $artistDest
        }

        if ($PSCmdlet.ShouldProcess($destinationPath, "Move from $FolderPath")) {
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
            Write-Host "\n📦 Move Summary:"
            foreach ($artist in $movedFoldersByArtist.Keys) {
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
    Get-ChildItem "C:\Music" -Directory | Merge-AlbumInArtistFolder -DestinationFolder "C:\Organized" -WhatIf
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
            New-Item -ItemType Directory -Path $DestinationFolder -Force | Out-Null
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
            Write-Warning "No audio files found in: $FolderPath"
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
                Write-Warning "No album artist found in: $($firstAudioFile.FullName)"
                return
            }
            $albumArtist = $albumArtist[0]  # Take the first one
        }
        catch {
            Write-Warning "Failed to read tags from: $($firstAudioFile.FullName) — $_"
            return
        }

        # Create artist folder and move
        $artistDest = Join-Path $DestinationFolder $albumArtist
        if (-not (Test-Path $artistDest)) {
            if ($PSCmdlet.ShouldProcess($artistDest, "Create directory")) {
                New-Item -ItemType Directory -Path $artistDest -Force | Out-Null
            }
        }

        $folderName = Split-Path $FolderPath -Leaf
        $destinationPath = Join-Path $artistDest $folderName

        if ($PSCmdlet.ShouldProcess($destinationPath, "Move from $FolderPath")) {
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

.PARAMETER LogFile
    Path to the log file to process. Supports both JSON and text formats.

.PARAMETER Status
    Filter entries by status. Options are 'Good', 'Bad', or 'All'. Default is 'Good'.

.PARAMETER DestinationFolder
    The destination directory where processed folders will be moved.

.PARAMETER MaxItems
    Maximum number of folders to process. Default is to process all matching entries.

.PARAMETER LogFormat
    Format of the log file. Options are 'Auto' (detect automatically), 'JSON', or 'Text'. Default is 'Auto'.

.PARAMETER Quiet
    Suppresses verbose output during tagging operations.

.EXAMPLE
    Import-LoggedFolders -LogFile "C:\Logs\structure.json" -DestinationFolder "E:\CorrectedMusic" -WhatIf
    Processes all good folders from the JSON log file and shows what would be done.

.EXAMPLE
    Import-LoggedFolders -LogFile "C:\Logs\structure.log" -Status Bad -MaxItems 5 -DestinationFolder "E:\BadMusic"
    Processes first 5 bad folders from a text log file.

.EXAMPLE
    Import-LoggedFolders -LogFile "C:\Logs\structure.json" -DestinationFolder "E:\Processed" -Confirm
    Processes all good folders with confirmation prompts.

.EXAMPLE
    Import-LoggedFolders -LogFile "C:\Logs\structure.json" -DestinationFolder "E:\CorrectedMusic" -Quiet -WhatIf
    Processes folders quietly, showing only essential moving information.

.NOTES
    Automatically detects log format if set to 'Auto'.
    Supports -WhatIf and -Confirm parameters for safe operation.
    Requires TagLib-Sharp.dll for tagging operations.
#>
function Import-LoggedFolders {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [string]$LogFile,

        [Parameter()]
        [ValidateSet('Good', 'Bad', 'All')]
        [string]$Status = 'Good',

        [Parameter(Mandatory)]
        [string]$DestinationFolder,

        [Parameter()]
        [int]$MaxItems,

        [Parameter()]
        [ValidateSet('Auto', 'JSON', 'Text')]
        [string]$LogFormat = 'Auto',

        [switch]$Quiet
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
                    Write-Warning "Skipping malformed JSON line: $_"
                    $null
                }
            } | Where-Object { $_ -ne $null }
        } else {
            # Parse text format
            $logEntries = $logContent -split "`n" | Where-Object { $_ -match '\S' } | ForEach-Object {
                $line = $_.Trim()
                if ($line -match '^(GoodFolder|BadFolder)\s+(.+)$') {
                    [PSCustomObject]@{
                        Status = if ($matches[1] -eq 'GoodFolder') { 'Good' } else { 'Bad' }
                        Path = $matches[2]
                        Function = 'Find-BadMusicFolderStructure'
                        Type = if ($matches[1] -eq 'GoodFolder') { 'ArtistFolder' } else { 'AlbumFolder' }
                    }
                } else {
                    Write-Warning "Skipping malformed text line: $line"
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
        Write-Host "No matching entries found in log file."
        return
    }

    Write-Host "Found $($logEntries.Count) folders to process..."

    # Process each folder
    $processedCount = 0
    foreach ($entry in $logEntries) {
        $folderPath = $entry.Path

        if (-not (Test-Path $folderPath)) {
            Write-Warning "Folder not found, skipping: $folderPath"
            continue
        }

        Write-Host "Processing: $folderPath"

        try {
            # Tag the folder (this will validate it's still good)
            $taggedFolders = Save-TagsFromGoodMusicFolders -FolderPath $folderPath -WhatIf:$WhatIfPreference -Quiet:$Quiet

            if ($taggedFolders) {
                # Move the successfully tagged folder
                $taggedFolders | Move-GoodFolders -DestinationFolder $DestinationFolder -WhatIf:$WhatIfPreference -Quiet:$Quiet
                $processedCount++
            } else {
                Write-Warning "Failed to tag folder: $folderPath"
            }
        }
        catch {
            Write-Warning "Error processing folder $folderPath`: $_"
        }
    }

    Write-Host "✅ Completed processing $processedCount folders."
}