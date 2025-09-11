<#
.SYNOPSIS
    Interactive and scripted metadata updater for album folders.

.DESCRIPTION
    `Update-MusicFolderMetadata` lets you inspect and update common album-level tags
    (Album Artist, Album, Year) for folders containing music files. It supports both
    interactive editing (prompt per-folder) and scripted non-interactive updates via
    parameters. Uses TagLib-Sharp to write tags; requires the module's `lib\taglib-sharp.dll`.

.PARAMETER FolderPath
    One or more folder paths to process. Accepts pipeline input.

.PARAMETER AlbumArtist
    Optional album artist value to set for all processed folders (non-interactive).

.PARAMETER Album
    Optional album value to set for all processed folders (non-interactive).

.PARAMETER Year
    Optional year value to set for all processed folders (non-interactive).

.PARAMETER Interactive
    Switch to enable interactive prompting per folder. Default behavior is interactive
    when AlbumArtist/Album/Year are not provided.

.PARAMETER Quiet
    Suppress informational output.

.EXAMPLE
    Get-ChildItem -Directory C:\Music | Update-MusicFolderMetadata

.EXAMPLE
    Update-MusicFolderMetadata -FolderPath 'E:\Music\Artist\2020 - Album' -AlbumArtist 'Various Artists' -Year 2020 -WhatIf

.NOTES
    The function honors `ShouldProcess` for safe previewing and uses TagLib-Sharp
    loaded by the module loader. No private scripts are dot-sourced here; this file
    only defines the public function as required by the module structure.
#>

function Update-MusicFolderMetadata {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [string[]]$FolderPath,

        [Parameter()]
        [string]$AlbumArtist,

        [Parameter()]
        [string]$Album,

        [Parameter()]
        [int]$Year,

        [Parameter()]
        [switch]$Interactive,

        [switch]$Quiet
    )

    begin {
        $musicExtensions = @('.mp3', '.flac', '.m4a', '.ogg', '.wav', '.aac')
    }

    process {
        foreach ($folder in $FolderPath) {
            if (-not (Test-Path -LiteralPath $folder)) {
                if (-not $Quiet) { Write-Output "Skipping missing folder: $folder" }
                continue
            }

            # Find a representative audio file
            $firstAudio = $null
            foreach ($ext in $musicExtensions) {
                $firstAudio = Get-ChildItem -LiteralPath $folder -File -Filter "*${ext}" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($firstAudio) { break }
            }

            if (-not $firstAudio) {
                if (-not $Quiet) { Write-Output "No audio files found in: $folder" }
                continue
            }

            try {
                $tagFile = [TagLib.File]::Create($firstAudio.FullName)
            }
            catch {
                Write-Output "Failed to read tags from $($firstAudio.FullName): $_"
                continue
            }

            $currentAlbumArtist = ($null -ne $tagFile.Tag.AlbumArtists -and $tagFile.Tag.AlbumArtists.Count -gt 0) ? $tagFile.Tag.AlbumArtists[0] : ($null -ne $tagFile.Tag.Performers -and $tagFile.Tag.Performers.Count -gt 0 ? $tagFile.Tag.Performers[0] : '')
            $currentAlbum = $tagFile.Tag.Album
            $currentYear = $tagFile.Tag.Year

            $applyAlbumArtist = $AlbumArtist
            $applyAlbum = $Album
            $applyYear = $Year

            $doInteractive = $false
            if ($Interactive.IsPresent) { $doInteractive = $true }
            elseif (-not $AlbumArtist -and -not $Album -and -not $Year) { $doInteractive = $true }

            if ($doInteractive) {
                if (-not $Quiet) { Write-Output "\nFolder: $folder" }
                if (-not $Quiet) { Write-Output "Current Album Artist: $currentAlbumArtist" }
                if (-not $Quiet) { Write-Output "Current Album       : $currentAlbum" }
                if (-not $Quiet) { Write-Output "Current Year        : $currentYear" }

                $resp = Read-Host -Prompt "Enter Album Artist (blank to keep)"
                if ($resp -ne '') { $applyAlbumArtist = $resp }
                $resp = Read-Host -Prompt "Enter Album (blank to keep)"
                if ($resp -ne '') { $applyAlbum = $resp }
                $resp = Read-Host -Prompt "Enter Year (blank to keep)"
                if ($resp -ne '') {
                    if ([int]::TryParse($resp, [ref]$null)) { $applyYear = [int]$resp } else { Write-Output "Invalid year entered, skipping year update." }
                }
            }

            # No changes requested?
            if (($applyAlbumArtist -eq $null -or $applyAlbumArtist -eq '') -and ($applyAlbum -eq $null -or $applyAlbum -eq '') -and (-not $applyYear)) {
                if (-not $Quiet) { Write-Output "No changes for $folder" }
                continue
            }

            # Apply changes to all audio files in the folder
            $audioFiles = Get-ChildItem -LiteralPath $folder -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $musicExtensions -contains $_.Extension.ToLower() }
            foreach ($f in $audioFiles) {
                if ($PSCmdlet.ShouldProcess($f.FullName, 'Update music tags')) {
                    try {
                        $t = [TagLib.File]::Create($f.FullName)
                        if ($applyAlbumArtist -and $applyAlbumArtist -ne '') { $t.Tag.Performers = @($applyAlbumArtist); $t.Tag.AlbumArtists = @($applyAlbumArtist) }
                        if ($applyAlbum -and $applyAlbum -ne '') { $t.Tag.Album = $applyAlbum }
                        if ($applyYear) { $t.Tag.Year = [uint]$applyYear }
                        $t.Save()
                        if (-not $Quiet) { Write-Output "Updated: $($f.FullName)" }
                    }
                    catch {
                        Write-Output "Failed to update tags for $($f.FullName): $_" }
                }
            }
        }
    }
}
