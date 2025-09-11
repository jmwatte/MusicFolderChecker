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
        ,
        [Parameter()]
        [string]$DestinationFolder,

    [Parameter()]
    [string]$DestinationPattern,

        [Parameter()]
        [switch]$Move,

        [Parameter()]
        [string]$LogPath,

        
        [Parameter()]
        [ValidateSet('Skip','Overwrite','Merge')]
        [string]$OnConflict = 'Skip'
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
                $tagFile = Invoke-TagLibCreate -Path $firstAudio.FullName
            }
            catch {
                Write-Output "Failed to read tags from $($firstAudio.FullName): $_"
                continue
            }

            # Log folder processing start
            if ($LogPath) {
                $entry = @{ Function = 'Update-MusicFolderMetadata'; Level = 'Info'; Status = 'Start'; Path = $folder; DryRun = ($PSCmdlet.ShouldProcess($folder) -eq $false) }
                Write-StructuredLog -Path $LogPath -Entry $entry
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
            $noChanges = (($applyAlbumArtist -eq $null -or $applyAlbumArtist -eq '') -and ($applyAlbum -eq $null -or $applyAlbum -eq '') -and (-not $applyYear))
            if ($noChanges) {
                if (-not $Quiet) { Write-Output "No changes for $folder" }
                # If the user requested a move, proceed to move even when there are no tag changes.
                if (-not $Move.IsPresent) { continue }
            }

            # Folder-level validation: log missing metadata
            if ($LogPath) {
                if (-not $applyAlbumArtist -or $applyAlbumArtist -eq '') {
                    Write-StructuredLog -Path $LogPath -Entry @{ Function='Update-MusicFolderMetadata'; Level='Warning'; Status='Issue'; Path=$folder; IssueType='MissingAlbumArtist'; Details=@{ Found = $currentAlbumArtist } }
                }
                if (-not $applyAlbum -or $applyAlbum -eq '') {
                    Write-StructuredLog -Path $LogPath -Entry @{ Function='Update-MusicFolderMetadata'; Level='Warning'; Status='Issue'; Path=$folder; IssueType='MissingAlbum'; Details=@{ Found = $currentAlbum } }
                }
                if (-not $applyYear -or $applyYear -eq 0) {
                    Write-StructuredLog -Path $LogPath -Entry @{ Function='Update-MusicFolderMetadata'; Level='Warning'; Status='Issue'; Path=$folder; IssueType='MissingYear'; Details=@{ Found = $currentYear } }
                }
            }

            # Apply changes to all audio files in the folder
            $audioFiles = Get-ChildItem -LiteralPath $folder -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $musicExtensions -contains $_.Extension.ToLower() }
            foreach ($f in $audioFiles) {
                        if ($PSCmdlet.ShouldProcess($f.FullName, 'Update music tags')) {
                    try {
                        $t = Invoke-TagLibCreate -Path $f.FullName
                        if ($applyAlbumArtist -and $applyAlbumArtist -ne '') { $t.Tag.Performers = @($applyAlbumArtist); $t.Tag.AlbumArtists = @($applyAlbumArtist) }
                        if ($applyAlbum -and $applyAlbum -ne '') { $t.Tag.Album = $applyAlbum }
                        if ($applyYear) { $t.Tag.Year = [uint]$applyYear }
                        $t.Save()
                                if (-not $Quiet) { Write-Output "Updated: $($f.FullName)" }
                                if ($LogPath) { Write-StructuredLog -Path $LogPath -Entry @{ Function='Update-MusicFolderMetadata'; Level='Info'; Status='UpdatedTags'; Path=$folder; File=$f.FullName } }
                    }
                    catch {
                        Write-Output "Failed to update tags for $($f.FullName): $_" }
                }
            }

            # Optional move: after tag updates, move files to a structured destination when requested
            if ($Move.IsPresent -and $DestinationFolder) {
                try {
                    # Sanitization helper for filesystem-safe names
                    $sanitize = {
                        param($s)
                        if ($null -eq $s) { return '' }
                        $r = [regex]::Replace($s.ToString(), '[\\/:*?"<>|]', '')
                        return $r.Trim()
                    }

                    # Default structure: Artist\Year - Album\[Disc]\Track - Title.ext

                    # Decide whether to use disc subfolders for this album folder.
                    # Rule: if there are no disc tags, or the only disc tag present is 1, do not use disc folders.
                    # If there are multiple disc numbers or any disc > 1, enable disc subfolders.
                    $discNumbers = @()
                    # Helper to parse integers from tag values like '1/3' or '01' or even '1 - remastered'
                    $parseInt = {
                        param($v)
                        if ($null -eq $v) { return $null }
                        $s = $v.ToString()
                        # If format like '1/3', split and take the first part
                        if ($s -match '^\s*(\d+)') { return [int]$matches[1] }
                        return $null
                    }

                    foreach ($af in $audioFiles) {
                        try {
                            $tmp = Invoke-TagLibCreate -Path $af.FullName
                        }
                        catch { continue }
                        $dRaw = $tmp.Tag.Disc
                        $d = & $parseInt $dRaw
                        if ($d -and $d -ne 0) { $discNumbers += $d }
                    }
                    $discNumbers = $discNumbers | Sort-Object -Unique
                    $useDiscFolders = $false
                    if ($discNumbers.Count -gt 1) { $useDiscFolders = $true }
                    elseif ($discNumbers.Count -eq 1 -and $discNumbers[0] -gt 1) { $useDiscFolders = $true }

                    foreach ($f in $audioFiles) {
                        # Read/update tags for each file (we already opened and updated files above in the loop; reopen to get current tag values)
                        try {
                            $fileTag = Invoke-TagLibCreate -Path $f.FullName
                        }
                        catch {
                            Write-Output "Failed to read tags for file $($f.FullName): $_"
                            continue
                        }

                        $artistVal = $applyAlbumArtist; if (-not $artistVal) { $artistVal = ($fileTag.Tag.AlbumArtists.Count -gt 0 ? $fileTag.Tag.AlbumArtists[0] : ($fileTag.Tag.Performers.Count -gt 0 ? $fileTag.Tag.Performers[0] : 'Unknown Artist')) }
                        $albumVal = $applyAlbum; if (-not $albumVal) { $albumVal = ($fileTag.Tag.Album ? $fileTag.Tag.Album : 'Unknown Album') }
                        $yearVal = $applyYear; if (-not $yearVal) { $yearVal = ($fileTag.Tag.Year ? $fileTag.Tag.Year : '') }
                        $discRaw = $fileTag.Tag.Disc
                        $discVal = & $parseInt $discRaw
                        $trackRaw = $fileTag.Tag.Track
                        $trackVal = & $parseInt $trackRaw
                        $titleVal = $fileTag.Tag.Title

                        $artistSafe = & $sanitize $artistVal
                        $albumSafe = & $sanitize $albumVal
                        $yearSafe = & $sanitize $yearVal
                        $titleSafe = & $sanitize $titleVal

                        $trackSafe = if ($trackVal) { '{0:D2}' -f $trackVal } else { '00' }

                        # Build destination directories
                        $albumFolderName = if ($yearSafe) { "$yearSafe - $albumSafe" } else { $albumSafe }
                        $artistDir = Join-Path $DestinationFolder $artistSafe

                        # Determine album directory candidate. If an existing album folder
                        # contains files of a different extension than the current file,
                        # prefer a numbered sibling folder like 'Album (2)' so different
                        # formats can coexist.
                        # New policy: if the base album folder already exists, always place this
                        # incoming folder into the next numbered sibling (Album (2), Album (3), ...)
                        # regardless of existing contents. This ensures we don't try to merge or
                        # infer similarity — the user can inspect duplicates later.
                        $albumBaseName = $albumFolderName
                        $idx = 1
                        $albumDir = $null
                        while ($true) {
                            if ($idx -eq 1) { $candidateName = $albumBaseName } else { $candidateName = "$albumBaseName ($idx)" }
                            $candidatePath = Join-Path $artistDir $candidateName
                            if (-not (Test-Path -LiteralPath $candidatePath)) {
                                # Found a non-existing candidate; use it
                                $albumDir = $candidatePath
                                break
                            }
                            else {
                                # If idx==1 and base exists, we should try the next number (always create numbered duplicates)
                                $idx++
                                continue
                            }
                        }

                        $targetDir = $albumDir
                        if ($useDiscFolders -and $discVal) {
                            $discSafe = & $sanitize $discVal
                            $targetDir = Join-Path $albumDir ("Disc $discSafe")
                        }

                        $ext = $f.Extension
                        $fileName = "${trackSafe} - ${titleSafe}${ext}"
                        $destFile = Join-Path $targetDir $fileName

                        # Ensure target dir exists when moving
                        if (-not (Test-Path -LiteralPath $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }

                        # Log planned move action
                        if ($LogPath) { Write-StructuredLog -Path $LogPath -Entry @{ Function='Update-MusicFolderMetadata'; Level='Info'; Status='WillMove'; Path=$folder; File=$f.FullName; Destination=$destFile; DryRun = ($PSCmdlet.ShouldProcess($f.FullName) -eq $false) } }

                        # Handle conflicts per OnConflict
                        if (Test-Path -LiteralPath $destFile) {
                            switch ($OnConflict) {
                                'Skip' { if (-not $Quiet) { Write-Output "Destination file exists, skipping: $destFile" }; continue }
                                'Overwrite' { Remove-Item -LiteralPath $destFile -Force -ErrorAction SilentlyContinue }
                                'Merge' { /* for files, treat Merge same as Overwrite */ Remove-Item -LiteralPath $destFile -Force -ErrorAction SilentlyContinue }
                            }
                        }

                        if ($PSCmdlet.ShouldProcess($f.FullName, "Move file to $destFile")) {
                            try {
                                Move-Item -LiteralPath $f.FullName -Destination $destFile -Force
                                if (-not $Quiet) { Write-Output "Moved: $($f.FullName) -> $destFile" }
                                if ($LogPath) { Write-StructuredLog -Path $LogPath -Entry @{ Function='Update-MusicFolderMetadata'; Level='Info'; Status='Moved'; Path=$folder; File=$f.FullName; Destination=$destFile } }
                            }
                            catch {
                                Write-Output "Failed to move file $($f.FullName) to ${destFile}: $($_)"
                                if ($LogPath) { Write-StructuredLog -Path $LogPath -Entry @{ Function='Update-MusicFolderMetadata'; Level='Error'; Status='MoveFailed'; Path=$folder; File=$f.FullName; Destination=$destFile; Details = @{ Error = $_.ToString() } } }
                            }
                        }
                    }

                    # Remove source folder if empty
                    try {
                        if ((Get-ChildItem -LiteralPath $folder -Recurse -File -ErrorAction SilentlyContinue).Count -eq 0) { Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue }
                    }
                    catch { }
                }
                    catch {
                        $errText = $_.ToString()
                        Write-Output ('Failed during move operation for folder ' + $folder + ': ' + $errText)
                    }
            }
        }
    }
}
