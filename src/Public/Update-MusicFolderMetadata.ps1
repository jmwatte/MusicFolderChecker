<#
.SYNOPSIS
    Interactive and scripted metadata updater for music album folders with optional file relocation.

.DESCRIPTION
    Update-MusicFolderMetadata is the main function for processing music folders. It can work in interactive
    mode (prompting for metadata values) or scripted mode (using provided parameters). The function can update
    embedded audio file tags and optionally move folders to a destination with proper organization.

    The function automatically enters interactive mode when:
    - The -Interactive parameter is specified, OR
    - Any required metadata (AlbumArtist, Album, Year) is missing and no metadata is loaded from JSON

    In interactive mode with SkipMode, users can enter '\' to postpone processing complex folders.
    The function supports loading/saving metadata from/to JSON files for automation workflows.

    Note: The -Quiet parameter suppresses verbose output but still displays essential information
    during interactive mode, including current metadata values and prompts..PARAMETER FolderPath
    Path(s) to music folder(s) to process. Accepts pipeline input and has 'Path' alias. Mandatory parameter.

.PARAMETER AlbumArtist
    Album artist name to apply to all audio files in the folder(s).

.PARAMETER Album
    Album name to apply to all audio files in the folder(s).

.PARAMETER Year
    Release year to apply to all audio files in the folder(s).

.PARAMETER Interactive
    Switch parameter. When specified, prompts user for metadata values not provided as parameters.
    If not specified, the function automatically prompts when any required metadata is missing.

.PARAMETER Quiet
    Switch parameter. When specified, suppresses detailed console output except for essential interactive prompts and current metadata values.

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

.PARAMETER PreserveFilenames
    When moving files, preserve original filenames instead of renaming to standardized format.

.PARAMETER DefaultPreserveFilenames
    Set the default behavior for filename preservation in interactive mode. When $true, the default will be to preserve filenames. When $false (default), the default will be to rename files to standardized format.

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

.EXAMPLE
    Update-MusicFolderMetadata -FolderPath 'E:\Music\Artist\2020 - Album' -Interactive -Move -DestinationFolder 'E:\Processed' -DefaultPreserveFilenames:$true
    Processes folder interactively with move, defaulting to preserve original filenames during the move operation

