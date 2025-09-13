# Process-AnalysisLog.ps1
# Script to process saved music folder analysis logs interactively

param(
    [Parameter(Mandatory)]
    [string]$LogPath,
    
    [int]$BatchSize = 5,
    
    [string]$DestinationFolder = 'E:\_Processed',
    
    [switch]$WhatIf,
    
    [switch]$SkipInteractive
)

Write-Host "Reading analysis log: $LogPath" -ForegroundColor Cyan

# Read and parse the JSONL log file
$analysisResults = Get-Content $LogPath | ForEach-Object {
    try {
        $_ | ConvertFrom-Json
    } catch {
        $null
    }
} | Where-Object { $_ -and $_.StructureType -eq 'SimpleAlbum' }

if (-not $analysisResults) {
    Write-Warning "No SimpleAlbum folders found in the log file."
    return
}

Write-Host "Found $($analysisResults.Count) SimpleAlbum folders to process" -ForegroundColor Green

# Process in batches
$batches = [math]::Ceiling($analysisResults.Count / $BatchSize)
$currentBatch = 0

for ($i = 0; $i -lt $analysisResults.Count; $i += $BatchSize) {
    $currentBatch++
    $batch = $analysisResults[$i..([math]::Min($i + $BatchSize - 1, $analysisResults.Count - 1))]
    
    Write-Host "`n=== Batch $currentBatch of $batches ===" -ForegroundColor Yellow
    Write-Host "Processing $($batch.Count) folders..." -ForegroundColor Yellow
    
    foreach ($result in $batch) {
        Write-Host "`nProcessing: $(Split-Path $result.Path -Leaf)" -ForegroundColor Magenta
        
        if ($SkipInteractive) {
            # Non-interactive mode
            $params = @{
                DestinationFolder = $DestinationFolder
                Move = $true
                WhatIf = $WhatIf
            }
            $result.Path | Update-MusicFolderMetadata @params
        } else {
            # Interactive mode
            $params = @{
                Interactive = $true
                DestinationFolder = $DestinationFolder
                Move = $true
                WhatIf = $WhatIf
            }
            $result.Path | Update-MusicFolderMetadata @params
        }
    }
    
    if ($currentBatch -lt $batches) {
        $response = Read-Host "`nContinue with next batch? (Y/n)"
        if ($response -eq 'n' -or $response -eq 'N') {
            Write-Host "Processing stopped by user." -ForegroundColor Yellow
            break
        }
    }
}

Write-Host "`nProcessing complete!" -ForegroundColor Green