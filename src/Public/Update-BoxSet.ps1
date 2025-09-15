<#
.SYNOPSIS
    Intelligent BoxSet processor that automatically detects and processes music BoxSets with enhanced metadata handling.

.DESCRIPTION
    Process-BoxSet is a specialized function for handling music BoxSets (collections of multiple albums).
    It automatically detects BoxSet structures, processes each album individually with proper metadata,
    and moves the entire collection while preserving its organizational structure.

    The function combines BoxSet detection with all the powerful features of Update-MusicFolderMetadata,
    providing intelligent processing for complex music collections.

.PARAMETER FolderPath
    Path to the BoxSet folder to process. Accepts pipeline input and has 'Path' alias. Mandatory parameter.

.PARAMETER AlbumArtist
    Album artist name to apply to all audio files in the BoxSet albums.

.PARAMETER Album
    Album name to apply to all audio files (typically not used for BoxSets as each album has its own name).

.PARAMETER Year
    Release year to apply (typically not used for BoxSets as each album has its own year).

.PARAMETER Interactive
    Switch parameter. When specified, prompts user for metadata values not provided as parameters.

.PARAMETER SkipMode
    When used with -Interactive, allows entering '\' during prompts to postpone/skip complex folders for later processing.

.PARAMETER Quiet
    Switch parameter. When specified, suppresses detailed console output.

.PARAMETER DestinationFolder
    Destination directory for moving processed BoxSet. Required when using -Move.

.PARAMETER DestinationPattern
    Custom pattern for destination folder organization (not yet implemented).

.PARAMETER Move
    Switch parameter. When specified, moves the entire BoxSet to DestinationFolder after processing.

.PARAMETER LogPath
    Path to save structured JSONL log entries for audit and troubleshooting.

.PARAMETER MetadataJson
    Path to JSON file containing pre-defined metadata for folders.

.PARAMETER PreserveTrackArtists
    For compilation albums (Various Artists), preserve individual track artists instead of overwriting them with the album artist. Default is true for compilations.

.PARAMETER PreserveFilenames
    When moving files, preserve original filenames instead of renaming to standardized format.

.PARAMETER DefaultPreserveFilenames
    Set the default behavior for filename preservation in interactive mode. When $true, the default will be to preserve filenames. When $false (default), the default will be to rename files to standardized format.

.PARAMETER OutputMetadataJson
    Path to save collected metadata as JSON for future automated processing.

.PARAMETER OnConflict
    How to handle file conflicts during moves. Valid values: 'Skip', 'Overwrite', 'Merge'. Default is 'Skip'.

.PARAMETER BoxSetArtist
    Override artist name for all albums in the BoxSet (useful when BoxSet has consistent artist).

.PARAMETER ForceIndividualProcessing
    Switch parameter. When specified, processes each album individually instead of as a BoxSet unit.

.INPUTS
    System.String
    You can pipe folder paths to Process-BoxSet.

.OUTPUTS
    None directly, but writes to console, log files, and optionally moves files.

.EXAMPLE
    Process-BoxSet -FolderPath 'E:\1994 -The Complete Ella Fitzgerald Song Books' -Interactive -Move -DestinationFolder 'E:\ProcessedMusic'
    Processes the Ella Fitzgerald BoxSet interactively and moves it to the destination

.EXAMPLE
    Process-BoxSet -FolderPath 'E:\BoxSets\Various Artists - Complete Collection' -BoxSetArtist 'Various Artists' -Move -DestinationFolder 'E:\Music'
    Processes a compilation BoxSet with consistent artist override

.EXAMPLE
    Get-ChildItem 'E:\BoxSets' -Directory | Process-BoxSet -Interactive -SkipMode -WhatIf
    Processes multiple BoxSets with interactive skip capability in preview mode

.EXAMPLE
    Process-BoxSet -FolderPath 'E:\1994 -The Complete Ella Fitzgerald Song Books' -MetadataJson 'C:\Temp\boxset_metadata.json' -OutputMetadataJson 'C:\Temp\processed_metadata.json'
    Loads BoxSet metadata from file, processes the collection, and saves updated metadata

.NOTES
    Author: MusicFolderChecker Module
    Requires TagLib-Sharp.dll for audio file processing
    Automatically detects BoxSet structure using Get-FolderStructureAnalysis
    Supports WhatIf for safe preview of all operations
    Interactive mode with SkipMode uses '\' to postpone complex folders
    Automatically creates destination directories as needed
    Preserves BoxSet structure while processing individual albums
