<#
.SYNOPSIS
Gets audio tag fields for files in a path (or a single file).

.DESCRIPTION
Enumerates audio files and returns key tag fields (AlbumArtist/Performer, Album, Title, Track, Disc, Year)
along with technical properties (Duration, Bitrate, SampleRate, Channels). Includes a Missing array that
lists any required fields that are blank or zero. Useful to quickly see what metadata exists or is missing.

.PARAMETER Path
One or more files or directories to scan. Directories will be searched for audio files. Accepts pipeline.

.PARAMETER Recurse
When scanning a directory, include subdirectories.

.PARAMETER AudioExtensions
Audio file extensions to include. Defaults to common formats.

.PARAMETER Required
Fields to consider required for the Missing list. Defaults to AlbumArtist, Album, Year, Title, Track.

.PARAMETER IncludeProperties
Also include technical properties (DurationSec, BitrateKbps, SampleRateHz, Channels) when available.

.EXAMPLE
Get-MfcTags -Path 'D:\Music\Artist\1985 - Old Ways' -Recurse | Format-Table Path,AlbumArtist,Album,Year,Title,Track,Missing

.EXAMPLE
Get-ChildItem 'D:\Music' -Directory | Get-MfcTags -Recurse -IncludeProperties | Where-Object { $_.Missing.Count -gt 0 }
#>
function Get-MfcTags {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName','LiteralPath')]
        [string[]]$Path,

        [switch]$Recurse,

        [string[]]$AudioExtensions = @('.mp3', '.flac', '.m4a', '.ogg', '.wav', '.aac', '.wma', '.ape', '.aiff', '.aif'),

        [ValidateSet('AlbumArtist','Album','Year','Title','Track','Disc')]
        [string[]]$Required = @('AlbumArtist','Album','Year','Title','Track'),

        [switch]$IncludeProperties
    )

    begin {
        function Get-AlbumArtistFromTag([object]$tag) {
            if ($null -ne $tag.AlbumArtists -and $tag.AlbumArtists.Count -gt 0) { return $tag.AlbumArtists[0] }
            if ($null -ne $tag.Performers -and $tag.Performers.Count -gt 0) { return $tag.Performers[0] }
            return $null
        }
    }

    process {
        foreach ($p in $Path) {
            if (-not (Test-Path -LiteralPath $p)) { Write-Output ("Missing: {0}" -f $p); continue }

            $targets = @()
            $attr = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
            if ($attr -and -not $attr.PSIsContainer) {
                # Single file input
                $targets = @($attr)
            } else {
                # Directory: enumerate audio files
                $targets = Get-ChildItem -LiteralPath $p -File -Recurse:$Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $AudioExtensions -contains $_.Extension.ToLower() }
            }

            foreach ($f in $targets) {
                $tf = $null
                try {
                    try { $cache = [TagLib.File]::Cache; if ($cache) { $cache.Clear() } } catch { }
                    $tf = Invoke-TagLibCreate -Path $f.FullName
                    if (-not $tf) { continue }

                    $tag = $tf.Tag
                    $props = $tf.PSObject.Properties.Name -contains 'Properties' ? $tf.Properties : $null

                    $albumArtist = Get-AlbumArtistFromTag -tag $tag
                    $performer = ($null -ne $tag.Performers -and $tag.Performers.Count -gt 0) ? $tag.Performers[0] : $null
                    $album = $tag.Album
                    $title = $tag.Title
                    $track = $tag.Track
                    $disc = $tag.Disc
                    $year = $tag.Year

                    $missing = New-Object System.Collections.Generic.List[string]
                    if ($Required -contains 'AlbumArtist' -and -not $albumArtist) { [void]$missing.Add('AlbumArtist') }
                    if ($Required -contains 'Album' -and -not $album) { [void]$missing.Add('Album') }
                    if ($Required -contains 'Year' -and (-not $year -or [int]$year -eq 0)) { [void]$missing.Add('Year') }
                    if ($Required -contains 'Title' -and -not $title) { [void]$missing.Add('Title') }
                    if ($Required -contains 'Track' -and (-not $track -or [int]$track -eq 0)) { [void]$missing.Add('Track') }
                    if ($Required -contains 'Disc' -and (-not $disc -or [int]$disc -eq 0)) { [void]$missing.Add('Disc') }

                    $obj = [pscustomobject]@{
                        Path          = $f.FullName
                        FileName      = $f.Name
                        Extension     = $f.Extension
                        AlbumArtist   = $albumArtist
                        Performer     = $performer
                        Album         = $album
                        Title         = $title
                        Track         = $track
                        Disc          = $disc
                        Year          = $year
                        Missing       = $missing
                    }

                    if ($IncludeProperties -and $props) {
                        $dur = $null; $bit = $null; $sr = $null; $ch = $null
                        try { if ($props.Duration) { $dur = [int][Math]::Round($props.Duration.TotalSeconds) } } catch { }
                        try { if ($props.PSObject.Properties.Name -contains 'AudioBitrate') { $bit = $props.AudioBitrate } } catch { }
                        try { if ($props.PSObject.Properties.Name -contains 'AudioSampleRate') { $sr = $props.AudioSampleRate } } catch { }
                        try { if ($props.PSObject.Properties.Name -contains 'AudioChannels') { $ch = $props.AudioChannels } } catch { }
                        $obj | Add-Member -NotePropertyName DurationSec  -NotePropertyValue $dur
                        $obj | Add-Member -NotePropertyName BitrateKbps  -NotePropertyValue $bit
                        $obj | Add-Member -NotePropertyName SampleRateHz -NotePropertyValue $sr
                        $obj | Add-Member -NotePropertyName Channels    -NotePropertyValue $ch
                    }

                    Write-Output $obj
                } catch {
                    Write-Output ("Failed to read tags: {0} — {1}" -f $f.FullName, $_)
                } finally {
                    if ($tf) { try { $tf.Dispose() } catch { } }
                }
            }
        }
    }
}
