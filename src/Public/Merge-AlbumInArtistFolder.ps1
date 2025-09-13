<#
.SYNOPSIS
    Merges album folders into artist subfolders based on embedded metadata.

.DESCRIPTION
    Merge-AlbumInArtistFolder reads the album artist from audio file metadata and moves the folder
    into the appropriate artist subfolder structure. This helps organize music libraries by artist.

.PARAMETER FolderPath
    Path to the album folder to merge. Accepts pipeline input.

.PARAMETER DestinationFolder
    Root destination directory where artist subfolders will be created.

.PARAMETER DuplicateAction
    How to handle duplicate folders. Valid values: 'Overwrite', 'Skip', 'Rename'. Default is 'Rename'.

.INPUTS
    System.String
    You can pipe folder paths to Merge-AlbumInArtistFolder.

.OUTPUTS
    None. This function provides console output and moves folders.

.EXAMPLE
    Merge-AlbumInArtistFolder -FolderPath 'E:\Temp\Album1' -DestinationFolder 'E:\Music'
    Reads album artist from files in Album1 and moves it to E:\Music\ArtistName\Album1

.EXAMPLE
    Get-ChildItem 'E:\Unsorted' -Directory | Merge-AlbumInArtistFolder -DestinationFolder 'E:\Music' -WhatIf
    Shows what would happen when merging all subfolders from E:\Unsorted

.EXAMPLE
    Merge-AlbumInArtistFolder -FolderPath 'E:\Temp\Album1' -DestinationFolder 'E:\Music' -DuplicateAction 'Skip'
    Merges the album but skips if the destination already exists

.NOTES
    Author: MusicFolderChecker Module
    Requires TagLib-Sharp.dll for reading audio metadata
    Creates artist directories automatically if they don't exist
    Uses the first album artist found in the audio files
#>
function Merge-AlbumInArtistFolder {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$FolderPath,

        [Parameter(Mandatory)]
        [string]$DestinationFolder,

        [Parameter()]
        [ValidateSet('Overwrite', 'Skip', 'Rename')]
        [string]$DuplicateAction = 'Rename'
    )

    begin {
        # TagLib is already loaded at module level
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
            # Handle duplicate folders based on DuplicateAction
            if (Test-Path $destinationPath) {
                switch ($DuplicateAction) {
                    'Skip' {
                        if (-not $Quiet) {
                            Write-Host "⚠️  Skipping duplicate folder: $destinationPath"
                        }
                        return
                    }
                    'Rename' {
                        # Create numbered duplicate
                        $counter = 1
                        $folderName = Split-Path $destinationPath -Leaf
                        $parentPath = Split-Path $destinationPath -Parent
                        $newDest = Join-Path $parentPath "$folderName ($counter)"
                        while (Test-Path $newDest) {
                            $counter++
                            $newDest = Join-Path $parentPath "$folderName ($counter)"
                        }
                        $destinationPath = $newDest
                        if (-not $Quiet) {
                            Write-Host "📝 Renaming to avoid conflict: $destinationPath"
                        }
                    }
                    'Overwrite' {
                        # Default behavior - continue with overwrite
                        if (-not $Quiet) {
                            Write-Host "⚠️  Overwriting existing folder: $destinationPath"
                        }
                    }
                }
            }
            
            Move-Item -Path $FolderPath -Destination $destinationPath
            Write-Host "✅ Merged: $FolderPath to $destinationPath"
        }
    }
}
