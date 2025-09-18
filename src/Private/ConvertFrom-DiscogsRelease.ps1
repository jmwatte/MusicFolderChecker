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
            # position can be like '1-01', '2-03', 'A1', 'B2'; parse disc and track when numeric
            $disc = $null; $track = $null
            $pos = [string]$t.position
            if ($pos -match '^(\d+)[-\.](\d+)$') { $disc = [int]$matches[1]; $track = [int]$matches[2] }
            elseif ($pos -match '^(\d+)$') { $track = [int]$matches[1] }

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
