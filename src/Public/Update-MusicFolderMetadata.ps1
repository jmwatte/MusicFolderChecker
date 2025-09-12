<#
.SYNOPSIS
    Interactive and scripted metadata updater for album folders.

EXAMPLE
    Update-MusicFolderMetadata -FolderPath 'E:\Music\Artist\2020 - Album' -AlbumArtist 'Various Artists' -Year 2020 -WhatIf

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

        [Parameter()]
        [switch]$Quiet,

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
                try {
                    $resp = Read-Host -Prompt "Enter Album Artist (blank to keep)"
                    if ($resp -ne '') { $applyAlbumArtist = $resp }
                    $resp = Read-Host -Prompt "Enter Album (blank to keep)"
                    if ($resp -ne '') { $applyAlbum = $resp }

                    # Repeatedly prompt for Year until the user provides a blank (keep) or a valid integer.
                    while ($true) {
                        $resp = Read-Host -Prompt "Enter Year (blank to keep)"
                        if ($resp -eq '') {
                            # User chose to keep existing year
                            break
                        }
                        # Try parse integer year
                        $parsed = $null
                        if ([int]::TryParse($resp, [ref]$parsed)) {
                            $applyYear = [int]$parsed
                            break
                        }
                        else {
                            Write-Output "Invalid year entered. Please enter a four-digit year (e.g. 2011), or press Enter to keep the current value."
                            # loop continues and user will be prompted again
                        }
                    }
                }
                catch {
                    # User cancelled interactive input (ctrl+c) or another error occurred.
                    if ($LogPath) { Write-StructuredLog -Path $LogPath -Entry @{ Function='Update-MusicFolderMetadata'; Level='Warning'; Status='InteractiveCanceled'; Path=$folder; Details = @{ Error = $_.ToString() } } }
                    Write-Output "Interactive input cancelled. Skipping folder: $folder"
                    continue
                }
            }

            # No changes requested?
            $noChanges = (($applyAlbumArtist -eq $null -or $applyAlbumArtist -eq '') -and ($applyAlbum -eq $null -or $applyAlbum -eq '') -and (-not $applyYear))
            if ($noChanges) {
                if (-not $Quiet) { Write-Output "No changes for $folder" }
                # If the user requested a move, proceed to move even when there are no tag changes.
                if (-not $Move.IsPresent) {
                    # Log that we skipped because there were no changes and the user did not request a move
                    if ($LogPath) { Write-StructuredLog -Path $LogPath -Entry @{ Function='Update-MusicFolderMetadata'; Level='Info'; Status='SkippedNoChanges'; Path=$folder; Details = @{ Reason='NoRequestedChanges'; AlbumArtist=$applyAlbumArtist; Album=$applyAlbum; Year=$applyYear } } }
                    continue
                }
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
            # ...existing tag update code...
            foreach ($f in $audioFiles) {
                # Open the file and inspect current tags to determine whether an update is actually required.
                try {
                    $t = Invoke-TagLibCreate -Path $f.FullName
                }
                catch {
                    Write-Output "Failed to read tags for $($f.FullName): $_"
                    continue
                }

                $curArtist = ($null -ne $t.Tag.AlbumArtists -and $t.Tag.AlbumArtists.Count -gt 0) ? $t.Tag.AlbumArtists[0] : ($null -ne $t.Tag.Performers -and $t.Tag.Performers.Count -gt 0 ? $t.Tag.Performers[0] : '')
                $curAlbum = $t.Tag.Album
                $curYear = $t.Tag.Year

                $needUpdate = $false
                if ($applyAlbumArtist -and $applyAlbumArtist -ne '' -and $applyAlbumArtist -ne $curArtist) { $needUpdate = $true }
                if ($applyAlbum -and $applyAlbum -ne '' -and $applyAlbum -ne $curAlbum) { $needUpdate = $true }
                if ($applyYear -and ([int]$applyYear -ne 0) -and $applyYear -ne $curYear) { $needUpdate = $true }

                if (-not $needUpdate) {
                    if (-not $Quiet) { Write-Output "No tag changes for $($f.FullName)" }
                    continue
                }

                        if ($PSCmdlet.ShouldProcess($f.FullName, 'Update music tags')) {
                    try {
                        # Reuse $t opened above
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

                    # Decide album/artist directory once for the entire album (album-level placement)
                    $albumValSample = $applyAlbum
                    if (-not $albumValSample -or $albumValSample -eq '') {
                        # fallback to first audio file's album if none provided
                        try {
                            $albumValSample = (Invoke-TagLibCreate -Path $audioFiles[0].FullName).Tag.Album
                        }
                        catch {
                            $albumValSample = 'Unknown Album'
                        }
                    }
                    $artistValSample = $applyAlbumArtist
                    if (-not $artistValSample -or $artistValSample -eq '') {
                        try {
                            $artistValSample = (Invoke-TagLibCreate -Path $audioFiles[0].FullName).Tag.AlbumArtists[0]
                        }
                        catch {
                            $artistValSample = 'Unknown Artist'
                        }
                    }

                    $artistSafeSample = & $sanitize $artistValSample
                    $albumSafeSample = & $sanitize $albumValSample
                    # compute year sample with proper try/catch (avoid inline Try/ Catch expression)
                    $yearSampleRaw = ''
                    if ($applyYear) { $yearSampleRaw = $applyYear }
                    else {
                        try {
                            $yearSampleRaw = (Invoke-TagLibCreate -Path $audioFiles[0].FullName).Tag.Year
                        }
                        catch {
                            $yearSampleRaw = ''
                        }
                    }
                    $yearSafeSample = & $sanitize $yearSampleRaw

                    $albumFolderName = if ($yearSafeSample) { "$yearSafeSample - $albumSafeSample" } else { $albumSafeSample }
                    $artistDir = Join-Path $DestinationFolder $artistSafeSample

                    # Pick a single album directory candidate (numbered sibling only if base exists at destination).
                    $albumBaseName = $albumFolderName
                    $idx = 1
                    $albumDir = $null
                    while ($true) {
                        if ($idx -eq 1) { $candidateName = $albumBaseName } else { $candidateName = "$albumBaseName ($idx)" }
                        $candidatePath = Join-Path $artistDir $candidateName
                        if (-not (Test-Path -LiteralPath $candidatePath)) {
                            $albumDir = $candidatePath
                            break
                        }
                        else {
                            $idx++
                            continue
                        }
                    }

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

                        # per-file sanitized values not needed for album-level placement; compute only title/track
                        $titleSafe = & $sanitize $titleVal

                        $trackSafe = if ($trackVal) { '{0:D2}' -f $trackVal } else { '00' }

                        # Build destination directories
                        $targetDir = $albumDir
                        if ($useDiscFolders -and $discVal) {
                            $discSafe = & $sanitize $discVal
                            $targetDir = Join-Path $albumDir ("Disc $discSafe")
                        }

                        $ext = $f.Extension
                        $fileName = "${trackSafe} - ${titleSafe}${ext}"
                        $destFile = Join-Path $targetDir $fileName

                        # Ensure artist/album (and disc) dirs exist when moving (create once per needed dir)
                        if (-not (Test-Path -LiteralPath $artistDir)) { if ($PSCmdlet.ShouldProcess($artistDir, 'Create Directory')) { New-Item -ItemType Directory -Path $artistDir -Force | Out-Null } }
                        if (-not (Test-Path -LiteralPath $albumDir)) { if ($PSCmdlet.ShouldProcess($albumDir, 'Create Directory')) { New-Item -ItemType Directory -Path $albumDir -Force | Out-Null } }
                        if ($targetDir -ne $albumDir -and -not (Test-Path -LiteralPath $targetDir)) { if ($PSCmdlet.ShouldProcess($targetDir, 'Create Directory')) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null } }

                        # Log planned move action
                        if ($LogPath) { Write-StructuredLog -Path $LogPath -Entry @{ Function='Update-MusicFolderMetadata'; Level='Info'; Status='WillMove'; Path=$folder; File=$f.FullName; Destination=$destFile; DryRun = ($PSCmdlet.ShouldProcess($f.FullName) -eq $false) } }

                        # Handle conflicts per OnConflict
                        if (Test-Path -LiteralPath $destFile) {
                            switch ($OnConflict) {
                                'Skip' { if (-not $Quiet) { Write-Output "Destination file exists, skipping: $destFile" }; continue }
                                'Overwrite' { Remove-Item -LiteralPath $destFile -Force -ErrorAction SilentlyContinue }
                                'Merge' { # for files, treat Merge same as Overwrite
                                    Remove-Item -LiteralPath $destFile -Force -ErrorAction SilentlyContinue
                                }
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
                    # Move non-audio files (artwork, cue, logs, etc.) into the album root folder so
                    # relative references (e.g. .cue) and cover files remain valid.
                    try {
                        $otherFiles = Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue | Where-Object { $musicExtensions -notcontains $_.Extension.ToLower() }
                        if ($otherFiles.Count -gt 0) {
                            foreach ($of in $otherFiles) {
                                $destFile = Join-Path $albumDir $of.Name
                                if (Test-Path -LiteralPath $destFile) {
                                    switch ($OnConflict) {
                                        'Skip' { if (-not $Quiet) { Write-Output "Destination file exists, skipping: $destFile" }; continue }
                                        'Overwrite' { Remove-Item -LiteralPath $destFile -Force -ErrorAction SilentlyContinue }
                                        'Merge' { Remove-Item -LiteralPath $destFile -Force -ErrorAction SilentlyContinue }
                                    }
                                }
                                if ($PSCmdlet.ShouldProcess($of.FullName, "Move file to $destFile")) {
                                    try {
                                        Move-Item -LiteralPath $of.FullName -Destination $destFile -Force
                                        if (-not $Quiet) { Write-Output "Moved: $($of.FullName) -> $destFile" }
                                    }
                                    catch {
                                        Write-Output "Failed to move file $($of.FullName): $_"
                                    }
                                }
                            }
                        }
                    }
                    catch { }

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
