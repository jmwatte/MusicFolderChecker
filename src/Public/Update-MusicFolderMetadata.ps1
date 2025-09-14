<#
.SYNOPSIS
    Interactive and scripted metadata updater for music album folders with optional file relocation.

.DESCRIPTION
    Update-MusicFolderMetadata is the main function for processing music folders. It can work in interactive
    mode (prompting for metadata) or scripted mode (using provided parameters). The function can update
    embedded audio file tags and optionally move folders to a destination with proper organization.

    In interactive mode with SkipMode, users can enter '\' to postpone processing complex folders.
    The function supports loading/saving metadata from/to JSON files for automation workflows.

.PARAMETER FolderPath
    Path(s) to music folder(s) to process. Accepts pipeline input and has 'Path' alias. Mandatory parameter.

.PARAMETER AlbumArtist
    Album artist name to apply to all audio files in the folder(s).

.PARAMETER Album
    Album name to apply to all audio files in the folder(s).

.PARAMETER Year
    Release year to apply to all audio files in the folder(s).

.PARAMETER Interactive
    Switch parameter. When specified, prompts user for metadata values not provided as parameters.

.PARAMETER Quiet
    Switch parameter. When specified, suppresses detailed console output.

.PARAMETER DestinationFolder
    Destination directory for moving processed folders. Required when using -Move.

.PARAMETER DestinationPattern
    Custom pattern for destination folder organization (not yet implemented).

.PARAMETER Move
    Switch parameter. When specified, moves folders to DestinationFolder after processing.

.PARAMETER LogPath
    Path to save structured JSONL log entries for audit and troubleshooting.

.PARAMETER MetadataJson
    Path to JSON file containing pre-defined metadata for folders.

.PARAMETER SkipMode
    When used with -Interactive, allows entering '\' during prompts to postpone/skip complex folders for later processing. Skipped folders are collected and reported at the end.

.PARAMETER OutputMetadataJson
    Path to save collected metadata as JSON for future automated processing.

.PARAMETER OnConflict
    How to handle file conflicts during moves. Valid values: 'Skip', 'Overwrite', 'Merge'. Default is 'Skip'.

.PARAMETER PreserveTrackArtists
    For compilation albums (Various Artists), preserve individual track artists instead of overwriting them with the album artist. Default is true for compilations.

.INPUTS
    System.String
    You can pipe folder paths to Update-MusicFolderMetadata.

.OUTPUTS
    None directly, but writes to console, log files, and optionally moves files.

.EXAMPLE
    Update-MusicFolderMetadata -FolderPath 'E:\Music\Artist\2020 - Album' -Interactive
    Processes the folder interactively, prompting for any missing metadata

.EXAMPLE
    Update-MusicFolderMetadata -FolderPath 'E:\Music\Artist\2020 - Album' -AlbumArtist 'Artist Name' -Album 'Album Title' -Year 2020 -Move -DestinationFolder 'E:\Processed'
    Updates metadata and moves the folder to organized destination

.EXAMPLE
    Find-BadMusicFolderStructure -StartingPath 'E:\Music' | Update-MusicFolderMetadata -Interactive -SkipMode -WhatIf
    Finds folders and processes them interactively with skip option in preview mode

.EXAMPLE
    Update-MusicFolderMetadata -FolderPath 'E:\Music\Artist\2020 - Album' -MetadataJson 'C:\Temp\metadata.json' -OutputMetadataJson 'C:\Temp\updated_metadata.json'
    Loads metadata from file, processes folder, and saves updated metadata

.EXAMPLE
    Get-Content 'C:\Temp\log.jsonl' | ConvertFrom-Json | Select-Object -ExpandProperty Path | Update-MusicFolderMetadata -Interactive -SkipMode
    Processes folders from JSONL log entries with interactive skip capability

.EXAMPLE
    Update-MusicFolderMetadata -FolderPath 'E:\Music\Compilations\Various Artists - 2020 Hits' -AlbumArtist 'Various Artists' -PreserveTrackArtists
    Updates compilation album metadata while preserving individual track artists

