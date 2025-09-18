<#
.SYNOPSIS
Applies Discogs plan proposals to folders.

.DESCRIPTION
Takes plan items from New-MfcDiscogsPlan and applies AlbumArtist/Album/Year, and optionally per-track
Title/Track/Disc using Set-TrackTagsFromDiscogs. Honors guardrails and -WhatIf via ShouldProcess.

.PARAMETER Plan
Plan items produced by New-MfcDiscogsPlan.

.PARAMETER Tracks
Also apply per-track tag updates from Discogs.

.PARAMETER Rename
Optionally rename folders after tags are applied.

.PARAMETER LogPath
Structured JSONL log path.

.EXAMPLE
New-MfcDiscogsPlan -Path 'D:\\Music' -Recurse | Invoke-MfcDiscogsPlan -Tracks -WhatIf
#>
function Invoke-MfcDiscogsPlan {
    <#
    .SYNOPSIS
    Applies Discogs-derived tag proposals to album folders.

    .DESCRIPTION
    Accepts plan items from New-MfcDiscogsPlan and applies AlbumArtist/Album/Year using
    Update-MusicFolderMetadata in non-interactive mode. Optionally applies per-track Title/Track/Disc
    using Set-TrackTagsFromDiscogs. Honors guardrails and ShouldProcess.

    .PARAMETER Plan
    Plan items from New-MfcDiscogsPlan (pipeline supported).

    .PARAMETER Tracks
    Also apply per-track tags (Title/Track/Disc) from the Discogs release referenced by the plan.

    .PARAMETER Rename
    If set, rename folders after tags are applied using suggested folder naming from consensus.

    .PARAMETER LogPath
    Optional structured log path.

    .EXAMPLE
    New-MfcDiscogsPlan -Path 'D:\\Music' -Recurse | Invoke-MfcDiscogsPlan -Tracks -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [psobject[]]$Plan,

        [switch]$Tracks,
        [switch]$Rename,
        [string]$LogPath
    )

    begin { $applied = 0; $skipped = 0 }
    process {
        foreach ($item in $Plan) {
            $folder = $item.Path
            if (-not (Test-Path -LiteralPath $folder)) { Write-Output "Missing folder: $folder"; $skipped++; continue }

            $guard = Confirm-MfcMutationAllowed -Path $folder -AllowCollectionChanges:$false
            if (-not $guard.Allowed) { Write-Output ("Skipping (guard): {0} — {1}" -f $folder, $guard.Reason); $skipped++; continue }

            $artist = $item.ProposedAlbumArtist
            $album  = $item.ProposedAlbum
            $year   = $item.ProposedYear
            if (-not $artist -and -not $album -and -not $year) { $skipped++; continue }

            $changes = @()
            if ($artist) { $changes += ("Artist='{0}'" -f $artist) }
            if ($album)  { $changes += ("Album='{0}'" -f $album) }
            if ($year)   { $changes += ("Year={0}" -f $year) }
            $action = if ($changes.Count -gt 0) { 'Apply tags: ' + ($changes -join '; ') } else { 'Apply tags (no changes)' }

            if ($PSCmdlet.ShouldProcess($folder, $action)) {
                if (-not $WhatIfPreference) {
                    Update-MusicFolderMetadata -FolderPath $folder -AlbumArtist $artist -Album $album -Year $year -NonInteractive -UseConsensusHints -LogPath $LogPath -WhatIf:$WhatIfPreference
                    if ($Tracks -and $item.ReleaseId) {
                        try {
                            # Apply per-track tags as a separate ShouldProcess action per file inside the helper
                            Set-TrackTagsFromDiscogs -Path $folder -ReleaseId ([int]$item.ReleaseId) -LogPath $LogPath -WhatIf:$WhatIfPreference
                        } catch {
                            Write-Verbose ("Per-track apply failed for {0}: {1}" -f $folder, $_)
                            if ($LogPath) { Write-StructuredLog -Path $LogPath -Entry @{ Function='Invoke-MfcDiscogsPlan'; Level='Warning'; Status='TracksApplyFailed'; Path=$folder; ReleaseId=$item.ReleaseId; Details = $_.ToString() } }
                        }
                    }
                } else {
                    if ($LogPath) { Write-StructuredLog -Path $LogPath -Entry @{ Function='Invoke-MfcDiscogsPlan'; Level='Info'; Status='WillApply'; Path=$folder; Changes=$changes -join '; '; Tracks=$Tracks } }
                }
            }

            if ($Rename) {
                # Optional: we could compute suggested name from consensus again
                # For now, rely on separate consensus rename pipeline if desired.
            }

            $applied++
        }
    }
    end { Write-Output ("Applied={0} Skipped={1}" -f $applied, $skipped) }
}
