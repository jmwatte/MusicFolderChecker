function Find-DiscogsRelease {
    <#
    .SYNOPSIS
    Searches Discogs releases by artist/title/year and returns ranked candidates.

    .DESCRIPTION
    Calls /database/search with provided filters and returns a sorted list of candidates
    with a simple score and reasons for matching.

    .PARAMETER Artist
    Artist filter.

    .PARAMETER Title
    Release title filter.

    .PARAMETER Year
    Year filter.

    .PARAMETER Barcode
    Barcode filter when available.

    .PARAMETER CatalogNumber
    Catalog number filter when available.

    .PARAMETER PerPage
    Number of results to retrieve (default 10).

    .OUTPUTS
    PSCustomObject with Id, Title, Year, Country, Label, Format, Score, Reasons
    #>
    [CmdletBinding()]
    param(
        [string]$Artist,
        [string]$Title,
        [int]$Year,
        [string]$Barcode,
        [string]$CatalogNumber,
        [int]$PerPage = 10
    )

    $q = @{}
    if ($Artist) { $q['artist'] = $Artist }
    if ($Title)  { $q['release_title'] = $Title }
    if ($Year)   { $q['year'] = $Year }
    if ($Barcode) { $q['barcode'] = $Barcode }
    if ($CatalogNumber) { $q['catno'] = $CatalogNumber }
    if ($q.Count -eq 0 -and $Title) { $q['q'] = $Title }

    $q['per_page'] = $PerPage
    $q['type'] = 'release'

    Write-Verbose ("Discogs search (release): artist='{0}', title='{1}', year='{2}', per_page={3}" -f $Artist, $Title, $Year, $PerPage)
    $resp = Invoke-DiscogsRequest -Method GET -RelativePath '/database/search' -Query $q
    $results = if ($resp) { $resp.results } else { $null }

    # Fallback 1: search master if no release results
    if (-not $results -or $results.Count -eq 0) {
        $qMaster = $q.Clone()
        $qMaster['type'] = 'master'
        Write-Verbose ("Discogs search fallback (master): artist='{0}', title='{1}', year='{2}'" -f $Artist, $Title, $Year)
        $resp = Invoke-DiscogsRequest -Method GET -RelativePath '/database/search' -Query $qMaster
        $results = if ($resp) { $resp.results } else { $null }
    }

    # Fallback 2: generic q search if still empty
    if (-not $results -or $results.Count -eq 0) {
        $q2 = @{}
        $qText = (($Artist ? $Artist : ''), ($Title ? $Title : '')) -join ' '
        $q2['q'] = $qText.Trim()
        if ($Year) { $q2['year'] = $Year }
        $q2['per_page'] = $PerPage
        Write-Verbose ("Discogs search fallback (q): q='{0}', year='{1}'" -f $q2['q'], $Year)
        $resp = Invoke-DiscogsRequest -Method GET -RelativePath '/database/search' -Query $q2
        $results = if ($resp) { $resp.results } else { $null }
    }

    # Fallback 3: if artist was specified and still no results, try title/year only (drop artist filter)
    if ((-not $results -or $results.Count -eq 0) -and $Title) {
        $qNoArtist = @{ 'type'='release'; 'per_page'=$PerPage; 'release_title'=$Title }
        if ($Year) { $qNoArtist['year'] = $Year }
        Write-Verbose ("Discogs search fallback (no-artist): title='{0}', year='{1}'" -f $Title, $Year)
        $resp = Invoke-DiscogsRequest -Method GET -RelativePath '/database/search' -Query $qNoArtist
        $results = if ($resp) { $resp.results } else { $null }
    }

    if (-not $results -or $results.Count -eq 0) { Write-Verbose 'Discogs search returned 0 results'; return }

    $out = New-Object System.Collections.Generic.List[object]
    foreach ($r in $results) {
        $score = 0
        $reasons = New-Object System.Collections.Generic.List[string]
        if ($Artist -and $r.artist -and ($r.artist -like "*$Artist*")) { $score += 0.4; $reasons.Add('artist') }
        if ($Title -and $r.title -and ($r.title -like "*$Title*")) { $score += 0.4; $reasons.Add('title') }
        if ($Year -and $r.year -eq $Year) { $score += 0.2; $reasons.Add('year') }
        $out.Add([pscustomobject]@{
            Id      = $r.id
            Title   = $r.title
            Year    = $r.year
            Country = $r.country
            Label   = if ($r.label) { ($r.label -join ', ') } else { $null }
            Format  = if ($r.format) { ($r.format -join ', ') } else { $null }
            Score   = [math]::Round($score,2)
            Reasons = $reasons -join ','
        }) | Out-Null
    }

    $sorted = $out | Sort-Object -Property Score -Descending
    foreach ($c in $sorted) { Write-Output $c }
}
