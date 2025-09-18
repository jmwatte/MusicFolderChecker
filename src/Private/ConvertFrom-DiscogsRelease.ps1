function ConvertFrom-DiscogsRelease {
    <#
    .SYNOPSIS
    Converts a Discogs release object to tag-friendly fields and per-track mappings.

    .DESCRIPTION
    Produces AlbumArtist, Album, Year and a Tracks array with Disc/TrackNumber, Title, Duration.

    .PARAMETER Release
    Discogs release object as returned by Get-DiscogsRelease.

    .OUTPUTS
    PSCustomObject with AlbumArtist, Album, Year, Tracks
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Release
    )

    if (-not $Release) { return $null }
    $artist = $null
    try {
        if ($Release.artists -and $Release.artists.Count -gt 0) { $artist = $Release.artists[0].name }
        elseif ($Release.artist -and $Release.artist.Count -gt 0) { $artist = $Release.artist[0].name }
    } catch { }
    if (-not $artist -and $Release.title -and $Release.title -match '^(.*)\s+-\s+(.*)$') { $artist = $matches[1] }

    $album = $Release.title
    $year = if ($Release.year) { [int]$Release.year } else { $null }

    $tracks = @()
    if ($Release.tracklist) {
        foreach ($t in $Release.tracklist) {
            # position variants observed on Discogs:
            # - Numeric with disc separator: '1-01', '2.03', 'CD1-01'
            # - Pure numeric: '05'
            # - Lettered sides: 'A1', 'B2', 'C3' (vinyl)
            # We parse conservatively: derive Disc/Track when we can; otherwise leave Disc=$null and Track from sequence/index
            $disc = $null; $track = $null
            $pos = ([string]$t.position).Trim()

            # CD/Disc prefixes like 'CD1-01', 'Disc2-03', or plain '1-01'/'2.03'
            if ($pos -match '^(?:CD|Disc|D|LP)?\s*(\d+)[-\.](\d+)$') {
                $disc = [int]$matches[1]
                $track = [int]$matches[2]
            }
            # Lettered sides like 'A1', 'B2', 'C3' (map side letters to sequential discs to preserve ordering)
            elseif ($pos -match '^([A-Z])(\d+)$') {
                $side = [char]$matches[1]
                $sideIndex = ([int][char]::ToUpperInvariant($side)) - ([int][char]'A') + 1
                # Treat each side as its own Disc to avoid duplicate track numbers within one disc
                $disc = $sideIndex
                $track = [int]$matches[2]
            }
            # Pure numeric (no disc info)
            elseif ($pos -match '^(\d+)$') {
                $track = [int]$matches[1]
            }

            $dur = $null
            if ($t.duration -and $t.duration -match '^(\d{1,2}):(\d{2})$') {
                $dur = ([int]$matches[1]) * 60 + [int]$matches[2]
            }

            $tracks += [pscustomobject]@{
                Disc   = $disc
                Track  = $track
                Title  = $t.title
                Seconds= $dur
            }
        }
    }

    [pscustomobject]@{
        AlbumArtist = $artist
        Album       = $album
        Year        = $year
        Tracks      = $tracks
    }
}