#>

function Update-BoxSet {
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
        [bool]$DefaultPreserveFilenames = $false,

        [Parameter()]
        [string]$OutputMetadataJson,

        [Parameter()]
        [ValidateSet('Skip','Overwrite','Merge')]
        [string]$OnConflict = 'Skip',

        [Parameter()]
        [string]$BoxSetArtist,

        [Parameter()]
        [switch]$ForceIndividualProcessing
    )

    begin {
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
        $processedBoxSets = @()
    }

    process {
        foreach ($boxSetPath in $FolderPath) {
            if (-not (Test-Path -LiteralPath $boxSetPath)) {
                if (-not $Quiet) { Write-Output "Skipping missing BoxSet folder: $boxSetPath" }
                continue
            }

            Write-Host "🎵 Processing BoxSet: $(Split-Path $boxSetPath -Leaf)" -ForegroundColor Cyan
            Write-Host "=================================" -ForegroundColor Cyan

            # Step 1: Analyze the BoxSet structure
            if (-not $Quiet) { Write-Host "`n📊 Analyzing BoxSet Structure..." -ForegroundColor Yellow }
            $analysis = Get-FolderStructureAnalysis -Path $boxSetPath

            Write-Host "Structure Type: $($analysis.StructureType)" -ForegroundColor Green
            Write-Host "Confidence: $($analysis.Confidence)" -ForegroundColor Green
            Write-Host "Albums Detected: $($analysis.Metadata.AlbumSubfolderCount)" -ForegroundColor Green
            Write-Host "Total Audio Files: $($analysis.Metadata.AlbumSubfolderAudioCount)" -ForegroundColor Green

            # Check if this is actually a BoxSet
            $isBoxSet = $analysis.StructureType -eq "BoxSet"
            if (-not $isBoxSet -and -not $ForceIndividualProcessing) {
                Write-Warning "This doesn't appear to be a BoxSet. Structure type: $($analysis.StructureType)"
                Write-Host "Recommendations:" -ForegroundColor Yellow
                $analysis.Recommendations | ForEach-Object { Write-Host "  • $_" -ForegroundColor Yellow }

                $response = Read-Host "Continue processing as individual albums? (Y/N)"
                if ($response -ne 'Y' -and $response -ne 'y') {
                    Write-Host "Skipping: $boxSetPath" -ForegroundColor Gray
                    continue
                }
            }

            # Step 2: Get all album folders within the BoxSet
            if (-not $Quiet) { Write-Host "`n📂 Discovering Album Folders..." -ForegroundColor Yellow }
            $albumFolders = Get-ChildItem -Path $boxSetPath -Directory | Where-Object {
                $_.Name -match '^\d{4}\s*-\s*.+'
            }

            Write-Host "Found $($albumFolders.Count) album folders:" -ForegroundColor Green
            $albumFolders | ForEach-Object {
                Write-Host "  • $($_.Name)" -ForegroundColor Gray
            }

            # Step 3: Process each album individually
            if (-not $Quiet) { Write-Host "`n🔄 Processing Individual Albums..." -ForegroundColor Yellow }
            $processedAlbums = @()
            $skippedAlbums = @()

            foreach ($albumFolder in $albumFolders) {
                Write-Host "`nProcessing Album: $($albumFolder.Name)" -ForegroundColor Cyan

                # Analyze individual album structure
                $albumAnalysis = Get-FolderStructureAnalysis -Path $albumFolder.FullName

                if ($albumAnalysis.StructureType -eq "MultiDiscAlbum" -or $albumAnalysis.StructureType -eq "SimpleAlbum" -or $ForceIndividualProcessing) {
                    Write-Host "  ✅ Valid album structure: $($albumAnalysis.StructureType)" -ForegroundColor Green

                    # Extract artist and album from folder name
                    $applyAlbumArtist = $AlbumArtist
                    $applyAlbum = $Album
                    $applyYear = $Year

                    if ($albumFolder.Name -match '^(\d{4})\s*-\s*(.+)$') {
                        $extractedYear = $matches[1]
                        $extractedAlbumTitle = $matches[2]

                        # Use BoxSetArtist override if provided, otherwise use extracted or provided values
                        if ($BoxSetArtist) {
                            $applyAlbumArtist = $BoxSetArtist
                        } elseif (-not $applyAlbumArtist) {
                            $applyAlbumArtist = $AlbumArtist  # Use provided value or keep as-is
                        }

                        if (-not $applyAlbum) {
                            $applyAlbum = $extractedAlbumTitle
                        }

                        if (-not $applyYear) {
                            $applyYear = [int]$extractedYear
                        }

                        Write-Host "  📝 Extracted metadata:" -ForegroundColor Blue
                        Write-Host "    Artist: $applyAlbumArtist" -ForegroundColor Blue
                        Write-Host "    Album: $applyAlbum" -ForegroundColor Blue
                        Write-Host "    Year: $applyYear" -ForegroundColor Blue
                    } else {
                        Write-Host "  ⚠️ Could not parse folder name for metadata" -ForegroundColor Yellow
                        $skippedAlbums += $albumFolder.Name
                        continue
                    }

                    # Update metadata for this album using Update-MusicFolderMetadata
                    if (-not $WhatIfPreference) {
                        Write-Host "  📝 Updating metadata..." -ForegroundColor Yellow

                        try {
                            Update-MusicFolderMetadata -FolderPath $albumFolder.FullName `
                                -AlbumArtist $applyAlbumArtist `
                                -Album $applyAlbum `
                                -Year $applyYear `
                                -Interactive:$Interactive `
                                -SkipMode:$SkipMode `
                                -Quiet:$Quiet `
                                -LogPath $LogPath `
                                -MetadataJson $MetadataJson `
                                -PreserveTrackArtists:$PreserveTrackArtists `
                                -PreserveFilenames:$PreserveFilenames `
                                -DefaultPreserveFilenames $DefaultPreserveFilenames `
                                -OutputMetadataJson $OutputMetadataJson `
                                -OnConflict $OnConflict `
                                -WhatIf:$WhatIfPreference

                            $processedAlbums += $albumFolder.Name
                            Write-Host "  ✅ Metadata updated successfully" -ForegroundColor Green
                        }
                        catch {
                            Write-Host "  ❌ Failed to update metadata: $_" -ForegroundColor Red
                            $skippedAlbums += $albumFolder.Name
                        }
                    } else {
                        Write-Host "  🔍 WhatIf: Would update metadata for $($albumFolder.Name)" -ForegroundColor Cyan
                        $processedAlbums += $albumFolder.Name
                    }
                } else {
                    Write-Host "  ⚠️ Skipping album with structure: $($albumAnalysis.StructureType)" -ForegroundColor Yellow
                    Write-Host "    Reason: $($albumAnalysis.Details -join '; ')" -ForegroundColor Gray
                    $skippedAlbums += $albumFolder.Name
                }
            }

            # Step 4: Move the entire BoxSet to destination (only if Move is requested)
            if ($Move.IsPresent -and $DestinationFolder) {
                if (-not $Quiet) { Write-Host "`n📦 Moving BoxSet to Destination..." -ForegroundColor Yellow }

                if (-not (Test-Path $DestinationFolder)) {
                    New-Item -ItemType Directory -Path $DestinationFolder -Force | Out-Null
                    if (-not $Quiet) { Write-Host "Created destination folder: $DestinationFolder" -ForegroundColor Green }
                }

                # Determine BoxSet artist for folder structure
                $boxSetArtist = if ($BoxSetArtist) {
                    $BoxSetArtist
                } elseif ($AlbumArtist) {
                    $AlbumArtist
                } else {
                    # Try to extract from first album folder name
                    $firstAlbum = $albumFolders | Select-Object -First 1
                    if ($firstAlbum -and $firstAlbum.Name -match '^(\d{4})\s*-\s*(.+?)\s*-\s*(.+)') {
                        $matches[2]  # Artist from "Year - Artist - Album" pattern
                    } elseif ($firstAlbum -and $firstAlbum.Name -match '^(\d{4})\s*-\s*(.+)') {
                        "Unknown Artist"  # Fallback if we can't parse artist
                    } else {
                        "Unknown Artist"
                    }
                }

                # Create the final destination path with artist subfolder
                $boxSetName = Split-Path $boxSetPath -Leaf
                $artistFolder = Join-Path $DestinationFolder $boxSetArtist
                $finalDestination = Join-Path $artistFolder $boxSetName

                # Ensure artist folder exists
                if (-not (Test-Path $artistFolder)) {
                    New-Item -ItemType Directory -Path $artistFolder -Force | Out-Null
                    if (-not $Quiet) { Write-Host "Created artist folder: $artistFolder" -ForegroundColor Green }
                }

                if (-not $Quiet) { Write-Host "Moving BoxSet to: $finalDestination" -ForegroundColor Cyan }

                if ($WhatIfPreference) {
                    Write-Host "🔍 WhatIf: Would move '$boxSetPath' to '$finalDestination'" -ForegroundColor Cyan
                } else {
                    try {
                        # Move the entire BoxSet folder
                        Move-Item -Path $boxSetPath -Destination $finalDestination -Force

                        Write-Host "✅ BoxSet moved successfully to: $finalDestination" -ForegroundColor Green
                        $processedBoxSets += @{
                            Name = $boxSetName
                            OriginalPath = $boxSetPath
                            FinalPath = $finalDestination
                            AlbumsProcessed = $processedAlbums.Count
                            AlbumsSkipped = $skippedAlbums.Count
                        }
                    }
                    catch {
                        Write-Host "❌ Failed to move BoxSet: $_" -ForegroundColor Red
                        continue
                    }
                }
            } elseif ($Move.IsPresent -and -not $DestinationFolder) {
                Write-Warning "Move requested but no DestinationFolder specified. Skipping move operation."
            }

            # Step 5: Summary for this BoxSet
            if (-not $Quiet) {
                Write-Host "`n📊 BoxSet Processing Summary" -ForegroundColor Yellow
                Write-Host "=================================" -ForegroundColor Yellow

                Write-Host "BoxSet: $boxSetName" -ForegroundColor Cyan
                Write-Host "Original Location: $boxSetPath" -ForegroundColor Gray
                if ($Move.IsPresent -and $DestinationFolder) {
                    Write-Host "Final Location: $finalDestination" -ForegroundColor Gray
                }
                Write-Host ""
                Write-Host "Albums Processed: $($processedAlbums.Count)" -ForegroundColor Green
                if ($processedAlbums.Count -gt 0) {
                    Write-Host "  ✅ Successfully processed:" -ForegroundColor Green
                    $processedAlbums | ForEach-Object { Write-Host "    • $_" -ForegroundColor Green }
                }

                if ($skippedAlbums.Count -gt 0) {
                    Write-Host "  ⚠️ Skipped albums: $($skippedAlbums.Count)" -ForegroundColor Yellow
                    Write-Host "  📋 Skipped:" -ForegroundColor Yellow
                    $skippedAlbums | ForEach-Object { Write-Host "    • $_" -ForegroundColor Yellow }
                }

                Write-Host ""
                Write-Host "Total Audio Files: $($analysis.Metadata.AlbumSubfolderAudioCount)" -ForegroundColor Cyan
                Write-Host "BoxSet Structure: $(if ($isBoxSet) { 'Preserved' } else { 'Individual Processing' })" -ForegroundColor Cyan

                if ($WhatIfPreference) {
                    Write-Host "`n🔍 This was a WhatIf run - no actual changes were made" -ForegroundColor Cyan
                    Write-Host "Run without -WhatIf to perform the actual processing" -ForegroundColor Cyan
                } else {
                    Write-Host "`n✅ BoxSet processing completed successfully!" -ForegroundColor Green
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

        # Overall summary if multiple BoxSets were processed
        if ($processedBoxSets.Count -gt 1 -and -not $Quiet) {
            Write-Host "`n🎵 Overall Processing Summary" -ForegroundColor Cyan
            Write-Host "============================" -ForegroundColor Cyan
            Write-Host "Total BoxSets Processed: $($processedBoxSets.Count)" -ForegroundColor Green

            $totalAlbums = ($processedBoxSets | Measure-Object -Property AlbumsProcessed -Sum).Sum
            $totalSkipped = ($processedBoxSets | Measure-Object -Property AlbumsSkipped -Sum).Sum

            Write-Host "Total Albums Processed: $totalAlbums" -ForegroundColor Green
            Write-Host "Total Albums Skipped: $totalSkipped" -ForegroundColor Yellow

            Write-Host "`nProcessed BoxSets:" -ForegroundColor Cyan
            foreach ($boxSet in $processedBoxSets) {
                Write-Host "  • $($boxSet.Name) ($($boxSet.AlbumsProcessed) albums)" -ForegroundColor Green
            }
        }
    }
}