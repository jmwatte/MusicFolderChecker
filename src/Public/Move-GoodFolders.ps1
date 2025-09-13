<#
.SYNOPSIS
    Moves validated music folders to a destination with proper artist/album organization.

.DESCRIPTION
    Move-GoodFolders moves music folders that have been validated for proper structure.
    It automatically organizes them into Artist\Album format at the destination.
    The function validates each folder before moving and provides detailed feedback.

.PARAMETER FolderPath
    Path to the music folder to move. Accepts pipeline input.

.PARAMETER DestinationFolder
    Root destination directory where organized folders will be placed.

.PARAMETER Quiet
    Switch parameter. When specified, suppresses detailed console output.

.PARAMETER DuplicateAction
    How to handle duplicate folders at destination. Valid values: 'Overwrite', 'Skip', 'Rename'. Default is 'Rename'.

.INPUTS
    System.String
    You can pipe folder paths to Move-GoodFolders.

.OUTPUTS
    None. This function provides console output and moves folders.

.EXAMPLE
    Move-GoodFolders -FolderPath 'E:\Temp\GoodAlbum' -DestinationFolder 'E:\Music'
    Validates and moves the album to proper artist/album structure

.EXAMPLE
    Find-BadMusicFolderStructure -StartingPath 'E:\Temp' -Good | Move-GoodFolders -DestinationFolder 'E:\Music'
    Finds good folders and moves them to the destination

.EXAMPLE
    Move-GoodFolders -FolderPath 'E:\Temp\Album1' -DestinationFolder 'E:\Music' -DuplicateAction 'Skip' -WhatIf
    Shows what would happen without actually moving, skipping duplicates

.NOTES
    Author: MusicFolderChecker Module
    Automatically validates folder structure before moving
    Creates artist directories as needed
    Provides detailed move summary at completion
    Supports both artist folders and individual album folders
#>
function Move-GoodFolders {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$FolderPath,

        [Parameter(Mandatory)]
        [string]$DestinationFolder,

        [switch]$Quiet,

        [Parameter()]
        [ValidateSet('Overwrite', 'Skip', 'Rename')]
        [string]$DuplicateAction = 'Rename'
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
                    $albumFolder | Move-GoodFolders -DestinationFolder $DestinationFolder -WhatIf:$WhatIfPreference -Quiet:$Quiet -DuplicateAction:$DuplicateAction
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
