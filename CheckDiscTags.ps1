# Test script to check disc tags in compilation folder
try {
    Import-Module .\MusicFolderChecker.psm1 -Force -ErrorAction Stop
    Write-Host "Module imported successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to import module: $_" -ForegroundColor Red
    exit 1
}

$folderPath = "E:\VA -220 Greatest Old Songs [MP3-128 & 320kbps]"
$musicExtensions = @('.mp3', '.flac', '.m4a', '.ogg', '.wav', '.aac', '.ape', '.mpc')

# Get all audio files
$audioFiles = Get-ChildItem -LiteralPath $folderPath -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $musicExtensions -contains $_.Extension.ToLower() }

Write-Host "Checking disc tags in $($audioFiles.Count) audio files..." -ForegroundColor Cyan

$discValues = @()
foreach ($file in $audioFiles) {
    try {
        $tag = Invoke-TagLibCreate -Path $file.FullName
        $discRaw = $tag.Tag.Disc
        $discVal = if ($discRaw) {
            # Parse disc number like the function does
            $s = $discRaw.ToString()
            if ($s -match '^\s*(\d+)') {
                [int]$matches[1]
            } else {
                $null
            }
        } else {
            $null
        }

        if ($discVal -or $discRaw) {
            $discValues += [PSCustomObject]@{
                File = $file.Name
                DiscRaw = $discRaw
                DiscParsed = $discVal
            }
        }
    } catch {
        Write-Host "Error reading $($file.Name): $_" -ForegroundColor Red
    }
}

Write-Host "`nFiles with disc tags:" -ForegroundColor Yellow
$discValues | Format-Table -AutoSize

Write-Host "`nUnique disc values found:" -ForegroundColor Yellow
$uniqueDiscs = $discValues | Where-Object { $_.DiscParsed } | Select-Object -ExpandProperty DiscParsed -Unique | Sort-Object
$uniqueDiscs

$useDiscFolders = $false
if ($uniqueDiscs.Count -gt 1) {
    $useDiscFolders = $true
    Write-Host "Decision: Use disc folders because multiple disc numbers found" -ForegroundColor Green
} elseif ($uniqueDiscs.Count -eq 1 -and $uniqueDiscs[0] -gt 1) {
    $useDiscFolders = $true
    Write-Host "Decision: Use disc folders because disc number > 1 found" -ForegroundColor Green
} else {
    Write-Host "Decision: No disc folders needed" -ForegroundColor Green
}