<#
.SYNOPSIS
    Checks music folder structures for compliance with                $results += [PSCustomObject]@{ Status = 'Good'; StartingPath = $folder }
            if( $LogTo -and $Good) {
                    Add-Content -Path $LogTo -Value ("GoodFolderStructure " + ($folder))
                }ected naming conventions.

.DESCRIPTION
    This function recursively scans a starting path for music folders and determines if they follow
    the expected structure: Artist\Year - Album\Track - Title.ext or with Disc folders.
    It returns folders that have bad structure or good structure based on the -Good switch.

.PARAMETER StartingPath
    The root path to start scanning for music folders. This can be a directory path.

.PARAMETER Good
    Switch to return only folders with good structure instead of bad ones.

.PARAMETER LogTo
    Optional path to a log file where results will be written.

.EXAMPLE
    Find-BadMusicFolderStructure -StartingPath "C:\Music"
    Returns all folders with bad music structure under C:\Music.

.EXAMPLE
    Find-BadMusicFolderStructure -StartingPath "C:\Music" -Good
    Returns all folders with good music structure under C:\Music.

.EXAMPLE
    Get-ChildItem "C:\Music" -Directory | Find-BadMusicFolderStructure -LogTo "C:\Logs\structure.log"
    Pipes directories to check and logs results.

.NOTES
    Supported audio extensions: .mp3, .wav, .flac, .aac, .ogg, .wma
#>
function Find-BadMusicFolderStructure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]$StartingPath,

        [switch]$Good,

        [string]$LogTo
    )

    begin {
        $audioExtensions = @(".mp3", ".wav", ".flac", ".aac", ".ogg", ".wma")
        $patternMain = '(?i).*\\([^\\]+)\\\d{4} - (?!.*(?:CD|Disc)\d+)[^\\]+\\\d{2} - .+\.[a-z0-9]+$'
        $patternDisc = '(?i).*\\([^\\]+)\\\d{4} - [^\\]+(?:\\Disc \d+|- CD\d+)\\\d{2} - .+\.[a-z0-9]+$'
        $results = @()
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
            if( $LogTo -and $Good) {
                    Add-Content -Path $LogTo -Value ("GoodFolderStructure " + ($artistFolderPath))
                }
            }
            else {
                $badFolder = $firstAudioFile.DirectoryName
                $results += [PSCustomObject]@{ Status = 'Bad'; StartingPath = $badFolder }
                if ($LogTo) {
                    Add-Content -Path $LogTo -Value ("BadFolderStructure " + ($badFolder))
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

.EXAMPLE
    Save-TagsFromGoodMusicFolders -FolderPath "C:\Music\Artist\2020 - Album"
    Processes the specified folder and tags its music files.

.EXAMPLE
    Find-BadMusicFolderStructure -StartingPath "C:\Music" -Good | Save-TagsFromGoodMusicFolders -LogTo "C:\Logs\tagging.log"
    Finds good folders and pipes them to be tagged, with logging.

.EXAMPLE
    Save-TagsFromGoodMusicFolders -FolderPath "C:\Music\Album" -WhatIf
    Shows what would be tagged without actually making changes.

.NOTES
    Requires TagLib-Sharp.dll in the module's lib directory.
    Only processes folders with compliant structure.
    Outputs successfully processed folder paths.
#>
function Save-TagsFromGoodMusicFolders {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('StartingPath')]
        [string]$FolderPath,

        [string]$LogTo
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
                            Write-Host "✅ Retagged: $($file.Name)"
                            
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
                [System.IO.File]::AppendAllText($LogTo, "$reasons`: $folder`r`n", [System.Text.Encoding]::UTF8)
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
        [string]$DestinationFolder
    )

    begin {
        if (-not (Test-Path $DestinationFolder)) {
            New-Item -ItemType Directory -Path $DestinationFolder -Force | Out-Null
        }
    }

    process {
        # Extract artist and album from the path
        $parentPath = Split-Path $FolderPath -Parent
        $artist = Split-Path $parentPath -Leaf
        $album = Split-Path $FolderPath -Leaf

        $artistDest = Join-Path $DestinationFolder $artist
        if (-not (Test-Path $artistDest)) {
            New-Item -ItemType Directory -Path $artistDest -Force | Out-Null
        }

        $destinationPath = Join-Path $artistDest $album

        if ($PSCmdlet.ShouldProcess($FolderPath, "Move to $destinationPath")) {
            Move-Item -Path $FolderPath -Destination $destinationPath
            Write-Host "✅ Moved: $FolderPath to $destinationPath"
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

        if ($PSCmdlet.ShouldProcess($FolderPath, "Move to $destinationPath")) {
            Move-Item -Path $FolderPath -Destination $destinationPath
            Write-Host "✅ Merged: $FolderPath to $destinationPath"
        }
    }
}