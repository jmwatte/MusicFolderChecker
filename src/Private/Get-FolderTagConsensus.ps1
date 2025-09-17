function Get-FolderTagConsensus {
    <#
    .SYNOPSIS
        Computes consensus metadata (Year/Album/Artist) across audio files in a folder tree.

    .DESCRIPTION
        Scans a folder recursively for audio files and aggregates tag values to determine
        the most common Year, Album, and AlbumArtist/Performer. Returns ratios for each
        field and a suggested normalized folder name (e.g., "YYYY - Album"). When tags are
        inconsistent, falls back to existing folder name parts.

    .PARAMETER Path
        The folder to analyze. The folder is scanned recursively to include disc subfolders.

    .PARAMETER AudioExtensions
        Array of audio file extensions to consider. Defaults to common formats.

    .PARAMETER MinFiles
        Minimum number of audio files required to compute a meaningful consensus. Default 3.

    .PARAMETER YearThreshold
        Ratio threshold (0-1) to consider Year values "consistent enough". Default 0.6.

    .PARAMETER AlbumThreshold
        Ratio threshold (0-1) to consider Album values "consistent enough". Default 0.6.

    .PARAMETER ArtistThreshold
        Ratio threshold (0-1) to consider Artist values "consistent enough". Default 0.6.

    .OUTPUTS
        PSCustomObject with fields: Path, FileCount, YearTopValue, YearTopRatio, YearConsensus,
        AlbumTopValue, AlbumTopRatio, AlbumConsensus, ArtistTopValue, ArtistTopRatio, ArtistConsensus,
        SuggestedYear, SuggestedAlbum, SuggestedArtist, SuggestedFolderName, Confidence, Details
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string[]]$AudioExtensions = @('.mp3', '.flac', '.m4a', '.ogg', '.wav', '.aac', '.wma', '.ape', '.dsd', '.aiff', '.aif'),

        [int]$MinFiles = 3,
        [double]$YearThreshold = 0.6,
        [double]$AlbumThreshold = 0.6,
        [double]$ArtistThreshold = 0.6
    )

    # Gather audio files recursively
    $audioFiles = @()
    foreach ($ext in $AudioExtensions) {
        $audioFiles += Get-ChildItem -LiteralPath $Path -File -Filter "*${ext}" -Recurse -ErrorAction SilentlyContinue
    }

    $fileCount = $audioFiles.Count
    if ($fileCount -lt $MinFiles) {
        return [PSCustomObject]@{
            Path = $Path
            FileCount = $fileCount
            YearTopValue = $null
            YearTopRatio = 0.0
            YearConsensus = $false
            AlbumTopValue = $null
            AlbumTopRatio = 0.0
            AlbumConsensus = $false
            ArtistTopValue = $null
            ArtistTopRatio = 0.0
            ArtistConsensus = $false
            SuggestedYear = $null
            SuggestedAlbum = $null
            SuggestedArtist = $null
            SuggestedFolderName = Split-Path $Path -Leaf
            Confidence = 0.0
            Details = @("Too few audio files for consensus")
        }
    }

    # Counters
    $yearCounts = @{}
    $albumCounts = @{}
    $artistCounts = @{}
    $validYear = 0
    $validAlbum = 0
    $validArtist = 0

    foreach ($f in $audioFiles) {
        $tagFile = $null
        try {
            # Best effort to clear TagLib cache to avoid stale references
            try { $cache = [TagLib.File]::Cache; if ($cache) { $cache.Clear() } } catch { }
            $tagFile = Invoke-TagLibCreate -Path $f.FullName
        } catch {
            $tagFile = $null
        }
        if (-not $tagFile) { continue }

        try {
            # Year
            $y = $tagFile.Tag.Year
            if ($y -and [int]$y -gt 0) {
                $validYear++
                $keyY = [string][int]$y
                if (-not $yearCounts.ContainsKey($keyY)) { $yearCounts[$keyY] = 0 }
                $yearCounts[$keyY]++
            }

            # Album (normalize by removing disc suffixes like 'Disc 1', 'CD2', 'Part 1', trailing brackets)
            $alb = $tagFile.Tag.Album
            if ($alb) {
                $albNorm = $alb -replace '(?i)\s*(?:disc|cd|part)\s*\d+.*$', ''
                $albNorm = $albNorm -replace '\s*[\(\[]?(?:remaster(?:ed)?|deluxe|expanded|bonus).*[\)\]]?\s*$', ''
                $albNorm = ($albNorm).Trim()
                if ($albNorm -ne '') {
                    $validAlbum++
                    if (-not $albumCounts.ContainsKey($albNorm)) { $albumCounts[$albNorm] = 0 }
                    $albumCounts[$albNorm]++
                }
            }

            # Artist: prefer AlbumArtist then Performer
            $artist = $null
            if ($null -ne $tagFile.Tag.AlbumArtists -and $tagFile.Tag.AlbumArtists.Count -gt 0) {
                $artist = $tagFile.Tag.AlbumArtists[0]
            } elseif ($null -ne $tagFile.Tag.Performers -and $tagFile.Tag.Performers.Count -gt 0) {
                $artist = $tagFile.Tag.Performers[0]
            }
            if ($artist) {
                $validArtist++
                if (-not $artistCounts.ContainsKey($artist)) { $artistCounts[$artist] = 0 }
                $artistCounts[$artist]++
            }
        } finally {
            $tagFile.Dispose()
            $tagFile = $null
        }
    }

    function Get-Top {
        param(
            [hashtable]$Counts, [int]$Valid
        )
        if ($Counts.Count -eq 0 -or $Valid -eq 0) {
            return [PSCustomObject]@{ Key = $null; Ratio = 0.0; Value = 0 }
        }
        $entry = $Counts.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 1
        $ratio = if ($Valid -gt 0) { [double]$entry.Value / [double]$Valid } else { 0.0 }
        return [PSCustomObject]@{ Key = $entry.Key; Ratio = [double]$ratio; Value = [int]$entry.Value }
    }

    $yt = Get-Top -Counts $yearCounts -Valid $validYear
    $at = Get-Top -Counts $albumCounts -Valid $validAlbum
    $art = Get-Top -Counts $artistCounts -Valid $validArtist
    $yearTop = $yt.Key; $yearRatio = $yt.Ratio
    $albumTop = $at.Key; $albumRatio = $at.Ratio
    $artistTop = $art.Key; $artistRatio = $art.Ratio

    $hasYearTop = ($validYear -gt 0 -and $yearCounts.Count -gt 0)
    $hasAlbumTop = ($validAlbum -gt 0 -and $albumCounts.Count -gt 0)
    $hasArtistTop = ($validArtist -gt 0 -and $artistCounts.Count -gt 0)
    $yearConsensus = ($hasYearTop -and $yearRatio -ge $YearThreshold)
    $albumConsensus = ($hasAlbumTop -and $albumRatio -ge $AlbumThreshold)
    $artistConsensus = ($hasArtistTop -and $artistRatio -ge $ArtistThreshold)

    # Fallbacks from folder name when needed
    $folderName = Split-Path $Path -Leaf
    $parsedYear = $null
    $parsedAlbum = $null
    if ($folderName -match '^(\d{4})\s*-\s*(.+)$') {
        $parsedYear = [int]$matches[1]
        $parsedAlbum = $matches[2].Trim()
    }

    $suggestedYear = if ($yearConsensus) { [int]$yearTop } elseif ($parsedYear) { $parsedYear } else { $null }
    $suggestedAlbum = if ($albumConsensus) { $albumTop } elseif ($parsedAlbum) { $parsedAlbum } else { $folderName }
    $suggestedArtist = if ($artistConsensus) { $artistTop } else { $null }

    # Suggested folder name format
    $suggestedFolderName = if ($suggestedYear) { "${suggestedYear} - ${suggestedAlbum}" } else { $suggestedAlbum }

    # Confidence: simple average of available consensuses weighted by valid counts
    $signals = @()
    if ($validYear -gt 0) { $signals += $yearRatio }
    if ($validAlbum -gt 0) { $signals += $albumRatio }
    if ($validArtist -gt 0) { $signals += $artistRatio }
    $confidence = if ($signals.Count -gt 0) { [math]::Min(0.95, ($signals | Measure-Object -Average).Average) } else { 0.0 }

    $yearTopValueOut = $null
    if ($yearTop -ne $null) {
        try { $yearTopValueOut = [int]$yearTop } catch { $yearTopValueOut = $null }
    }

    return [PSCustomObject]@{
        Path = $Path
        FileCount = $fileCount
        YearTopValue = $yearTopValueOut
        YearTopRatio = [math]::Round($yearRatio, 3)
        YearConsensus = $yearConsensus
        AlbumTopValue = $albumTop
        AlbumTopRatio = [math]::Round($albumRatio, 3)
        AlbumConsensus = $albumConsensus
        ArtistTopValue = $artistTop
        ArtistTopRatio = [math]::Round($artistRatio, 3)
        ArtistConsensus = $artistConsensus
        SuggestedYear = $suggestedYear
        SuggestedAlbum = $suggestedAlbum
        SuggestedArtist = $suggestedArtist
        SuggestedFolderName = $suggestedFolderName
        Confidence = [math]::Round($confidence, 3)
        Details = @()
    }
}
