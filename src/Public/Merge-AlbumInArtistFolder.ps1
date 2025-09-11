<#
.SYNOPSIS
    Merges album folders into artist subfolders based on metadata.
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
