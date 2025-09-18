param(
    [Parameter(Mandatory)]
    [string]$SourceAlbumPath,

    [string]$OutRoot = (Join-Path -Path $PSScriptRoot -ChildPath '..\\tests\\scratch\\DiscogsTests\\10cc-SheetMusic')
)

try {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..\\MusicFolderChecker.psm1') -Force -ErrorAction Stop
} catch {
    Write-Output ("Failed to import module: {0}" -f $_)
    exit 1
}

if (-not (Test-Path -LiteralPath $SourceAlbumPath)) {
    Write-Output ("Source album not found: {0}" -f $SourceAlbumPath)
    exit 1
}

Write-Output ("Source: {0}" -f $SourceAlbumPath)
if (Test-Path -LiteralPath $OutRoot) {
    try { Remove-Item -LiteralPath $OutRoot -Recurse -Force -ErrorAction Stop } catch { Write-Output ("Failed to clean scratch: {0}" -f $_) }
}
New-Item -ItemType Directory -Path $OutRoot -Force | Out-Null
Write-Output ("Scratch root: {0}" -f (Resolve-Path -LiteralPath $OutRoot))

Copy-Item -LiteralPath $SourceAlbumPath -Destination (Join-Path -Path $OutRoot -ChildPath 'Base') -Recurse -Force
$variants = @('A-ArtistTweaked','B-YearTweaked','C-TrackTitleTweaked','D-ClearTracks','E-MixedNumbers')
foreach ($v in $variants) {
    Copy-Item -LiteralPath (Join-Path -Path $OutRoot -ChildPath 'Base') -Destination (Join-Path -Path $OutRoot -ChildPath $v) -Recurse -Force
}

function Edit-Tags {
    param(
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][scriptblock]$Edit
    )
    $audioExt = @('.mp3', '.flac', '.m4a', '.ogg', '.wav', '.aac', '.wma', '.ape', '.aiff', '.aif')
    $files = Get-ChildItem -LiteralPath $Folder -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $audioExt -contains $_.Extension.ToLower() }
    foreach ($f in $files) {
        try {
            $tf = Invoke-TagLibCreate -Path $f.FullName
            if ($tf) {
                & $Edit $tf
                $tf.Save()
                try { $tf.Dispose() } catch { }
            }
        } catch { }
    }
}

# Locate the album subfolder under each variant (assume one top-level folder under the variant root)
function Get-AlbumFolder([string]$variantRoot) {
    $sub = Get-ChildItem -LiteralPath $variantRoot -Directory | Select-Object -First 1
    if ($sub) { return $sub.FullName } else { return $variantRoot }
}

# A: change album artist
$aFolder = Get-AlbumFolder (Join-Path -Path $OutRoot -ChildPath 'A-ArtistTweaked')
Edit-Tags -Folder $aFolder -Edit { param($tf)
    $tf.Tag.AlbumArtists = [string[]]@('10ccX')
    $tf.Tag.Performers = [string[]]@()
}

# B: change year
$bFolder = Get-AlbumFolder (Join-Path -Path $OutRoot -ChildPath 'B-YearTweaked')
Edit-Tags -Folder $bFolder -Edit { param($tf) $tf.Tag.Year = 1975 }

# C: change first track title
$cFolder = Get-AlbumFolder (Join-Path -Path $OutRoot -ChildPath 'C-TrackTitleTweaked')
$firstC = Get-ChildItem -LiteralPath $cFolder -Recurse -File | Sort-Object FullName | Select-Object -First 1
if ($firstC) {
    $tf = Invoke-TagLibCreate -Path $firstC.FullName
    if ($tf) { $tf.Tag.Title = 'WRONG TITLE'; $tf.Save(); try { $tf.Dispose() } catch { } }
}

# D: clear track numbers and titles (simulate messy order)
$dFolder = Get-AlbumFolder (Join-Path -Path $OutRoot -ChildPath 'D-ClearTracks')
Edit-Tags -Folder $dFolder -Edit { param($tf) $tf.Tag.Track = 0; $tf.Tag.Title = $null }

# E: mixed numbers (set odd tracks to wrong numbers)
$eFolder = Get-AlbumFolder (Join-Path -Path $OutRoot -ChildPath 'E-MixedNumbers')
$filesE = Get-ChildItem -LiteralPath $eFolder -Recurse -File | Sort-Object FullName
$i = 0
foreach ($f in $filesE) {
    $i++
    try {
        $tf = Invoke-TagLibCreate -Path $f.FullName
        if ($tf) {
            if (($i % 2) -eq 1) { $tf.Tag.Track = 99 } else { $tf.Tag.Track = [uint32]$i }
            $tf.Save(); try { $tf.Dispose() } catch { }
        }
    } catch { }
}

$targets = Get-ChildItem -LiteralPath $OutRoot -Directory | Where-Object { $_.Name -ne 'Base' } | Select-Object -ExpandProperty FullName
foreach ($t in $targets) {
    Write-Output ("`n=== Variant: {0} ===" -f (Split-Path -Path $t -Leaf))
    # Primary WhatIf via plan/apply (uses Number matching for track applier)
    New-MfcDiscogsPlan -Path $t -IncludeTracks | Invoke-MfcDiscogsPlan -Tracks -WhatIf -Verbose

    # For order-fix scenarios, also show a direct pass forcing MatchBy Order to ignore current bad numbers
    $map = (New-MfcDiscogsPlan -Path $t -IncludeTracks | Select-Object -First 1 -ExpandProperty Map)
    if ($map) {
        Write-Output ("-- Per-track WhatIf with MatchBy=Order --")
        Set-TrackTagsFromDiscogs -Path (Get-AlbumFolder $t) -Mapping $map -MatchBy Order -WhatIf -Verbose
    }
}

Write-Output "Done."
