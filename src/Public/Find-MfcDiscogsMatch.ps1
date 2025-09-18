<#
.SYNOPSIS
Finds Discogs release candidates for a local album folder.

.DESCRIPTION
Computes local Artist/Album/Year consensus, queries Discogs for matching releases, and returns
ranked candidates. Optionally opens the best match in a browser.

.PARAMETER Path
Album folder to analyze.

.PARAMETER PerPage
Number of candidates to return.

.PARAMETER OpenInBrowser
Open the top candidate on discogs.com.

.PARAMETER Artist
Override search artist.

.PARAMETER Album
Override search album title.

.PARAMETER Year
Override search year.

.EXAMPLE
Find-MfcDiscogsMatch -Path 'D:\\Artist\\1997 - OK Computer' -OpenInBrowser
#>
function Find-MfcDiscogsMatch {
    <#
    .SYNOPSIS
    Finds top Discogs release candidates for a local album folder.

    .DESCRIPTION
    Computes local consensus (Artist/Album/Year) for the folder, queries Discogs releases,
    and returns ranked candidates with a simple score and reasons. Optionally opens the best
    match in the default browser.

    .PARAMETER Path
    Album folder to analyze and match.

    .PARAMETER PerPage
    Number of Discogs candidates to fetch (default 10).

    .PARAMETER OpenInBrowser
    Open the best match (top candidate) in the default browser.

    .PARAMETER Artist
    Override artist used for search (otherwise inferred from local consensus).

    .PARAMETER Album
    Override album title used for search (otherwise inferred from local consensus).

    .PARAMETER Year
    Override year used for search (otherwise inferred from local consensus).

    .EXAMPLE
    Find-MfcDiscogsMatch -Path 'D:\Artist\1997 - OK Computer' -PerPage 15 -OpenInBrowser

    .NOTES
    Requires a Discogs personal access token in DISCOGS_TOKEN for best results and higher rate limits.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]$Path,

        [int]$PerPage = 10,

        [switch]$OpenInBrowser,

        [string]$Artist,
        [string]$Album,
        [int]$Year
    )

    if (-not (Test-Path -LiteralPath $Path)) { Write-Output ("Missing: {0}" -f $Path); return }

    $cons = $null
    try { $cons = Get-FolderTagConsensus -Path $Path -Fast } catch { }
    # Seed from consensus unless overridden
    $artist = if ($PSBoundParameters.ContainsKey('Artist')) { $Artist } else { if ($cons) { $cons.SuggestedArtist } else { $null } }
    $title  = if ($PSBoundParameters.ContainsKey('Album'))  { $Album }  else { if ($cons) { $cons.SuggestedAlbum } else { $null } }
    $year   = if ($PSBoundParameters.ContainsKey('Year'))   { $Year }   else { if ($cons) { $cons.SuggestedYear } else { $null } }

    if (-not $artist -and -not $title) {
        Write-Output ("Insufficient data to search Discogs for: {0}. Provide -Artist and/or -Album." -f $Path)
        return
    }

    $cands = $null
    try { $cands = Find-DiscogsRelease -Artist $artist -Title $title -Year $year -PerPage $PerPage } catch { }
    if (-not $cands -or $cands.Count -eq 0) {
        # If requested, open a general Discogs search in browser so user can refine manually
        if ($OpenInBrowser) {
            $qArtist = if ($artist) { [System.Uri]::EscapeDataString($artist) } else { '' }
            $qTitle  = if ($title)  { [System.Uri]::EscapeDataString($title) }  else { '' }
            $qCombo  = [System.Uri]::EscapeDataString(((($artist ? $artist : ''), ($title ? $title : '')) -join ' ').Trim())
            $url = "https://www.discogs.com/search/?type=release"
            if ($qArtist) { $url += ("&artist={0}" -f $qArtist) }
            if ($qTitle)  { $url += ("&release_title={0}" -f $qTitle) }
            if ($year)    { $url += ("&year={0}" -f $year) }
            if ($qCombo)  { $url += ("&q={0}" -f $qCombo) }
            Write-Output ("Opening Discogs search: {0}" -f $url)
            try { Start-Process -FilePath $url | Out-Null } catch { Write-Output ("Failed to open browser: {0}" -f $_.Exception.Message) }
        }
        return
    }

    if ($OpenInBrowser) {
        $best = $cands | Select-Object -First 1
        if ($best -and $best.Id) {
            $link = "https://www.discogs.com/release/{0}" -f $best.Id
            Write-Output ("Opening: {0}" -f $link)
            try { Start-Process -FilePath $link | Out-Null } catch { Write-Output ("Failed to open browser: {0}" -f $_.Exception.Message) }
        } else {
            Write-Output "No candidate with an Id to open."
        }
    }

    $cands
}