.EXAMPLE
    Update-MusicFolderMetadata -FolderPath 'E:\Music\Artist\2020 - Album' -Interactive -Move -DestinationFolder 'E:\Processed'
    Processes folder interactively with intelligent filename analysis - automatically determines whether to preserve or rename filenames based on quality analysis

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
    [switch]$NonInteractive,

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
    [bool]$DefaultPreserveFilenames = $false,
    
    [Parameter()]
    [string]$OutputMetadataJson,        [Parameter()]
        [ValidateSet('Skip','Overwrite','Merge')]
        [string]$OnConflict = 'Skip',

        [Parameter()]
        [switch]$AllowCollectionChanges,

        [Parameter()]
        [switch]$UseConsensusHints
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
            # Phase 2 safety: classify folder structure and apply guardrails for collections
            try {
                $folderAnalysis = if ($UseConsensusHints) {
                    Get-FolderStructureAnalysis -Path $folder -UseConsensusHints:$true
                } else {
                    Get-FolderStructureAnalysis -Path $folder
                }
            }
            catch {
                if (-not $Quiet) { Write-Output ("Warning: Failed to analyze structure for {0}: {1}" -f $folder, $_) }
                $folderAnalysis = $null
            }

            if ($folderAnalysis) {
                $st = $folderAnalysis.StructureType
                if ($st -in @('BoxSet','ArtistFolder')) {
                    if (-not $AllowCollectionChanges) {
                        if ($Interactive) {
                            Write-Warning "This folder appears to be a $st. Processing it as a single album may alter a collection."
                            Write-Output "Recommendations: $($folderAnalysis.Recommendations -join '; ')"
                            $resp = Read-Host "Continue anyway? (Y/N)"
                            if ($resp -ne 'Y' -and $resp -ne 'y') {
                                if (-not $Quiet) { Write-Output "Skipping collection root: $folder" }
                                continue
                            }
                        } else {
                            if (-not $Quiet) { Write-Output "Skipping collection root (use -AllowCollectionChanges to override): $folder" }
                            continue
                        }
                    }
                }
            }
            # Clear variables to prevent state contamination between folders
            $tagFile = $null
            $currentAlbumArtist = $null
            $currentAlbum = $null
            $currentYear = $null
            $applyAlbumArtist = $null
            $applyAlbum = $null
            $applyYear = $null
            $firstAudio = $null
            $metadataLooksValid = $true

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
                # Clear TagLib cache to prevent state contamination between folders
                try {
                    $cache = [TagLib.File]::Cache
                    if ($cache) {
                        $cache.Clear()
                    }
                } catch {
                    # Ignore if cache clearing fails
                }
                $tagFile = Invoke-TagLibCreate -Path $firstAudio.FullName
                if (-not $tagFile) {
                    Write-Output "Failed to read tags from $($firstAudio.FullName): TagLib returned null"
                    continue
                }
            }
            catch {
                Write-Output "Failed to read tags from $($firstAudio.FullName): $_"
                # For testing purposes, continue with empty metadata if tag reading fails
                $tagFile = $null
                $currentAlbumArtist = ''
                $currentAlbum = ''
                $currentYear = 0
                if (-not $Quiet) {
                    Write-Output "Continuing with empty metadata for testing purposes"
                }
            }

            # Log folder processing start
            if ($LogPath) {
                $entry = @{ Function = 'Update-MusicFolderMetadata'; Level = 'Info'; Status = 'Start'; Path = $folder; DryRun = ($PSCmdlet.ShouldProcess($folder) -eq $false) }
                Write-StructuredLog -Path $LogPath -Entry $entry
            }

            # Read metadata from tag file if available
            if ($tagFile) {
                $currentAlbumArtist = ($null -ne $tagFile.Tag.AlbumArtists -and $tagFile.Tag.AlbumArtists.Count -gt 0) ? $tagFile.Tag.AlbumArtists[0] : ($null -ne $tagFile.Tag.Performers -and $tagFile.Tag.Performers.Count -gt 0 ? $tagFile.Tag.Performers[0] : '')
                $currentAlbum = $tagFile.Tag.Album
                $currentYear = $tagFile.Tag.Year

                # Dispose TagLib object immediately after reading metadata
                if ($tagFile) {
                    try { if ($tagFile.PSObject.Methods.Name -contains 'Dispose') { $tagFile.Dispose() } } catch { }
                    $tagFile = $null
                    try { [System.GC]::Collect() } catch { }
                }
            } else {
                # Use folder name parsing when tag reading fails
                $currentAlbumArtist = ''
                $currentAlbum = ''
                $currentYear = 0
            }

            # Detect obviously corrupted metadata and prefer folder parsing in those cases
            $metadataLooksValid = $true
            if ($currentAlbum -and $currentAlbum -match '^\d+\.\s*') {
                # Album starts with track number pattern (e.g., "01. Track Name")
                $metadataLooksValid = $false
            }
            if ($currentAlbumArtist -and $currentAlbumArtist -match '^\d+\.\s*') {
                # AlbumArtist starts with track number pattern
                $metadataLooksValid = $false
            }
            if ($currentAlbum -and $firstAudio -and $currentAlbum -eq [System.IO.Path]::GetFileNameWithoutExtension($firstAudio.Name)) {
                # Album is the same as filename (corrupted)
                $metadataLooksValid = $false
            }
            if ($currentAlbumArtist -and $firstAudio -and $currentAlbumArtist -eq [System.IO.Path]::GetFileNameWithoutExtension($firstAudio.Name)) {
                # AlbumArtist is the same as filename (corrupted)
                $metadataLooksValid = $false
            }

            # Try to parse folder name for better current values when no parameters provided or metadata looks corrupted
            $folderName = Split-Path $folder -Leaf
            $parentFolderName = Split-Path (Split-Path $folder -Parent) -Leaf
            
            # Parse folder name like "1939 - The 6 Cello Suites Disc 1" or "2002 - The Golden Age Of The Andrews Sisters"
            if ($folderName -match '^(\d{4})\s*-\s*(.+)$') {
                $parsedYear = [int]$matches[1]
                $parsedAlbum = $matches[2].Trim()
                
                # Update current values if no parameters provided OR metadata looks corrupted
                if (-not $AlbumArtist -or -not $metadataLooksValid) { $currentAlbumArtist = $parentFolderName }
                if (-not $Album -or -not $metadataLooksValid) { $currentAlbum = $parsedAlbum }
                if (-not $Year -or -not $metadataLooksValid) { $currentYear = $parsedYear }
            } elseif ($folderName -match '^(.+?)\s*-\s*(.+)$') {
                # Fallback: try to parse as "Artist - Album" 
                $possibleArtist = $matches[1].Trim()
                $possibleAlbum = $matches[2].Trim()
                
                if (-not $AlbumArtist -or -not $metadataLooksValid) { $currentAlbumArtist = $possibleArtist }
                if (-not $Album -or -not $metadataLooksValid) { $currentAlbum = $possibleAlbum }
            }

            # Initialize apply-* values from parameters (do not mutate incoming parameters)
            $applyAlbumArtist = $AlbumArtist
            $applyAlbum = $Album
            $applyYear = $Year

            # Phase 2 UX: derive consensus defaults for ambiguous cases (opt-in)
            if ($UseConsensusHints -and (-not $applyAlbum -or -not $applyYear -or -not $applyAlbumArtist)) {
                try {
                    $cons = Get-FolderTagConsensus -Path $folder -AudioExtensions $musicExtensions
                    if (-not $applyYear -and $cons.YearConsensus -and $cons.SuggestedYear) { $currentYear = [int]$cons.SuggestedYear }
                    if (-not $applyAlbum -and $cons.AlbumConsensus -and $cons.SuggestedAlbum) { $currentAlbum = $cons.SuggestedAlbum }
                    if (-not $applyAlbumArtist -and $cons.ArtistConsensus -and $cons.SuggestedArtist) { $currentAlbumArtist = $cons.SuggestedArtist }
                    if (-not $Quiet -and $Interactive) { Write-Output "Consensus defaults inferred (Year=$currentYear, Album='$currentAlbum', Artist='$currentAlbumArtist')" }
                } catch { }
            }

            # Use loaded metadata if available and (no parameters provided OR metadata looks corrupted)
            if ($loadedMetadata.ContainsKey($folder)) {
                $metadata = $loadedMetadata[$folder]
                
                # Validate loaded metadata for corruption
                $loadedMetadataLooksValid = $true
                if ($metadata.Album -and $metadata.Album -match '^\d+\.\s*') {
                    $loadedMetadataLooksValid = $false
                }
                if ($metadata.AlbumArtist -and $metadata.AlbumArtist -match '^\d+\.\s*') {
                    $loadedMetadataLooksValid = $false
                }
                
                if ($loadedMetadataLooksValid) {
                    if ((-not $applyAlbumArtist -or -not $metadataLooksValid) -and $metadata.AlbumArtist) { $applyAlbumArtist = $metadata.AlbumArtist }
                    if ((-not $applyAlbum -or -not $metadataLooksValid) -and $metadata.Album) { $applyAlbum = $metadata.Album }
                    if ((-not $applyYear -or -not $metadataLooksValid) -and $metadata.Year) { $applyYear = $metadata.Year }
                    if (-not $Quiet) { Write-Output "Using pre-loaded metadata for $folder" }
                } else {
                    if (-not $Quiet) { Write-Output "Skipping corrupted pre-loaded metadata for $folder" }
                }
            }

            $doInteractive = $false
            if ($NonInteractive.IsPresent) {
                $doInteractive = $false
            }
            elseif ($Interactive.IsPresent) { 
                $doInteractive = $true 
            }
            elseif ((-not $AlbumArtist -or -not $Album -or -not $Year) -and -not $loadedMetadata.ContainsKey($folder)) { 
                $doInteractive = $true 
            }
            elseif (-not $metadataLooksValid -and -not $AlbumArtist -and -not $Album -and -not $Year) {
                # Only force interactive mode when metadata looks corrupted AND no parameters provided
                $doInteractive = $true
                if (-not $Quiet) { Write-Output "Warning: File metadata appears corrupted, entering interactive mode for review" }
            }

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
                # Always show current values in interactive mode, even with -Quiet
                # Show current values - what will be applied if user presses enter
                if ($applyAlbumArtist) {
                    Write-Host "Current Album Artist: $applyAlbumArtist" -ForegroundColor Green
                } else {
                    Write-Host "Current Album Artist: $currentAlbumArtist" -ForegroundColor Green
                }
                
                if ($applyAlbum) {
                    Write-Host "Current Album       : $applyAlbum" -ForegroundColor Green
                } else {
                    Write-Host "Current Album       : $currentAlbum" -ForegroundColor Green
                }
                
                if ($applyYear) {
                    Write-Host "Current Year        : $applyYear" -ForegroundColor Green
                } else {
                    Write-Host "Current Year        : $currentYear" -ForegroundColor Green
                }
                
                # Flag to track if folder should be skipped
                $skipThisFolder = $false
                
                try {
                    if ($SkipMode) {
                        if ($applyAlbumArtist) {
                            Write-Host -NoNewline "Enter Album Artist ("
                            Write-Host -NoNewline "blank to accept new" -ForegroundColor Green
                            Write-Host ", '\' to postpone this folder): "
                        } else {
                            Write-Host -NoNewline "Enter Album Artist ("
                            Write-Host -NoNewline "blank to keep current" -ForegroundColor Green
                            Write-Host ", '\' to postpone this folder): "
                        }
                        $resp = Read-Host
                        if ($resp -eq '\') {
                            $skipThisFolder = $true
                        }
                    } else {
                        if ($applyAlbumArtist) {
                            Write-Host -NoNewline "Enter Album Artist ("
                            Write-Host -NoNewline "blank to accept new" -ForegroundColor Green
                            Write-Host "): "
                        } else {
                            Write-Host -NoNewline "Enter Album Artist ("
                            Write-Host -NoNewline "blank to keep current" -ForegroundColor Green
                            Write-Host "): "
                        }
                        $resp = Read-Host
                    }
                    if ($resp -ne '' -and -not $skipThisFolder) { $applyAlbumArtist = $resp }
                    
                    if (-not $skipThisFolder) {
                        if ($SkipMode) {
                            if ($applyAlbum) {
                                Write-Host -NoNewline "Enter Album ("
                                Write-Host -NoNewline "blank to accept new" -ForegroundColor Green
                                Write-Host ", '\' to postpone this folder): "
                            } else {
                                Write-Host -NoNewline "Enter Album ("
                                Write-Host -NoNewline "blank to keep current" -ForegroundColor Green
                                Write-Host ", '\' to postpone this folder): "
                            }
                            $resp = Read-Host
                            if ($resp -eq '\') {
                                $skipThisFolder = $true
                            }
                        } else {
                            if ($applyAlbum) {
                                Write-Host -NoNewline "Enter Album ("
                                Write-Host -NoNewline "blank to accept new" -ForegroundColor Green
                                Write-Host "): "
                            } else {
                                Write-Host -NoNewline "Enter Album ("
                                Write-Host -NoNewline "blank to keep current" -ForegroundColor Green
                                Write-Host "): "
                            }
                            $resp = Read-Host
                        }
                        if ($resp -ne '' -and -not $skipThisFolder) { $applyAlbum = $resp }
                    }

                    # Repeatedly prompt for Year until the user provides a blank (keep) or a valid integer.
                    if (-not $skipThisFolder) {
                        while ($true) {
                            if ($SkipMode) {
                                if ($applyYear) {
                                    Write-Host -NoNewline "Enter Year ("
                                    Write-Host -NoNewline "blank to accept new" -ForegroundColor Green
                                    Write-Host ", '\' to postpone this folder): "
                                } else {
                                    Write-Host -NoNewline "Enter Year ("
                                    Write-Host -NoNewline "blank to keep current" -ForegroundColor Green
                                    Write-Host ", '\' to postpone this folder): "
                                }
                                $resp = Read-Host
                                if ($resp -eq '\') {
                                    $skipThisFolder = $true
                                    break
                                }
                            } else {
                                if ($applyYear) {
                                    Write-Host -NoNewline "Enter Year ("
                                    Write-Host -NoNewline "blank to accept new" -ForegroundColor Green
                                    Write-Host "): "
                                } else {
                                    Write-Host -NoNewline "Enter Year ("
                                    Write-Host -NoNewline "blank to keep current" -ForegroundColor Green
                                    Write-Host "): "
                                }
                                $resp = Read-Host
                            }
                            if ($resp -eq '') {
                                # User chose to accept the new/current year
                                break
                            }
                            # Try parse integer year
                            $parsed = $null
                            if ([int]::TryParse($resp, [ref]$parsed)) {
                                $applyYear = [int]$parsed
                                break
                            }
                            else {
                                if ($applyYear) {
                                    Write-Output "Invalid year entered. Please enter a four-digit year (e.g. 2011), or press Enter to accept the new value."
                                } else {
                                    Write-Output "Invalid year entered. Please enter a four-digit year (e.g. 2011), or press Enter to keep the current value."
                                }
                                # loop continues and user will be prompted again
                            }
                        }
                    }
                    # Get sample audio files for filename preview and analysis
                    $sampleAudioFiles = Get-ChildItem -LiteralPath $folder -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $musicExtensions -contains $_.Extension.ToLower() } | Select-Object -First 3
                    if ($sampleAudioFiles) {
                        Write-Output "`nFilename preview (original vs. default renaming):"
                        foreach ($f in $sampleAudioFiles) {
                            $tag = $null
                            try {
                                # Clear TagLib cache
                                try {
                                    $cache = [TagLib.File]::Cache
                                    if ($cache) {
                                        $cache.Clear()
                                    }
                                } catch {
                                    # Ignore if cache clearing fails
                                }
                                $tag = Invoke-TagLibCreate -Path $f.FullName
                            } catch {
                            }
                            if ($tag) {
                                $track = $tag.Tag.Track
                                $title = $tag.Tag.Title
                                $trackSafe = if ($track) { '{0:D2}' -f [int]$track } else { '00' }
                                $titleSafe = [regex]::Replace($title, '[\\/:*?"<>|]', '')
                                $defaultName = "${trackSafe} - ${titleSafe}$($f.Extension)"
                                Write-Output "  Original: $($f.Name)"
                                Write-Host -NoNewline "  Default:  $defaultName" -ForegroundColor Green
                                Write-Output ""
                                
                                # Dispose TagLib object
                                try { if ($tag.PSObject.Methods.Name -contains 'Dispose') { $tag.Dispose() } } catch { }
                                $tag = $null
                            } else {
                                Write-Output "  $($f.Name) - (could not read tags)"
                                Write-Output ""
                            }
                        }
                    }

                    # Analyze filename quality if no explicit default was set
                    $filenameAnalysis = $null
                    if (-not $PSBoundParameters.ContainsKey('DefaultPreserveFilenames')) {
                        $allAudioFiles = Get-ChildItem -LiteralPath $folder -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $musicExtensions -contains $_.Extension.ToLower() }
                        if ($allAudioFiles.Count -gt 0) {
                            $filenameAnalysis = Get-FilenameQualityAnalysis -AudioFiles $allAudioFiles -MusicExtensions $musicExtensions
                            $DefaultPreserveFilenames = $filenameAnalysis.ShouldPreserveFilenames
                            
                            if (-not $Quiet) {
                                Write-Output "`nFilename Analysis:"
                                Write-Output "  Quality Score: $([math]::Round($filenameAnalysis.GoodPatternRatio * 100, 0))% good patterns"
                                Write-Output "  Track Numbers: $([math]::Round($filenameAnalysis.TrackNumberRatio * 100, 0))% have track numbers"
                                Write-Output "  Recommendation: $($filenameAnalysis.Recommendation) filenames (confidence: $([math]::Round($filenameAnalysis.Confidence * 100, 0))%)"
                                if ($filenameAnalysis.Reasons.Count -gt 0) {
                                    Write-Output "  Reason: $($filenameAnalysis.Reasons[0])"
                                }
                            }
                        }
                    }
    
                    # Prompt for filename preservation if moving (only if not explicitly set)
                    if (-not $skipThisFolder -and $Move.IsPresent -and -not $PSBoundParameters.ContainsKey('PreserveFilenames')) {
                        # Determine the default based on the parameter or analysis
                        $defaultPreserve = if ($PSBoundParameters.ContainsKey('PreserveFilenames') -or $DefaultPreserveFilenames) { 'Y' } else { 'N' }
                        $defaultSource = if ($PSBoundParameters.ContainsKey('PreserveFilenames')) { 'user-set' } 
                                       elseif ($PSBoundParameters.ContainsKey('DefaultPreserveFilenames')) { 'user-set' } 
                                       else { 'analysis' }
                        
                        if ($SkipMode) {
                            Write-Host -NoNewline "Preserve original filenames during move? (Y/N, "
                            Write-Host -NoNewline "default $defaultPreserve" -ForegroundColor Green
                            if ($defaultSource -eq 'analysis') {
                                Write-Host -NoNewline " [auto]" -ForegroundColor Cyan
                            }
                            Write-Host ", '\' to postpone this folder): "
                            $resp = Read-Host
                            if ($resp -eq '\') {
                                $skipThisFolder = $true
                            } elseif ($resp -eq 'Y' -or $resp -eq 'y') {
                                $PreserveFilenames = $true
                            } elseif ($resp -eq 'N' -or $resp -eq 'n') {
                                $PreserveFilenames = $false
                            } else {
                                # Empty response means use default
                                $PreserveFilenames = $DefaultPreserveFilenames
                            }
                        } else {
                            Write-Host -NoNewline "Preserve original filenames during move? (Y/N, "
                            Write-Host -NoNewline "default $defaultPreserve" -ForegroundColor Green
                            if ($defaultSource -eq 'analysis') {
                                Write-Host -NoNewline " [auto]" -ForegroundColor Cyan
                            }
                            Write-Host "): "
                            $resp = Read-Host
                            if ($resp -eq 'Y' -or $resp -eq 'y') {
                                $PreserveFilenames = $true
                            } elseif ($resp -eq 'N' -or $resp -eq 'n') {
                                $PreserveFilenames = $false
                            } else {
                                # Empty response means use default
                                $PreserveFilenames = $DefaultPreserveFilenames
                            }
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
            $noChanges = (($null -eq $applyAlbumArtist -or $applyAlbumArtist -eq '') -and ($null -eq $applyAlbum -or $applyAlbum -eq '') -and (-not $applyYear))
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

             # Safeguard: Check for multiple albums in the folder
            $albumsInFolder = @()
            $artistsInFolder = @()
            foreach ($af in $audioFiles) {
                try {
                    # Clear TagLib cache
                    try {
                        $cache = [TagLib.File]::Cache
                        if ($cache) {
                            $cache.Clear()
                        }
                    } catch {
                        # Ignore if cache clearing fails
                    }
                    $tag = Invoke-TagLibCreate -Path $af.FullName
                    $albumP = $tag.Tag.Album
                    $artist = ($tag.Tag.AlbumArtists.Count -gt 0) ? $tag.Tag.AlbumArtists[0] :
                             ($tag.Tag.Performers.Count -gt 0 ? $tag.Tag.Performers[0] : '')
                    
                    if ($albumP -and $albumsInFolder -notcontains $albumP) {
                        $albumsInFolder += $albumP
                    }
                    if ($artist -and $artistsInFolder -notcontains $artist) {
                        $artistsInFolder += $artist
                    }
                    
                    # Dispose TagLib object immediately
                    if ($tag) {
                        $tag.Dispose()
                        $tag = $null
                    }
                } catch {
                    # Skip files that can't be read
                }
            }
            # Do not reset the input parameter $Album; keep it intact for apply-* logic
            # Only warn if we have multiple albums AND multiple artists (indicating mixed content)
            # For compilations, we expect multiple artists but usually one album name
            if ($albumsInFolder.Count -gt 1 -and $artistsInFolder.Count -gt 1) {
                Write-Warning "Multiple albums and artists detected in folder '$folder':"
                Write-Warning "Albums: $($albumsInFolder -join ', ')"
                Write-Warning "Artists: $($artistsInFolder -join ', ')"
                if ($NonInteractive) {
                    Write-Verbose "NonInteractive mode: continuing without prompt despite mixed content."
                } else {
                    $response = Read-Host "This appears to be mixed content from different albums. Continue processing? (Y/N)"
                    if ($response -ne 'Y' -and $response -ne 'y') {
                        Write-Output "Skipping folder: $folder"
                        continue
                    }
                }
            } elseif ($albumsInFolder.Count -gt 1) {
                Write-Warning "Multiple album names detected: $($albumsInFolder -join ', ')"
                Write-Warning "This might be a compilation or incorrectly tagged files."
                if ($NonInteractive) {
                    Write-Verbose "NonInteractive mode: continuing without prompt for multiple album names."
                } else {
                    $response = Read-Host "Continue processing as a single album? (Y/N)"
                    if ($response -ne 'Y' -and $response -ne 'y') {
                        Write-Output "Skipping folder: $folder"
                        continue
                    }
                }
            } 

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
                    # Clear TagLib cache
                    try {
                        $cache = [TagLib.File]::Cache
                        if ($cache) {
                            $cache.Clear()
                        }
                    } catch {
                        # Ignore if cache clearing fails
                    }
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
                    # Dispose TagLib object
                    if ($t) { try { if ($t.PSObject.Methods.Name -contains 'Dispose') { $t.Dispose() } } catch { }; $t = $null }
                    continue
                }

            # Build a detailed action string for ShouldProcess/WhatIf
            $detailChanges = @()
            if ($applyAlbumArtist -and $applyAlbumArtist -ne '' -and $applyAlbumArtist -ne $curArtist) { $detailChanges += ("Artist '{0}'->'{1}'" -f ($curArtist ?? ''), $applyAlbumArtist) }
            if ($applyAlbum -and $applyAlbum -ne '' -and $applyAlbum -ne $curAlbum) { $detailChanges += ("Album '{0}'->'{1}'" -f ($curAlbum ?? ''), $applyAlbum) }
            if ($applyYear -and ([int]$applyYear -ne 0) -and $applyYear -ne $curYear) { $detailChanges += ("Year {0}->{1}" -f ($curYear ?? ''), $applyYear) }
            $actionDesc = if ($detailChanges.Count -gt 0) { 'Update tags: ' + ($detailChanges -join '; ') } else { 'Update music tags' }

            if ($PSCmdlet.ShouldProcess((Split-Path $f.FullName -Leaf), $actionDesc)) {
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
                
                # Dispose TagLib object
                if ($t) { try { if ($t.PSObject.Methods.Name -contains 'Dispose') { $t.Dispose() } } catch { }; $t = $null }
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
            if ($Move.IsPresent) {
                # Handle in-place reorganization when no destination folder is specified
                if (-not $DestinationFolder) {
                    $DestinationFolder = Split-Path $folder -Parent
                    if (-not $Quiet) {
                        Write-Output "No destination folder specified. Using in-place reorganization to: $DestinationFolder"
                    }
                }

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
                            # Clear TagLib cache
                            try {
                                $cache = [TagLib.File]::Cache
                                if ($cache) {
                                    $cache.Clear()
                                }
                            } catch {
                                # Ignore if cache clearing fails
                            }
                            $tmp = Invoke-TagLibCreate -Path $af.FullName
                        }
                        catch { 
                            # Skip files that can't be read during disc detection
                            continue 
                        }
                        if ($tmp) {
                            $dRaw = $tmp.Tag.Disc
                            $d = & $parseInt $dRaw
                            if ($d -and $d -ne 0) { $discNumbers += $d }
                            
                            # Dispose TagLib object
                            if ($tmp) {
                                $tmp.Dispose()
                                $tmp = $null
                            }
                        }
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
                            # Clear TagLib cache
                            try {
                                $cache = [TagLib.File]::Cache
                                if ($cache) {
                                    $cache.Clear()
                                }
                            } catch {
                                # Ignore if cache clearing fails
                            }
                            $yearSampleTag = Invoke-TagLibCreate -Path $audioFiles[0].FullName
                            if ($yearSampleTag) {
                                $yearSampleRaw = $yearSampleTag.Tag.Year
                                # Dispose TagLib object
                                $yearSampleTag.Dispose()
                                $yearSampleTag = $null
                            }
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
                        $fileTag = $null
                        try {
                            # Clear TagLib cache
                            try {
                                $cache = [TagLib.File]::Cache
                                if ($cache) {
                                    $cache.Clear()
                                }
                            } catch {
                                # Ignore if cache clearing fails
                            }
                            $fileTag = Invoke-TagLibCreate -Path $f.FullName
                        }
                        catch {
                            Write-Output "Failed to read tags for file $($f.FullName): $_"
                            # For testing purposes, create a mock tag object with default values
                            $fileTag = [PSCustomObject]@{
                                Tag = [PSCustomObject]@{
                                    AlbumArtists = @()
                                    Performers = @()
                                    Album = ''
                                    Year = 0
                                    Disc = 1
                                    Track = 1
                                    Title = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
                                }
                            }
                            Add-Member -InputObject $fileTag -MemberType ScriptMethod -Name Dispose -Value { }
                        }

                        if ($fileTag) {
                            $artistVal = $applyAlbumArtist; if (-not $artistVal) { $artistVal = ($fileTag.Tag.AlbumArtists.Count -gt 0 ? $fileTag.Tag.AlbumArtists[0] : ($fileTag.Tag.Performers.Count -gt 0 ? $fileTag.Tag.Performers[0] : 'Unknown Artist')) }
                            $albumVal = $applyAlbum; if (-not $albumVal) { $albumVal = ($fileTag.Tag.Album ? $fileTag.Tag.Album : 'Unknown Album') }
                            $yearVal = $applyYear; if (-not $yearVal) { $yearVal = ($fileTag.Tag.Year ? $fileTag.Tag.Year : '') }
                            $discRaw = $fileTag.Tag.Disc
                            $discVal = & $parseInt $discRaw
                            $trackRaw = $fileTag.Tag.Track
                            $trackVal = & $parseInt $trackRaw
                            $titleVal = $fileTag.Tag.Title

                            # Dispose TagLib object
                            if ($fileTag -and $fileTag.PSObject.Methods.Name -contains 'Dispose') {
                                $fileTag.Dispose()
                                $fileTag = $null
                            }
                        } else {
                            # Fallback values when tag reading completely fails
                            $artistVal = $applyAlbumArtist ? $applyAlbumArtist : 'Unknown Artist'
                            $albumVal = $applyAlbum ? $applyAlbum : 'Unknown Album'
                            $yearVal = $applyYear ? $applyYear : ''
                            $discVal = 1
                            $trackVal = 1
                            $titleVal = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
                        }

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

                                # Rename disc folders for consistency with audio files
                                if ($rel -match '^(?:disc|cd)\s*(\d+)') {
                                    $discNum = [int]$matches[1]
                                    $rel = "Disc $discNum"
                                }

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
                                if (-not $Quiet) { Write-Output "`nWhatIf planned ($($plannedMoves.Count)) moves for album '$albumValSample' by '$artistValSample'" }
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
