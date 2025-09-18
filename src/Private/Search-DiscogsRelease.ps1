function Search-DiscogsRelease {
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

    $resp = Invoke-DiscogsRequest -Method GET -RelativePath '/database/search' -Query $q
    if (-not $resp -or -not $resp.results) { return }

    $out = @()
    foreach ($r in $resp.results) {
        $score = 0
        $reasons = New-Object System.Collections.Generic.List[string]
        if ($Artist -and $r.artist -and ($r.artist -like "*$Artist*")) { $score += 0.4; $reasons.Add('artist') }
        if ($Title -and $r.title -and ($r.title -like "*$Title*")) { $score += 0.4; $reasons.Add('title') }
        if ($Year -and $r.year -eq $Year) { $score += 0.2; $reasons.Add('year') }
        $out += [pscustomobject]@{
            Id      = $r.id
            Title   = $r.title
            Year    = $r.year
            Country = $r.country
            Label   = if ($r.label) { ($r.label -join ', ') } else { $null }
            Format  = if ($r.format) { ($r.format -join ', ') } else { $null }
            Score   = [math]::Round($score,2)
            Reasons = $reasons -join ','
        }
    }
    if ($out.Count -gt 0) {
        $sorted = $out | Sort-Object -Property Score -Descending
        foreach ($c in $sorted) { Write-Output $c }
    }
    return
}
