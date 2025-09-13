# Test script to verify Process-AnalysisLog move functionality
# This creates a simple test scenario

param(
    [string]$TestSource = "C:\Temp\TestMusic",
    [string]$TestDest = "C:\Temp\TestDest"
)

Write-Host "=== Testing Process-AnalysisLog Move Functionality ===" -ForegroundColor Cyan

# Create test directories
if (-not (Test-Path $TestSource)) {
    New-Item -ItemType Directory -Path $TestSource -Force | Out-Null
    Write-Host "Created test source: $TestSource" -ForegroundColor Green
}

if (-not (Test-Path $TestDest)) {
    New-Item -ItemType Directory -Path $TestDest -Force | Out-Null
    Write-Host "Created test destination: $TestDest" -ForegroundColor Green
}

# Create a simple test folder with a dummy file
$testFolder = Join-Path $TestSource "TestAlbum"
if (-not (Test-Path $testFolder)) {
    New-Item -ItemType Directory -Path $testFolder -Force | Out-Null
    # Create a dummy file to simulate an audio file
    "dummy content" | Out-File -FilePath (Join-Path $testFolder "test.mp3") -Encoding UTF8
    Write-Host "Created test folder: $testFolder" -ForegroundColor Green
}

Write-Host "`nTest setup complete!" -ForegroundColor Green
Write-Host "Source: $TestSource" -ForegroundColor Yellow
Write-Host "Destination: $TestDest" -ForegroundColor Yellow

Write-Host "`nTo test the move functionality, run:" -ForegroundColor Cyan
Write-Host "Update-MusicFolderMetadata -FolderPath '$testFolder' -DestinationFolder '$TestDest' -Move -WhatIf" -ForegroundColor White

Write-Host "`nOr test with Process-AnalysisLog (after creating a log file):" -ForegroundColor Cyan
Write-Host ".\Process-AnalysisLog.ps1 -LogPath 'path\to\log.jsonl' -DestinationFolder '$TestDest' -SkipInteractive" -ForegroundColor White