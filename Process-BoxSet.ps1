# BoxSet Processing Workflow Script
# This script demonstrates the complete workflow for processing BoxSets

param(
    [Parameter(Mandatory=$true)]
    [string]$BoxSetPath,

    [Parameter(Mandatory=$true)]
    [string]$DestinationFolder,

    [switch]$WhatIf,
    [switch]$Interactive,
    [switch]$Quiet
)

Import-Module 'c:\Users\resto\Documents\PowerShell\Modules\MusicFolderChecker\MusicFolderChecker.psm1' -Force

Write-Host "🎵 BoxSet Processing Workflow" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan

# Step 1: Analyze the BoxSet structure
Write-Host "`n📊 Step 1: Analyzing BoxSet Structure" -ForegroundColor Yellow
$analysis = Get-FolderStructureAnalysis -Path $BoxSetPath

Write-Host "Structure Type: $($analysis.StructureType)" -ForegroundColor Green
Write-Host "Confidence: $($analysis.Confidence)" -ForegroundColor Green
Write-Host "Albums Detected: $($analysis.Metadata.AlbumSubfolderCount)" -ForegroundColor Green
Write-Host "Total Audio Files: $($analysis.Metadata.AlbumSubfolderAudioCount)" -ForegroundColor Green

if ($analysis.StructureType -ne "BoxSet") {
    Write-Warning "This doesn't appear to be a BoxSet. Structure type: $($analysis.StructureType)"
    Write-Host "Recommendations:" -ForegroundColor Yellow
    $analysis.Recommendations | ForEach-Object { Write-Host "  • $_" -ForegroundColor Yellow }
    return
}

# Step 2: Get all album folders within the BoxSet
Write-Host "`n📂 Step 2: Discovering Album Folders" -ForegroundColor Yellow
$albumFolders = Get-ChildItem -Path $BoxSetPath -Directory | Where-Object {
    $_.Name -match '^\d{4}\s*-\s*.+'
}

Write-Host "Found $($albumFolders.Count) album folders:" -ForegroundColor Green
$albumFolders | ForEach-Object {
    Write-Host "  • $($_.Name)" -ForegroundColor Gray
}

# Step 3: Process each album individually
Write-Host "`n🔄 Step 3: Processing Individual Albums" -ForegroundColor Yellow
$processedAlbums = @()
$skippedAlbums = @()

foreach ($albumFolder in $albumFolders) {
    Write-Host "`nProcessing: $($albumFolder.Name)" -ForegroundColor Cyan

    # Analyze individual album structure
    $albumAnalysis = Get-FolderStructureAnalysis -Path $albumFolder.FullName

    if ($albumAnalysis.StructureType -eq "MultiDiscAlbum" -or $albumAnalysis.StructureType -eq "SimpleAlbum") {
        Write-Host "  ✅ Valid album structure: $($albumAnalysis.StructureType)" -ForegroundColor Green

        # Update metadata for this album
        if (-not $WhatIf) {
            Write-Host "  📝 Updating metadata..." -ForegroundColor Yellow

            # Extract artist and album from folder name
            if ($albumFolder.Name -match '^(\d{4})\s*-\s*(.+)$') {
                $year = $matches[1]
                $albumTitle = $matches[2]

                # For BoxSets, the artist is typically the same across all albums
                # You might want to set this manually or extract from the BoxSet name
                $artistName = "Ella Fitzgerald"  # Example - adjust based on your BoxSet

                try {
                    Update-MusicFolderMetadata -FolderPath $albumFolder.FullName `
                        -AlbumArtist $artistName `
                        -Album $albumTitle `
                        -Year $year `
                        -Quiet:$Quiet `
                        -WhatIf:$WhatIf

                    $processedAlbums += $albumFolder.Name
                    Write-Host "  ✅ Metadata updated successfully" -ForegroundColor Green
                }
                catch {
                    Write-Host "  ❌ Failed to update metadata: $_" -ForegroundColor Red
                    $skippedAlbums += $albumFolder.Name
                }
            } else {
                Write-Host "  ⚠️ Could not parse folder name for metadata" -ForegroundColor Yellow
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

# Step 4: Move the entire BoxSet to destination
Write-Host "`n📦 Step 4: Moving BoxSet to Destination" -ForegroundColor Yellow

if (-not (Test-Path $DestinationFolder)) {
    New-Item -ItemType Directory -Path $DestinationFolder -Force | Out-Null
    Write-Host "Created destination folder: $DestinationFolder" -ForegroundColor Green
}

# Create the final destination path (preserve BoxSet name)
$boxSetName = Split-Path $BoxSetPath -Leaf
$finalDestination = Join-Path $DestinationFolder $boxSetName

Write-Host "Moving BoxSet to: $finalDestination" -ForegroundColor Cyan

if ($WhatIf) {
    Write-Host "🔍 WhatIf: Would move '$BoxSetPath' to '$finalDestination'" -ForegroundColor Cyan
} else {
    try {
        # Move the entire BoxSet folder
        Move-Item -Path $BoxSetPath -Destination $finalDestination -Force

        Write-Host "✅ BoxSet moved successfully to: $finalDestination" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Failed to move BoxSet: $_" -ForegroundColor Red
        return
    }
}

# Step 5: Summary
Write-Host "`n📊 Step 5: Processing Summary" -ForegroundColor Yellow
Write-Host "=================================" -ForegroundColor Yellow

Write-Host "BoxSet: $boxSetName" -ForegroundColor Cyan
Write-Host "Original Location: $BoxSetPath" -ForegroundColor Gray
Write-Host "Final Location: $finalDestination" -ForegroundColor Gray
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
Write-Host "BoxSet Structure: Preserved" -ForegroundColor Cyan

if ($WhatIf) {
    Write-Host "`n🔍 This was a WhatIf run - no actual changes were made" -ForegroundColor Cyan
    Write-Host "Run without -WhatIf to perform the actual processing" -ForegroundColor Cyan
} else {
    Write-Host "`n✅ BoxSet processing completed successfully!" -ForegroundColor Green
}