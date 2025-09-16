<#
.SYNOPSIS
    Sorts mixed music files from a folder into proper artist/album structures based on embedded tags.

.DESCRIPTION
    Group-MixedMusicFiles analyzes all audio files in the specified folder, groups them by artist/album/year
    from their embedded tags, and moves them to organized destination folders. Supports interactive mode
    for confirming moves and handling special cases.

.PARAMETER FolderPath
    Path to the folder containing mixed music files to sort.

.PARAMETER DestinationFolder
    Base destination directory where organized folders will be created.

.PARAMETER Interactive
    Switch to enable interactive prompts for each group of files.

.PARAMETER WhatIf
    Switch to preview moves without actually performing them.

.PARAMETER LogPath
    Optional path to save structured JSONL log entries.

.EXAMPLE
    Group-MixedMusicFiles -FolderPath 'E:\MixedMusic' -DestinationFolder 'E:\Organized' -Interactive
    Interactively sorts files from the mixed folder to organized structure.

.NOTES
    Requires TagLib-Sharp.dll for audio file processing.
    Preserves non-audio files by moving them to album root folders.
#>

function Group-MixedMusicFiles {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [string]$FolderPath,

        [Parameter(Mandatory=$true)]
        [string]$DestinationFolder,

        [Parameter()]
        [switch]$Interactive,

        [Parameter()]
        [string]$LogPath
    )

    begin {
        $musicExtensions = @('.mp3', '.flac', '.m4a', '.ogg', '.wav', '.aac', '.ape', '.mpc')
        $groups = @{}
    }

    process {
        if (-not (Test-Path -LiteralPath $FolderPath)) {
            Write-Error "Source folder does not exist: $FolderPath"
            return
        }

        if (-not (Test-Path -LiteralPath $DestinationFolder)) {
            Write-Error "Destination folder does not exist: $DestinationFolder"
            return
        }

        # Get all audio files
        $audioFiles = Get-ChildItem -LiteralPath $FolderPath -Recurse -File -ErrorAction SilentlyContinue |
                      Where-Object { $musicExtensions -contains $_.Extension.ToLower() }

        if ($audioFiles.Count -eq 0) {
            Write-Warning "No audio files found in $FolderPath"
            return
        }

        Write-Output "Found $($audioFiles.Count) audio files to process"

        # Group files by artist/album/year
        foreach ($file in $audioFiles) {
            try {
                $tag = Invoke-TagLibCreate -Path $file.FullName
                $artist = ($tag.Tag.AlbumArtists.Count -gt 0) ? $tag.Tag.AlbumArtists[0] :
                         ($tag.Tag.Performers.Count -gt 0 ? $tag.Tag.Performers[0] : 'Unknown Artist')
                $album = $tag.Tag.Album ? $tag.Tag.Album : 'Unknown Album'
                $year = $tag.Tag.Year ? $tag.Tag.Year.ToString() : ''

                $key = "$artist|$album|$year"
                if (-not $groups.ContainsKey($key)) {
                    $groups[$key] = @{
                        Artist = $artist
                        Album = $album
                        Year = $year
                        Files = @()
                        NonAudioFiles = @()
                    }
                }
                $groups[$key].Files += $file
            }
            catch {
                Write-Warning "Failed to read tags for $($file.FullName): $_"
            }
        }

        # Get non-audio files
        $nonAudioFiles = Get-ChildItem -LiteralPath $FolderPath -Recurse -File -ErrorAction SilentlyContinue |
                         Where-Object { $musicExtensions -notcontains $_.Extension.ToLower() }

        Write-Output "Found $($groups.Count) album groups and $($nonAudioFiles.Count) non-audio files"

        # Process each group
        foreach ($key in $groups.Keys) {
            $group = $groups[$key]
            $artistSafe = [regex]::Replace($group.Artist, '[\\/:*?"<>|]', '')
            $albumSafe = [regex]::Replace($group.Album, '[\\/:*?"<>|]', '')
            $yearSafe = $group.Year

            $albumFolderName = if ($yearSafe) { "$yearSafe - $albumSafe" } else { $albumSafe }
            $destPath = Join-Path $DestinationFolder $artistSafe | Join-Path -ChildPath $albumFolderName

            if ($Interactive) {
                Write-Output "`nGroup: $($group.Artist) - $($group.Album) ($($group.Year))"
                Write-Output "Files: $($group.Files.Count)"
                Write-Output "Destination: $destPath"
                $response = Read-Host "Proceed with moving these files? (Y/N/Skip)"
                if ($response -eq 'N' -or $response -eq 'n') { continue }
                if ($response -eq 'Skip' -or $response -eq 's') { continue }
            }

            # Create destination directory
            if (-not (Test-Path -LiteralPath $destPath)) {
                if ($PSCmdlet.ShouldProcess($destPath, 'Create Directory')) {
                    [System.IO.Directory]::CreateDirectory($destPath) | Out-Null
                }
            }

            # Move audio files
            foreach ($file in $group.Files) {
                $destFile = Join-Path $destPath $file.Name
                if ($PSCmdlet.ShouldProcess($file.FullName, "Move to $destFile")) {
                    try {
                        Move-Item -LiteralPath $file.FullName -Destination $destFile -Force
                        Write-Output "$($file.FullName)"
                        Write-Output "-> $destFile"
                        if ($LogPath) {
                            Write-StructuredLog -Path $LogPath -Entry @{
                                Function = 'Group-MixedMusicFiles'
                                Level = 'Info'
                                Status = 'Moved'
                                Source = $file.FullName
                                Destination = $destFile
                            }
                        }
                    }
                    catch {
                        Write-Error "Failed to move $($file.FullName): $_"
                    }
                }
            }
        }

        # Handle non-audio files - ask where to put them
        if ($nonAudioFiles.Count -gt 0) {
            if ($Interactive) {
                Write-Output "`nFound $($nonAudioFiles.Count) non-audio files:"
                $nonAudioFiles | ForEach-Object { Write-Output "  $($_.Name)" }
                $response = Read-Host "Move non-audio files to first album folder? (Y/N)"
                if ($response -eq 'Y' -or $response -eq 'y') {
                    $firstGroup = $groups.Values | Select-Object -First 1
                    if ($firstGroup) {
                        $artistSafe = [regex]::Replace($firstGroup.Artist, '[\\/:*?"<>|]', '')
                        $albumSafe = [regex]::Replace($firstGroup.Album, '[\\/:*?"<>|]', '')
                        $yearSafe = $firstGroup.Year
                        $albumFolderName = if ($yearSafe) { "$yearSafe - $albumSafe" } else { $albumSafe }
                        $destPath = Join-Path $DestinationFolder $artistSafe | Join-Path -ChildPath $albumFolderName

                        foreach ($file in $nonAudioFiles) {
                            $destFile = Join-Path $destPath $file.Name
                            if ($PSCmdlet.ShouldProcess($file.FullName, "Move to $destFile")) {
                                try {
                                    Move-Item -LiteralPath $file.FullName -Destination $destFile -Force
                                    Write-Output "$($file.FullName)"
                                    Write-Output "-> $destFile"
                                }
                                catch {
                                    Write-Error "Failed to move $($file.FullName): $_"
                                }
                            }
                        }
                    }
                }
            }
        }

        # Clean up empty directories
        Get-ChildItem -LiteralPath $FolderPath -Recurse -Directory | Sort-Object -Property FullName -Descending |
        Where-Object { (Get-ChildItem -LiteralPath $_.FullName -File -Recurse).Count -eq 0 } |
        ForEach-Object {
            if ($PSCmdlet.ShouldProcess($_.FullName, 'Remove empty directory')) {
                Remove-Item -LiteralPath $_.FullName -Force
            }
        }
    }
}