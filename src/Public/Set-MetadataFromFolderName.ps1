function Set-MetadataFromFolderName {
    <#
    .SYNOPSIS
        Parses folder name to extract artist, year, and album, then sets metadata in audio files.

    .DESCRIPTION
        This function attempts to parse the folder name using common patterns like:
        - "Artist - Year - Album"
        - "Number Artist (Label, Year)"
        - "Year - Artist - Album"
        And sets the corresponding metadata in all audio files in the folder.

    .PARAMETER FolderPath
        Path to the folder to process.

    .PARAMETER WhatIf
        Shows what would happen without actually making changes.

    .EXAMPLE
        Set-MetadataFromFolderName -FolderPath "E:\Music\04 Gaspar Cassado (VoxBox, 1957)"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$FolderPath
    )

    $musicExtensions = @('.mp3', '.flac', '.m4a', '.ogg', '.wav', '.aac', '.ape')

    $folderName = Split-Path $FolderPath -Leaf

    # Try different parsing patterns
    $parsed = $null

    # Pattern 1: "Number Artist (Label, Year)" - e.g., "04 Gaspar Cassado (VoxBox, 1957)"
    if ($folderName -match '^\d+\s+(.+?)\s*\((.+?),\s*(\d{4})\)$') {
        $parsed = @{
            Artist = $matches[1].Trim()
            Year = [int]$matches[3]
            Album = "Unknown Album"  # Will try to get from parent folder
        }
    }
    # Pattern 2: "Year - Artist - Album"
    elseif ($folderName -match '^(\d{4})\s*-\s*(.+?)\s*-\s*(.+)$') {
        $parsed = @{
            Year = [int]$matches[1]
            Artist = $matches[2].Trim()
            Album = $matches[3].Trim()
        }
    }
    # Pattern 3: "Artist - Year - Album"
    elseif ($folderName -match '^(.+?)\s*-\s*(\d{4})\s*-\s*(.+)$') {
        $parsed = @{
            Artist = $matches[1].Trim()
            Year = [int]$matches[2]
            Album = $matches[3].Trim()
        }
    }

    if (-not $parsed) {
        Write-Output "Could not parse folder name: $folderName"
        return
    }

    # Try to get album from parent folder if not set
    if ($parsed.Album -eq "Unknown Album") {
        $parentFolder = Split-Path $FolderPath -Parent
        $parentName = Split-Path $parentFolder -Leaf
        if ($parentName -and $parentName -ne "Music" -and $parentName -ne "Audio") {
            $parsed.Album = $parentName
        }
    }

    Write-Output "Parsed from '$folderName':"
    Write-Output "  Artist: $($parsed.Artist)"
    Write-Output "  Year: $($parsed.Year)"
    Write-Output "  Album: $($parsed.Album)"

    # Find audio files
    $audioFiles = Get-ChildItem -Path $FolderPath -File -Recurse | Where-Object {
        $musicExtensions -contains $_.Extension.ToLower()
    }

    if ($audioFiles.Count -eq 0) {
        Write-Output "No audio files found in $FolderPath"
        return
    }

    foreach ($file in $audioFiles) {
        try {
            $tagFile = Invoke-TagLibCreate -Path $file.FullName
        }
        catch {
            Write-Output "Failed to read tags from $($file.FullName): $_"
            continue
        }

        $currentArtist = ($null -ne $tagFile.Tag.AlbumArtists -and $tagFile.Tag.AlbumArtists.Count -gt 0) ? $tagFile.Tag.AlbumArtists[0] : ($null -ne $tagFile.Tag.Performers -and $tagFile.Tag.Performers.Count -gt 0 ? $tagFile.Tag.Performers[0] : '')
        $currentAlbum = $tagFile.Tag.Album
        $currentYear = $tagFile.Tag.Year

        $needsUpdate = $false
        if ($parsed.Artist -and $parsed.Artist -ne $currentArtist) { $needsUpdate = $true }
        if ($parsed.Album -and $parsed.Album -ne $currentAlbum) { $needsUpdate = $true }
        if ($parsed.Year -and $parsed.Year -ne $currentYear) { $needsUpdate = $true }

        if (-not $needsUpdate) {
            Write-Verbose "Metadata already correct for $($file.FullName)"
            continue
        }

        if ($PSCmdlet.ShouldProcess($file.FullName, "Update metadata: Artist='$($parsed.Artist)', Album='$($parsed.Album)', Year=$($parsed.Year)")) {
            try {
                if ($parsed.Artist) {
                    $tagFile.Tag.Performers = @($parsed.Artist)
                    $tagFile.Tag.AlbumArtists = @($parsed.Artist)
                }
                if ($parsed.Album) { $tagFile.Tag.Album = $parsed.Album }
                if ($parsed.Year) { $tagFile.Tag.Year = [uint]$parsed.Year }
                $tagFile.Save()
                Write-Output "Updated: $($file.FullName)"
            }
            catch {
                Write-Output "Failed to update metadata for $($file.FullName): $_"
            }
        }
    }

    Write-Output "Metadata update complete for $FolderPath"
}