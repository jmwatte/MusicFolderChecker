<#
.SYNOPSIS
Updates per-track tags (Title, Track, Disc) from a Discogs release for a local album folder.

.DESCRIPTION
Fetches a Discogs release by Id, converts it to a tag-friendly mapping, and applies per-track
metadata to files in the specified folder. Matching is primarily by disc and track number; when
numbers are missing, files are matched in order. Honors -WhatIf and -Verbose.

.PARAMETER Path
Album folder path containing the audio files to update.

.PARAMETER ReleaseId
Discogs release id to map from.

.PARAMETER MatchBy
Match strategy. 'Number' uses Disc/Track numbers when available; otherwise order by filename.

.PARAMETER LogPath
Optional structured JSONL log path.

    .PARAMETER ValidateLength
    When set, compares local file duration to Discogs track length and logs mismatches.

    .PARAMETER LengthToleranceSec
    Allowed absolute difference in seconds when validating length. Default 2 seconds.

    .PARAMETER StrictLength
    When used with -ValidateLength, fail (throw) if any file length differs beyond tolerance.

    .EXAMPLE
Set-TrackTagsFromDiscogs -Path 'D:\\_CorrectedMusic\\Abba\\1976 - Arrival' -ReleaseId 10988576 -WhatIf -Verbose
#>
function Set-TrackTagsFromDiscogs {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]$Path,

        [Parameter(Mandatory)]
        [int]$ReleaseId,

        [ValidateSet('Number','Order')]
        [string]$MatchBy = 'Number',

        [string]$LogPath,

        [switch]$ValidateLength,
        [int]$LengthToleranceSec = 2,
        [switch]$StrictLength
    )

    begin {
        $audioExtensions = @('.mp3', '.flac', '.m4a', '.ogg', '.wav', '.aac', '.wma', '.ape', '.aiff', '.aif')
        function Get-DiscFromPath {
            param([string]$p)
            if (-not $p) { return $null }
            $name = Split-Path $p -Leaf
            if ($name -match '(?i)^(?:disc|cd)\s*(\d+)') { return [int]$matches[1] }
            return $null
        }
    }

    process {
        if (-not (Test-Path -LiteralPath $Path)) { Write-Output ("Missing: {0}" -f $Path); return }

        $rel = $null
        try { $rel = Get-DiscogsRelease -Id $ReleaseId } catch { Write-Output ("Failed to fetch Discogs release {0}: {1}" -f $ReleaseId, $_); return }
        if (-not $rel) { Write-Output ("Discogs release not found: {0}" -f $ReleaseId); return }

        $map = $null
        try { $map = ConvertFrom-DiscogsRelease -Release $rel } catch { Write-Output ("Failed to map Discogs release {0}: {1}" -f $ReleaseId, $_); return }
        if (-not $map -or -not $map.Tracks -or $map.Tracks.Count -eq 0) { Write-Output "Discogs mapping has no tracks"; return }

        # Enumerate audio files
        $files = Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $audioExtensions -contains $_.Extension.ToLower() }
        if ($files.Count -eq 0) { Write-Output "No audio files found"; return }

        # Extract file metadata (Disc/Track where available)
        $fileInfos = @()
        foreach ($f in $files) {
            $disc = $null; $track = $null; $title = $null
            try {
                # Clear TagLib cache
                try { $cache = [TagLib.File]::Cache; if ($cache) { $cache.Clear() } } catch { }
                $tf = Invoke-TagLibCreate -Path $f.FullName
                if ($tf) {
                    $disc = $tf.Tag.Disc
                    $track = $tf.Tag.Track
                    $title = $tf.Tag.Title
                }
            } catch { }
            finally {
                if ($tf) { try { $tf.Dispose() } catch { } }
            }
            if (-not $disc -or $disc -eq 0) { $disc = Get-DiscFromPath -p $f.DirectoryName }
            if (-not $disc -or $disc -eq 0) { $disc = $null }
            $fileInfos += [pscustomobject]@{ File=$f; Disc=$disc; Track=$track; Title=$title }
        }

        # Group Discogs tracks by disc (null => 1 if any file uses disc numbers)
        $discUsed = ($fileInfos | Where-Object { $_.Disc })
        $defaultDisc = if ($discUsed.Count -gt 0) { 1 } else { $null }
        $tracksByDisc = @{}
        foreach ($t in $map.Tracks) {
            $d = if ($null -ne $t.Disc -and $t.Disc -ne 0) { [int]$t.Disc } else { $defaultDisc }
            if ($null -eq $d) { continue }
            if (-not $tracksByDisc.ContainsKey($d)) { $tracksByDisc[$d] = New-Object System.Collections.Generic.List[object] }
            $tracksByDisc[$d].Add($t)
        }

    $updates = 0; $skipped = 0; $lenMismatches = 0
        # For each disc group among files
        $fileGroups = $fileInfos | Group-Object { if ($_.Disc) { $_.Disc } else { $defaultDisc } }
        foreach ($g in $fileGroups) {
            $discKey = $g.Name
            $discTracks = if ($discKey -ne $null -and $tracksByDisc.ContainsKey([int]$discKey)) { $tracksByDisc[[int]$discKey] } else { $null }
            if (-not $discTracks -or $discTracks.Count -eq 0) {
                Write-Verbose ("No Discogs tracks for disc '{0}', skipping group of {1} files" -f $discKey, $g.Count)
                $skipped += $g.Count
                continue
            }

            # Sort files based on existing track numbers or name
            $filesSorted = $null
            if ($MatchBy -eq 'Number') {
                $withNum = $g.Group | Where-Object { $_.Track -and $_.Track -ne 0 } | Sort-Object Track
                $without = $g.Group | Where-Object { -not $_.Track -or $_.Track -eq 0 } | Sort-Object { $_.File.Name }
                $filesSorted = @($withNum + $without)
            } else {
                $filesSorted = $g.Group | Sort-Object { $_.File.Name }
            }

            $discTracksSorted = $discTracks | Sort-Object { if ($_.Track) { $_.Track } else { 0 } }
            $limit = [math]::Min($filesSorted.Count, $discTracksSorted.Count)
            for ($i=0; $i -lt $limit; $i++) {
                $fi = $filesSorted[$i]
                $ti = $discTracksSorted[$i]
                $newDisc = if ($discKey) { [uint32]$discKey } else { 0 }
                $newTrack = if ($ti.Track) { [uint32]$ti.Track } else { [uint32]($i+1) }
                $newTitle = $ti.Title

                $leaf = $fi.File.Name
                $action = "Set track tags: Disc={0}; Track={1}; Title='{2}'" -f $newDisc, $newTrack, $newTitle
                if ($PSCmdlet.ShouldProcess($leaf, $action)) {
                    try {
                        # Clear TagLib cache; reopen for write
                        try { $cache = [TagLib.File]::Cache; if ($cache) { $cache.Clear() } } catch { }
                        $tf2 = Invoke-TagLibCreate -Path $fi.File.FullName
                        if ($tf2) {
                            # Optional length validation before writing
                            if ($ValidateLength -and $ti.PSObject.Properties.Name -contains 'Seconds' -and $ti.Seconds) {
                                try {
                                    $dur = $null
                                    if ($tf2.PSObject.Properties.Name -contains 'Properties' -and $tf2.Properties -and $tf2.Properties.Duration) {
                                        $dur = [int][Math]::Round($tf2.Properties.Duration.TotalSeconds)
                                    }
                                    if ($dur -ne $null) {
                                        $diff = [math]::Abs($dur - [int]$ti.Seconds)
                                        if ($diff -gt $LengthToleranceSec) {
                                            $lenMismatches++
                                            $msg = "Length mismatch: file=${dur}s vs discogs=$($ti.Seconds)s (diff=$diff)s"
                                            Write-Verbose $msg
                                            if ($LogPath) { Write-StructuredLog -Path $LogPath -Entry @{ Function='Set-TrackTagsFromDiscogs'; Level='Warning'; Status='LengthMismatch'; Path=$Path; File=$fi.File.FullName; FileSeconds=$dur; DiscogsSeconds=[int]$ti.Seconds; Diff=$diff } }
                                            if ($StrictLength) { throw $msg }
                                        }
                                    }
                                } catch { }
                            }
                            if ($newDisc -gt 0) { $tf2.Tag.Disc = $newDisc }
                            $tf2.Tag.Track = $newTrack
                            if ($newTitle) { $tf2.Tag.Title = $newTitle }
                            if (-not $WhatIfPreference) { $tf2.Save() }
                            try { $tf2.Dispose() } catch { }
                            $updates++
                            if ($LogPath) { Write-StructuredLog -Path $LogPath -Entry @{ Function='Set-TrackTagsFromDiscogs'; Level='Info'; Status='UpdatedTrack'; Path=$Path; File=$fi.File.FullName; Disc=$newDisc; Track=$newTrack; Title=$newTitle } }
                        }
                    } catch {
                        Write-Output ("Failed to update {0}: {1}" -f $fi.File.FullName, $_)
                    }
                }
            }
        }

        $summary = "Track updates={0} Skipped={1}" -f $updates, $skipped
        if ($ValidateLength) { $summary += (" LengthMismatches={0}" -f $lenMismatches) }
        Write-Output $summary
    }
}
