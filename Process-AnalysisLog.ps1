# Process-AnalysisLog.ps1
# Script to process saved music folder analysis logs interactively
#
# USAGE EXAMPLES:
#   .\Process-AnalysisLog.ps1 -LogPath 'C:\Logs\analysis.jsonl' -BatchSize 10
#   .\Process-AnalysisLog.ps1 -LogPath 'C:\Logs\analysis.jsonl' -SkipInteractive -WhatIf
#   .\Process-AnalysisLog.ps1 -LogPath 'C:\Logs\analysis.jsonl' -SkipMode -WhatIf
#
# PARAMETERS:
#   -LogPath: Path to the JSONL analysis log file (required)
#   -BatchSize: Number of folders to process per batch (default: 5)
#   -DestinationFolder: Where to move processed folders (default: 'E:\_Processed')
#   -WhatIf: Preview mode - shows what would be done without making changes
#   -SkipInteractive: Skip interactive prompts, process all folders automatically
#   -SkipMode: Enable skip/postpone functionality in interactive mode (type '\' to skip)

param(
    [Parameter(Mandatory)]
    [string]$LogPath,
    
    [int]$BatchSize = 5,
    
    [string]$DestinationFolder = 'E:\_Processed',
    
    [switch]$WhatIf,
    
    [switch]$SkipInteractive,
    
    [switch]$SkipMode
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
        
        if ($SkipMode) {
            Write-Host "  SkipMode enabled: Type '\' during prompts to postpone complex folders" -ForegroundColor Cyan
        }
        
        if ($SkipInteractive) {
            # Non-interactive mode
            $params = @{}
            if ($DestinationFolder) { $params.DestinationFolder = $DestinationFolder }
            if ($WhatIf) { $params.WhatIf = $WhatIf }
            # Add Move switch properly
            $result.Path | Update-MusicFolderMetadata @params -Move
        } else {
            # Interactive mode
            $params = @{}
            if ($DestinationFolder) { $params.DestinationFolder = $DestinationFolder }
            if ($WhatIf) { $params.WhatIf = $WhatIf }
            # Add SkipMode if specified
            if ($SkipMode) {
                $params.SkipMode = $true
            }
            # Add Move switch and Interactive switch properly
            $result.Path | Update-MusicFolderMetadata @params -Move -Interactive
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