<#
.SYNOPSIS
Builds a Discogs-backed plan comparing local consensus to Discogs releases.

.DESCRIPTION
For each target folder, computes local consensus, searches Discogs, chooses the best candidate,
and emits proposed AlbumArtist/Album/Year with a confidence score. Streams results and can write JSONL.

.PARAMETER Path
One or more root folders to analyze.

.PARAMETER Recurse
Recurse into subfolders.

.PARAMETER Fast
Use sampling for faster local consensus.

.PARAMETER JsonlPath
Append each plan item as JSONL.

.PARAMETER ShowProgress
Show a progress bar while scanning.

.PARAMETER ExcludePath
Exclude by path wildcard.

.PARAMETER ExcludeName
Exclude by leaf name wildcard.

.EXAMPLE
New-MfcDiscogsPlan -Path 'D:\\Music' -Recurse -ShowProgress
#>
function New-MfcDiscogsPlan {
    <#
    .SYNOPSIS
    Builds a Discogs-based plan for albums by comparing local consensus with Discogs releases.

    .DESCRIPTION
    For each folder, computes local consensus (Artist/Album/Year), searches Discogs for candidates,
    fetches the best match details, maps to tags, and emits a plan item with proposed fields and a
    confidence score. Streams items as they are computed and can also append JSONL to disk.

    .PARAMETER Path
    One or more root folders to analyze.

    .PARAMETER Recurse
    Include subfolders recursively.

    .PARAMETER Fast
    Use sampling for local consensus to speed up large trees.

    .PARAMETER JsonlPath
    Append each plan item as a JSON line to this file.

    .PARAMETER ShowProgress
    Display a progress bar while scanning.

    .PARAMETER ExcludePath
    Full path patterns to exclude.

    .PARAMETER ExcludeName
    Leaf name patterns to exclude.

    .PARAMETER IncludeTracks
    When set, include mapped track list in the plan item (Map.Tracks). Useful to avoid a second Discogs call during apply.

    .OUTPUTS
    PSCustomObject with Path, ReleaseId, ProposedAlbumArtist, ProposedAlbum, ProposedYear, Confidence, Notes, Map (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]]$Path,

        [switch]$Recurse,
        [switch]$Fast,
        [string]$JsonlPath,
        [switch]$ShowProgress,
        [string[]]$ExcludePath,
        [string[]]$ExcludeName,
        [switch]$IncludeTracks
    )

    begin {
        $items = @()
    }

    process {
        foreach ($root in $Path) {
            if (-not (Test-Path -LiteralPath $root)) { Write-Output "Missing: $root"; continue }
            $targets = @($root)
            if ($Recurse) {
                $targets += (Get-ChildItem -LiteralPath $root -Directory -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
                $targets = $targets | Select-Object -Unique
            }
            if ($ExcludePath) { $targets = $targets | Where-Object { $p=$_; -not ($ExcludePath | Where-Object { $p -like $_ }).Count } }
            if ($ExcludeName) { $targets = $targets | Where-Object { $leaf = Split-Path $_ -Leaf; -not ($ExcludeName | Where-Object { $leaf -like $_ }).Count } }

            $total = $targets.Count; $index = 0
            foreach ($folder in $targets) {
                $index++
                if ($ShowProgress) { Write-Progress -Activity 'Discogs planning' -Status $folder -PercentComplete ([int](($index/$total)*100)) }

                # Local consensus
                $cons = $null
                try { $cons = Get-FolderTagConsensus -Path $folder -Fast:$Fast } catch { }
                if (-not $cons) { Write-Verbose ("No consensus for {0}; skipping" -f $folder); continue }

                $artist = $cons.SuggestedArtist
                $album  = $cons.SuggestedAlbum
                $year   = $cons.SuggestedYear
                if (-not $artist -and -not $album) { Write-Verbose ("Insufficient data (no artist/album) for {0}; skipping Discogs search" -f $folder); continue }

                # Search Discogs
                $cands = $null
                try { $cands = Find-DiscogsRelease -Artist $artist -Title $album -Year $year -PerPage 10 } catch { }
                if (-not $cands -or $cands.Count -eq 0) { Write-Verbose ("No Discogs candidates for {0} (Artist='{1}', Album='{2}', Year={3})" -f $folder, $artist, $album, $year); continue }

                $best = $cands | Select-Object -First 1
                $rel  = $null
                try { $rel = Get-DiscogsRelease -Id $best.Id } catch { }
                if (-not $rel) { Write-Verbose ("Discogs release fetch failed (Id={0}) for {1}" -f $best.Id, $folder); continue }

                $mapped = ConvertFrom-DiscogsRelease -Release $rel
                $proposedArtist = $mapped.AlbumArtist
                $proposedAlbum  = $mapped.Album
                $proposedYear   = $mapped.Year

                # Simple confidence: base from candidate score plus field agreements and track count similarity
                $conf = 0.0
                try {
                    $conf += [double]$best.Score
                    if ($artist -and $proposedArtist -and ($proposedArtist -like "*$artist*")) { $conf += 0.2 }
                    if ($album -and $proposedAlbum -and ($proposedAlbum -like "*$album*")) { $conf += 0.2 }
                    if ($year -and $proposedYear -and ($proposedYear -eq $year)) { $conf += 0.1 }
                    if ($mapped.Tracks -and $mapped.Tracks.Count -gt 0) {
                        # Compare to local track count (sample via reading few files)
                        $localCount = (Get-ChildItem -LiteralPath $folder -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
                        if ($localCount -gt 0) {
                            $ratio = [math]::Min(1.0, [double]$mapped.Tracks.Count / [double]$localCount)
                            if ($ratio -gt 0.7) { $conf += 0.1 }
                        }
                    }
                    if ($conf -gt 0.95) { $conf = 0.95 }
                } catch { }

                $item = [pscustomobject]@{
                    Path = $folder
                    ReleaseId = $best.Id
                    ProposedAlbumArtist = $proposedArtist
                    ProposedAlbum = $proposedAlbum
                    ProposedYear = $proposedYear
                    Confidence = [math]::Round($conf,2)
                    Notes = @("Discogs: $($rel.country) $($rel.year) $($rel.label -join ', ') $($rel.format -join ', ')")
                }

                if ($IncludeTracks) { $item | Add-Member -NotePropertyName Map -NotePropertyValue $mapped }

                if ($JsonlPath) { try { $item | ConvertTo-Json -Depth 5 -Compress | Add-Content -LiteralPath $JsonlPath -Encoding UTF8 } catch { } }
                Write-Output $item
                $items += $item
            }
        }
    }
}