.NOTES
    Author: MusicFolderChecker Module
    Requires TagLib-Sharp.dll for audio file processing
    Supports WhatIf for safe preview of all operations
    Interactive mode with SkipMode uses '\' to postpone complex folders
    Automatically creates destination directories as needed
    Preserves existing metadata when only partial updates are requested
#>

function Update-MusicFolderMetadata {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('Path')]
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
        [switch]$SkipMode,

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
    [string]$MetadataJson,

    [Parameter()]
    [switch]$PreserveTrackArtists,
    
    [Parameter()]
    [switch]$PreserveFilenames,
    
    [Parameter()]
    [string]$OutputMetadataJson,        [Parameter()]
        [ValidateSet('Skip','Overwrite','Merge')]
        [string]$OnConflict = 'Skip'
    )

    begin {
        $musicExtensions = @('.mp3', '.flac', '.m4a', '.ogg', '.wav', '.aac', '.ape', '.mpc')
        
        # Load metadata from JSON if provided
        $loadedMetadata = @{}
        if ($MetadataJson -and (Test-Path $MetadataJson)) {
            try {
                $jsonContent = Get-Content $MetadataJson -Raw | ConvertFrom-Json
                foreach ($item in $jsonContent) {
                    $loadedMetadata[$item.FolderPath] = $item
                }
                if (-not $Quiet) { Write-Output "Loaded metadata for $($loadedMetadata.Count) folders from $MetadataJson" }
            }
            catch {
                Write-Output "Warning: Failed to load metadata from $MetadataJson`: $_"
            }
        }
        
        # Collection for output metadata
        $collectedMetadata = @()
        $skippedFolders = @()
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

            # Use loaded metadata if available
            if ($loadedMetadata.ContainsKey($folder)) {
                $metadata = $loadedMetadata[$folder]
                if (-not $applyAlbumArtist -and $metadata.AlbumArtist) { $applyAlbumArtist = $metadata.AlbumArtist }
                if (-not $applyAlbum -and $metadata.Album) { $applyAlbum = $metadata.Album }
                if (-not $applyYear -and $metadata.Year) { $applyYear = $metadata.Year }
                if (-not $Quiet) { Write-Output "Using pre-loaded metadata for $folder" }
            }

            $doInteractive = $false
            if ($Interactive.IsPresent) { $doInteractive = $true }
            elseif (-not $AlbumArtist -and -not $Album -and -not $Year -and -not $loadedMetadata.ContainsKey($folder)) { $doInteractive = $true }

            if ($doInteractive) {
                # Normalize WhatIf detection: accept explicit -WhatIf or $WhatIfPreference being 'Inquire'/'Continue' etc.
                $isWhatIf = $false
                try {
                    if ($PSBoundParameters.ContainsKey('WhatIf')) { $isWhatIf = $true }
                    elseif ($WhatIfPreference -eq $true) { $isWhatIf = $true }
                }
                catch { $isWhatIf = $false }

                if (-not $Quiet) { Write-Output "`nFolder: $folder" }
                # Provide the full path to the first audio file found so user can infer metadata from path
                if ($firstAudio -and -not $Quiet) { Write-Output "Representative audio file: $($firstAudio.FullName)" }
                if (-not $Quiet) { Write-Output "Current Album Artist: $currentAlbumArtist" }
                if (-not $Quiet) { Write-Output "Current Album       : $currentAlbum" }
                if (-not $Quiet) { Write-Output "Current Year        : $currentYear" }
                
                # Flag to track if folder should be skipped
                $skipThisFolder = $false
                
                try {
                    if ($SkipMode) {
                        $resp = Read-Host -Prompt "Enter Album Artist (blank to keep, '\' to postpone this folder)"
                        if ($resp -eq '\') {
                            $skipThisFolder = $true
                        }
                    } else {
                        $resp = Read-Host -Prompt "Enter Album Artist (blank to keep)"
                    }
                    if ($resp -ne '' -and -not $skipThisFolder) { $applyAlbumArtist = $resp }
                    
                    if (-not $skipThisFolder) {
                        if ($SkipMode) {
                            $resp = Read-Host -Prompt "Enter Album (blank to keep, '\' to postpone this folder)"
                            if ($resp -eq '\') {
                                $skipThisFolder = $true
                            }
                        } else {
                            $resp = Read-Host -Prompt "Enter Album (blank to keep)"
                        }
                        if ($resp -ne '' -and -not $skipThisFolder) { $applyAlbum = $resp }
                    }

                    # Repeatedly prompt for Year until the user provides a blank (keep) or a valid integer.
                    if (-not $skipThisFolder) {
                        while ($true) {
                            if ($SkipMode) {
                                $resp = Read-Host -Prompt "Enter Year (blank to keep, '\' to postpone this folder)"
                                if ($resp -eq '\') {
                                    $skipThisFolder = $true
                                    break
                                }
                            } else {
                                $resp = Read-Host -Prompt "Enter Year (blank to keep)"
                            }
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
                }

                # Get sample audio files for filename preview
                $sampleAudioFiles = Get-ChildItem -LiteralPath $folder -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $musicExtensions -contains $_.Extension.ToLower() } | Select-Object -First 3
                if ($sampleAudioFiles) {
                    Write-Output "`nFilename preview (original vs. default renaming):"
                    foreach ($f in $sampleAudioFiles) {
                        try {
                            $tag = Invoke-TagLibCreate -Path $f.FullName
                            $track = $tag.Tag.Track
                            $title = $tag.Tag.Title
                            $trackSafe = if ($track) { '{0:D2}' -f [int]$track } else { '00' }
                            $titleSafe = [regex]::Replace($title, '[\\/:*?"<>|]', '')
                            $defaultName = "${trackSafe} - ${titleSafe}$($f.Extension)"
                            Write-Output "  Original: $($f.Name)"
                            Write-Output "  Default:  $defaultName"
                            Write-Output ""
                        } catch {
                            Write-Output "  $($f.Name) - (could not read tags)"
                            Write-Output ""
                        }
                    }
                }

                # Prompt for filename preservation if moving
                if (-not $skipThisFolder -and $Move.IsPresent) {
                    if ($SkipMode) {
                        $resp = Read-Host -Prompt "Preserve original filenames during move? (Y/N, default N, '\' to postpone this folder)"
                        if ($resp -eq '\') {
                            $skipThisFolder = $true
                        } elseif ($resp -eq 'Y' -or $resp -eq 'y') {
                            $PreserveFilenames = $true
                        }
                    } else {
                        $resp = Read-Host -Prompt "Preserve original filenames during move? (Y/N, default N)"
                        if ($resp -eq 'Y' -or $resp -eq 'y') {
                            $PreserveFilenames = $true
                        }
                    }
                }

                catch {
                    # User cancelled interactive input (ctrl+c) or another error occurred.
                    if ($LogPath) { Write-StructuredLog -Path $LogPath -Entry @{ Function='Update-MusicFolderMetadata'; Level='Warning'; Status='InteractiveCanceled'; Path=$folder; Details = @{ Error = $_.ToString() } } }
                    Write-Output "Interactive input cancelled. Skipping folder: $folder"
                    continue
                }
                
                # Handle folder skipping
                if ($skipThisFolder) {
                    $skippedFolders += $folder
                    if (-not $Quiet) { Write-Output "Skipped folder: $folder" }
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
            # Precompute non-audio files and audio root so planned moves always include non-audio files
            $otherFiles = Get-ChildItem -LiteralPath $folder -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $musicExtensions -notcontains $_.Extension.ToLower() }
            $audioDirs = @($audioFiles | ForEach-Object { $_.DirectoryName } | Sort-Object -Unique)
            if ($audioDirs.Count -eq 1) { $audioRoot = $audioDirs[0] } else {
                $parts = $audioDirs | ForEach-Object { $_ -split '[\\/]+' }
                $minLen = ($parts | ForEach-Object { $_.Length } | Measure-Object -Minimum).Minimum
                $common = @()
                for ($i = 0; $i -lt $minLen; $i++) {
                    $val = $parts[0][$i]
                    if ($parts | Where-Object { $_[$i] -ne $val }) { break }
                    $common += $val
                }
                if ($common.Count -gt 0) { $audioRoot = ($common -join '\\') } else { $audioRoot = $folder }
            }
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

                        if ($PSCmdlet.ShouldProcess((Split-Path $f.FullName -Leaf), 'Update music tags')) {
                    try {
                        # Reuse $t opened above
                        if ($applyAlbumArtist -and $applyAlbumArtist -ne '') {
                            # For compilations (Various Artists), preserve individual track artists unless explicitly told not to
                            if ($applyAlbumArtist -eq 'Various Artists' -or $applyAlbumArtist -eq 'V.A.' -or $applyAlbumArtist -eq 'VA') {
                                $t.Tag.AlbumArtists = @($applyAlbumArtist)
                                # Preserve original track artist unless PreserveTrackArtists is false
                                if (-not $PreserveTrackArtists) {
                                    $t.Tag.Performers = @($applyAlbumArtist)
                                }
                                # If PreserveTrackArtists is true, don't overwrite Performers
                            } else {
                                # For regular albums, set both album artist and track artist
                                $t.Tag.Performers = @($applyAlbumArtist)
                                $t.Tag.AlbumArtists = @($applyAlbumArtist)
                            }
                        }
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

            # Collect metadata for output if requested
            if ($OutputMetadataJson -and ($applyAlbumArtist -or $applyAlbum -or $applyYear)) {
                $metadataEntry = @{
                    FolderPath = $folder
                    AlbumArtist = $applyAlbumArtist
                    Album = $applyAlbum
                    Year = $applyYear
                    Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                }
                $collectedMetadata += $metadataEntry
            }

            # Optional move: after tag updates, move files to a structured destination when requested
            if ($Move.IsPresent -and $DestinationFolder) {
                # Determine WhatIf mode for the move operation
                $isWhatIf = $false
                if ($PSBoundParameters.ContainsKey('WhatIf')) { 
                    $isWhatIf = $true 
                }
                elseif ($WhatIfPreference) { 
                    $isWhatIf = $true 
                }
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

                    # Also parse disc from album name if present
                    $discFromAlbum = $null
                    if ($albumValSample -match '(?i)disc\s*(\d+)') {
                        $discFromAlbum = [int]$matches[1]
                    }
                    elseif ($albumValSample -match '(?i)cd\s*(\d+)') {
                        $discFromAlbum = [int]$matches[1]
                    }
                    elseif ($albumValSample -match '(?i)part\s*(\d+)') {
                        $discFromAlbum = [int]$matches[1]
                    }
                    if ($discFromAlbum) { $discNumbers += $discFromAlbum }

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
                        $albumValSample = $currentAlbum
                    }
                    $artistValSample = $applyAlbumArtist
                    if (-not $artistValSample) {
                        $artistValSample = $currentAlbumArtist
                    }

                    $artistSafeSample = & $sanitize $artistValSample
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

                    # Normalize album name by removing disc information for folder naming
                    $normalizedAlbumSample = $albumValSample -replace '(?i)\s*(?:disc|cd|part)\s*\d+.*$', '' -replace '(?i)\s*(?:disc|cd|part).*$', ''
                    $normalizedAlbumSafe = & $sanitize $normalizedAlbumSample

                    $albumFolderName = if ($yearSafeSample) { "$yearSafeSample - $normalizedAlbumSafe" } else { $normalizedAlbumSafe }
                    $artistDir = Join-Path $DestinationFolder $artistSafeSample

                    # For multi-disc albums, always use the same base album folder
                    # Disc subfolders will be created within this album folder
                    $albumDir = Join-Path $artistDir $albumFolderName

                    # Only create numbered album folders if there's a conflict with non-disc content
                    # (i.e., if the album folder exists and contains files that aren't in disc subfolders)
                    if ((Test-Path -LiteralPath $albumDir) -and -not $useDiscFolders) {
                        $idx = 2
                        $candidateDir = $albumDir
                        while (Test-Path -LiteralPath $candidateDir) {
                            $candidateDir = Join-Path $artistDir "$albumFolderName ($idx)"
                            $idx++
                        }
                        $albumDir = $candidateDir
                    }

                    # Collect planned moves so we can show a concise summary in -WhatIf mode
                    $plannedMoves = @()
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
                        if ($PreserveFilenames) {
                            $fileName = $f.Name
                        } else {
                            $fileName = "${trackSafe} - ${titleSafe}${ext}"
                        }
                        $destFile = Join-Path $targetDir $fileName

                        # Ensure artist/album (and disc) dirs exist when moving (create once per needed dir)
                        if (-not (Test-Path -LiteralPath $artistDir)) {
                            if (-not $isWhatIf) {
                                if ($PSCmdlet.ShouldProcess((Split-Path $artistDir -Leaf), 'Create Directory')) { [System.IO.Directory]::CreateDirectory($artistDir) | Out-Null }
                            }
                            else {
                                # WhatIf: don't call ShouldProcess to avoid engine output; record planned directory creation in structured log
                                if ($LogPath) { Write-StructuredLog -Path $LogPath -Entry @{ Function='Update-MusicFolderMetadata'; Level='Info'; Status='WillCreateDirectory'; Path=$artistDir; DryRun = $true } }
                            }
                        }
                        if (-not (Test-Path -LiteralPath $albumDir)) {
                            if (-not $isWhatIf) {
                                if ($PSCmdlet.ShouldProcess((Split-Path $albumDir -Leaf), 'Create Directory')) { [System.IO.Directory]::CreateDirectory($albumDir) | Out-Null }
                            }
                            else {
                                if ($LogPath) { Write-StructuredLog -Path $LogPath -Entry @{ Function='Update-MusicFolderMetadata'; Level='Info'; Status='WillCreateDirectory'; Path=$albumDir; DryRun = $true } }
                            }
                        }
                        if ($targetDir -ne $albumDir -and -not (Test-Path -LiteralPath $targetDir)) {
                            if (-not $isWhatIf) {
                                if ($PSCmdlet.ShouldProcess((Split-Path $targetDir -Leaf), 'Create Directory')) { [System.IO.Directory]::CreateDirectory($targetDir) | Out-Null }
                            }
                            else {
                                if ($LogPath) { Write-StructuredLog -Path $LogPath -Entry @{ Function='Update-MusicFolderMetadata'; Level='Info'; Status='WillCreateDirectory'; Path=$targetDir; DryRun = $true } }
                            }
                        }

                        # Log planned move action (avoid calling ShouldProcess when -WhatIf to prevent engine output)
                        if ($LogPath) { Write-StructuredLog -Path $LogPath -Entry @{ Function='Update-MusicFolderMetadata'; Level='Info'; Status='WillMove'; Path=$folder; File=$f.FullName; Destination=$destFile; DryRun = $isWhatIf } }
                        # Record the planned move for a summary when running with -WhatIf
                        $plannedMoves += [pscustomobject]@{ Source = $f.FullName; Destination = $destFile; Type = 'Audio' }

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

                        if ($isWhatIf) {
                            # In WhatIf mode we skip calling ShouldProcess/Move-Item to avoid engine WhatIf messages; actions are summarized later.
                        }
                        else {
                            if ($PSCmdlet.ShouldProcess((Split-Path $f.FullName -Leaf), "Move to " + (Split-Path $destFile -Leaf))) {
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
                    }
                    # Move non-audio files (artwork, cue, logs, etc.) into the album root folder so
                    # relative references (e.g. .cue) and cover files remain valid.
                    try {
                        # otherFiles and audioRoot are precomputed earlier; use them here
                        Write-Verbose "Found $($otherFiles.Count) non-audio files to process"
                        if ($otherFiles.Count -gt 0) {
                            foreach ($of in $otherFiles) {
                                Write-Verbose "Processing non-audio file: $($of.FullName)"
                                # Preserve source-relative directory structure under the album directory.
                                $folderRoot = $audioRoot.TrimEnd('\','/')
                                $destFile = Join-Path $albumDir $of.Name
                                $sourceDir = $of.DirectoryName
                                $rel = ''
                                try {
                                    if ($sourceDir.Length -gt $folderRoot.Length) {
                                        $rel = $sourceDir.Substring($folderRoot.Length) -replace '^[\\/]+',''
                                    }
                                }
                                catch { $rel = '' }

                                $destDirForOther = if ($rel) { Join-Path $albumDir $rel } else { $albumDir }
                                # Ensure destination directory exists (or record it in WhatIf)
                                if (-not (Test-Path -LiteralPath $destDirForOther)) {
                                    if (-not $isWhatIf) {
                                        if ($PSCmdlet.ShouldProcess($destDirForOther, 'Create Directory')) { [System.IO.Directory]::CreateDirectory($destDirForOther) | Out-Null }
                                    }
                                    else {
                                        if ($LogPath) { Write-StructuredLog -Path $LogPath -Entry @{ Function='Update-MusicFolderMetadata'; Level='Info'; Status='WillCreateDirectory'; Path=$destDirForOther; DryRun = $true } }
                                    }
                                }

                                $destFile = Join-Path $destDirForOther $of.Name
                                # Record planned move for non-audio files as well
                                $plannedMoves += [pscustomobject]@{ Source = $of.FullName; Destination = $destFile; Type = 'Other' }

                                if (Test-Path -LiteralPath $destFile) {
                                    switch ($OnConflict) {
                                        'Skip' { if (-not $Quiet) { Write-Output "Destination file exists, skipping: $destFile" }; continue }
                                        'Overwrite' { Remove-Item -LiteralPath $destFile -Force -ErrorAction SilentlyContinue }
                                        'Merge' { Remove-Item -LiteralPath $destFile -Force -ErrorAction SilentlyContinue }
                                    }
                                }

                                if ($isWhatIf) {
                                    # skip actual move in WhatIf mode; summary will show planned moves
                                }
                                else {
                                    if ($PSCmdlet.ShouldProcess((Split-Path $of.FullName -Leaf), "Move to " + (Split-Path $destFile -Leaf))) {
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
                    }
                    catch { Write-Verbose "Error processing non-audio files: $_" }
                    # If running with -WhatIf, print a concise summary of planned moves for this folder
                    try {
                        if ($isWhatIf) {
                            if ($plannedMoves.Count -gt 0) {
                                if (-not $Quiet) { Write-Output "`nWhatIf planned moves for: $folder ($($plannedMoves.Count))" }
                                foreach ($p in $plannedMoves) {
                                    # Show just filename for source, and compact destination path
                                    $sourceFile = Split-Path $p.Source -Leaf
                                    $destFile = Split-Path $p.Destination -Leaf
                                    $destFolder = Split-Path $p.Destination -Parent
                                    
                                    # Improve destination folder display for readability
                                    if ($destFolder.Length -gt 60) {
                                        # Show last 3 folder levels with ellipsis
                                        $parts = $destFolder -split '[\\/]'
                                        if ($parts.Count -gt 3) {
                                            $destFolder = "..." + ($parts[-3..-1] -join '\')
                                        } else {
                                            $destFolder = "..." + $destFolder.Substring($destFolder.Length - 47)
                                        }
                                    }
                                    
                                    if (-not $Quiet) { Write-Output "  $sourceFile -> $destFolder\$destFile" }
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

    end {
        # Output collected metadata if requested
        if ($OutputMetadataJson -and $collectedMetadata.Count -gt 0) {
            try {
                $collectedMetadata | ConvertTo-Json -Depth 3 | Out-File -FilePath $OutputMetadataJson -Encoding UTF8
                if (-not $Quiet) { Write-Output "Exported metadata for $($collectedMetadata.Count) folders to $OutputMetadataJson" }
            }
            catch {
                Write-Output "Warning: Failed to export metadata to $OutputMetadataJson`: $_"
            }
        }

        # Report skipped folders
        if ($skippedFolders.Count -gt 0 -and -not $Quiet) {
            Write-Output "`nSkipped folders ($($skippedFolders.Count)):"
            foreach ($skipped in $skippedFolders) {
                Write-Output "  $skipped"
            }
        }
    }
}
