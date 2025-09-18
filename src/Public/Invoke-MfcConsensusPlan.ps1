<#
.SYNOPSIS
Applies a consensus plan to update tags and optionally rename folders.

.DESCRIPTION
Takes items produced by New-MfcConsensusPlan and applies AlbumArtist/Album/Year and optional renames,
with guardrails for ArtistFolder/BoxSet and clear WhatIf previews.

.PARAMETER Plan
Plan objects from New-MfcConsensusPlan.

.PARAMETER Rename
Also rename folders to SuggestedFolderName when appropriate.

.PARAMETER AllowCollectionChanges
Permit changes on collection roots.

.PARAMETER LogPath
Structured JSONL log path.

.EXAMPLE
New-MfcConsensusPlan -Path 'D:\\Music' -Recurse | Invoke-MfcConsensusPlan -WhatIf
#>
function Invoke-MfcConsensusPlan {
    <#
    .SYNOPSIS
    Applies a New-MfcConsensusPlan: tags, optional folder rename, with guardrails and WhatIf.

    .DESCRIPTION
    Takes items produced by `New-MfcConsensusPlan` and applies suggested tag updates and optional folder renames.
    Before any mutation, re-checks structure via `Confirm-MfcMutationAllowed` and blocks ArtistFolder/BoxSet unless
    `-AllowCollectionChanges` is set. Honors `-WhatIf` via SupportsShouldProcess.
    Use `-Verbose` to see detailed decisions (consensus, coverage, inheritance, and fallbacks) per folder.

    .PARAMETER Plan
    Plan items from `New-MfcConsensusPlan` (pipeline input supported).

    .PARAMETER Rename
    If set, rename folders to `SuggestedFolderName` when different.

    .PARAMETER AllowCollectionChanges
    Allow mutations on ArtistFolder or BoxSet roots.

    .PARAMETER LogPath
    Optional structured JSONL log path for audit.

    .PARAMETER OnConflict
    For renames: choose behavior when target exists. Default Skip.

    .NOTES
    Automatic artist inheritance: If the parent folder classifies as a BoxSet or MultiDiscAlbum and the
    grandparent as an ArtistFolder, AlbumArtist is inherited from the artist folder (grandparent leaf)
    for child items unless a strong artist consensus/proposal already exists.

    .EXAMPLE
    New-MfcConsensusPlan -Path 'D:\Music' -Recurse | Invoke-MfcConsensusPlan -WhatIf
    # Preview apply changes.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [psobject[]]$Plan,

        [switch]$Rename,

        [switch]$AllowCollectionChanges,

        [string]$LogPath,

        [ValidateSet('Skip','Overwrite')]
        [string]$OnConflict = 'Skip',

        [switch]$AllowFallbackFromFolderName,

        [double]$MinYearCoverage = 0.4
    )

    begin {
        $applied = 0; $skipped = 0
        # Cache for structure analyses to avoid recomputation across items
        $analysisCache = @{}

        function Get-AnalysisCached {
            param([string]$Path)
            if (-not $Path) { return $null }
            if ($analysisCache.ContainsKey($Path)) { return $analysisCache[$Path] }
            $res = $null
            try { $res = Get-FolderStructureAnalysis -Path $Path -UseConsensusHints } catch { }
            $analysisCache[$Path] = $res
            return $res
        }
    }

    process {
        foreach ($item in $Plan) {
            $folder = $item.Path
            if (-not (Test-Path -LiteralPath $folder)) { Write-Output "Missing folder: $folder"; $skipped++; continue }

            # Guardrail: confirm allowed just-in-time
            $guard = Confirm-MfcMutationAllowed -Path $folder -AllowCollectionChanges:$AllowCollectionChanges
            if (-not $guard.Allowed) { Write-Output ("Skipping (guard): {0} — {1}" -f $folder, $guard.Reason); $skipped++; continue }

            # Decide what to apply based on consensus and optional fallbacks
            $applyYear = $null
            $applyAlbum = $null
            $applyArtist = $null

            $cons = $item.Consensus
            if ($cons) {
                # Only apply when consensus holds; unless fallback is allowed
                if ($cons.YearConsensus -and $item.ProposedYear) { $applyYear = $item.ProposedYear }
                elseif ($AllowFallbackFromFolderName) { $applyYear = $item.ProposedYear }

                if ($cons.AlbumConsensus -and $item.ProposedAlbum) { $applyAlbum = $item.ProposedAlbum }
                elseif ($AllowFallbackFromFolderName) { $applyAlbum = $item.ProposedAlbum }

                if ($cons.ArtistConsensus -and $item.ProposedAlbumArtist) { $applyArtist = $item.ProposedAlbumArtist }
                elseif ($AllowFallbackFromFolderName) { $applyArtist = $item.ProposedAlbumArtist }

                # Gate Year by coverage threshold if provided
                if ($applyYear -and $cons.YearCoverageRatio -lt $MinYearCoverage) { $applyYear = $null }
            } else {
                # No consensus object? Apply only explicit proposals, or nothing if absent
                $applyYear = $item.ProposedYear
                $applyAlbum = $item.ProposedAlbum
                $applyArtist = $item.ProposedAlbumArtist
            }

            # Verbose: explain which fields will be applied or skipped (consensus & coverage)
            if ($cons) {
                if ($item.ProposedAlbumArtist) {
                    if ($cons.ArtistConsensus) { Write-Verbose ("Artist: applying proposed '{0}' (consensus)" -f $item.ProposedAlbumArtist) }
                    elseif ($AllowFallbackFromFolderName) { Write-Verbose ("Artist: applying proposed '{0}' (fallback from folder name)" -f $item.ProposedAlbumArtist) }
                    else { Write-Verbose ("Artist: skipping (no consensus and fallback disabled)") }
                } else { Write-Verbose ("Artist: no proposal available") }

                if ($item.ProposedAlbum) {
                    if ($cons.AlbumConsensus) { Write-Verbose ("Album: applying proposed '{0}' (consensus)" -f $item.ProposedAlbum) }
                    elseif ($AllowFallbackFromFolderName) { Write-Verbose ("Album: applying proposed '{0}' (fallback from folder name)" -f $item.ProposedAlbum) }
                    else { Write-Verbose ("Album: skipping (no consensus and fallback disabled)") }
                } else { Write-Verbose ("Album: no proposal available") }

                if ($item.ProposedYear) {
                    if ($cons.YearConsensus) { Write-Verbose ("Year: applying proposed {0} (consensus, coverage={1:P0})" -f $item.ProposedYear, $cons.YearCoverageRatio) }
                    elseif ($AllowFallbackFromFolderName) { Write-Verbose ("Year: applying proposed {0} (fallback from folder name)" -f $item.ProposedYear) }
                    else { Write-Verbose ("Year: skipping (no consensus and fallback disabled)") }

                    if ($cons.YearCoverageRatio -lt $MinYearCoverage) { Write-Verbose ("Year: blocked by coverage {0:P0} < MinYearCoverage {1:P0}" -f $cons.YearCoverageRatio, $MinYearCoverage) }
                } else { Write-Verbose ("Year: no proposal available") }
            }

            # Automatic inheritance: if parent is BoxSet or MultiDiscAlbum and grandparent is ArtistFolder, push artist down
            $artistInherited = $false
            # Short-circuit inheritance lookup if we already have a strong artist applied
            $hasStrongArtist = ($cons -and $cons.ArtistConsensus -and $item.ProposedAlbumArtist)
            if (-not $hasStrongArtist -and -not $applyArtist) {
                try {
                    $parentDir = Split-Path -Parent $folder
                    $grandDir  = if ($parentDir) { Split-Path -Parent $parentDir } else { $null }
                    $pa = Get-AnalysisCached -Path $parentDir
                    $ga = Get-AnalysisCached -Path $grandDir
                    if ($pa -and ($pa.StructureType -in @('BoxSet','MultiDiscAlbum')) -and $ga -and $ga.StructureType -eq 'ArtistFolder') {
                        $artistFromGrand = Split-Path -Leaf $grandDir
                        $applyArtist = $artistFromGrand; $artistInherited = $true
                    }
                } catch { }
            }

            if ($artistInherited) { Write-Verbose ("Artist: inherited from ArtistFolder '{0}' due to parent structure {1}" -f (Split-Path -Leaf $grandDir), ($pa.StructureType)) }

            # Apply tag updates using existing updater in scripted mode (no prompts)
            if ($applyYear -or $applyAlbum -or $applyArtist) {
                # Build a clear action message for WhatIf/Confirm
                $changes = @()
                if ($applyArtist) { $changes += ("Artist='{0}'{1}" -f $applyArtist, $(if ($artistInherited) { ' (inherited)' } else { '' })) }
                if ($applyAlbum)  { $changes += ("Album='{0}'" -f $applyAlbum) }
                if ($applyYear) {
                    $yrDetail = if ($cons -and $cons.YearCoverageRatio -ge 0) { " (coverage {0:P0})" -f $cons.YearCoverageRatio } else { '' }
                    $changes += ("Year={0}{1}" -f $applyYear, $yrDetail)
                }
                $actionMsg = if ($changes.Count -gt 0) { 'Apply tags: ' + ($changes -join '; ') } else { 'Apply tags (no changes)' }

                if ($PSCmdlet.ShouldProcess($folder, $actionMsg)) {
                    if (-not $WhatIfPreference) {
                        Update-MusicFolderMetadata -FolderPath $folder `
                            -Year $applyYear -Album $applyAlbum -AlbumArtist $applyArtist `
                            -NonInteractive -UseConsensusHints -AllowCollectionChanges:$AllowCollectionChanges `
                            -LogPath $LogPath -WhatIf:$WhatIfPreference
                    } else {
                        # Avoid expensive per-file TagLib operations during WhatIf; just log intended action
                        if ($LogPath) {
                            Write-StructuredLog -Path $LogPath -Entry @{ Function='Invoke-MfcConsensusPlan'; Level='Info'; Status='WillApply'; Path=$folder; Changes=$changes -join '; ' }
                        }
                    }
                }
            }

            # Optional rename
            if ($Rename -and $item.ProposedRename -and $item.SuggestedFolderName) {
                $parent = Split-Path -Parent $folder
                $target = Join-Path $parent $item.SuggestedFolderName
                if ((Test-Path -LiteralPath $target) -and $OnConflict -eq 'Skip') {
                    Write-Output ("Rename skipped (exists): {0} -> {1}" -f $folder, $target)
                } else {
                    $fromLeaf = Split-Path $folder -Leaf
                    $toLeaf   = $item.SuggestedFolderName
                    $renameMsg = ("Rename folder: '{0}' -> '{1}'" -f $fromLeaf, $toLeaf)
                    if ($PSCmdlet.ShouldProcess($folder, $renameMsg)) {
                        # Avoid renaming a folder that is the current working directory; move to parent temporarily
                        $prevLocation = $null; $movedOut = $false
                        try {
                            $prevLocation = (Get-Location).Path
                            $folderFull = [System.IO.Path]::GetFullPath($folder)
                            $prevFull = [System.IO.Path]::GetFullPath($prevLocation)
                            $folderPrefix = if ($folderFull.EndsWith('\')) { $folderFull } else { $folderFull + '\' }
                            if ($prevFull.Equals($folderFull, [System.StringComparison]::OrdinalIgnoreCase) -or $prevFull.StartsWith($folderPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                                Set-Location -LiteralPath $parent
                                $movedOut = $true
                            }
                        } catch { }

                        try {
                            if ((Test-Path -LiteralPath $target) -and $OnConflict -eq 'Overwrite') {
                                Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
                            }
                            if (-not $WhatIfPreference) {
                                # Retry a few times to ride out transient locks (indexing, AV, etc.)
                                $attempts = 0; $max = 3; $renamed = $false
                                while (-not $renamed -and $attempts -lt $max) {
                                    try {
                                        Rename-Item -LiteralPath $folder -NewName $item.SuggestedFolderName -Force -ErrorAction Stop
                                        $renamed = $true
                                    } catch {
                                        $attempts++
                                        try { [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers() } catch { }
                                        if ($attempts -lt $max) { Start-Sleep -Milliseconds (200 * $attempts) }
                                        else { throw }
                                    }
                                }
                            } else {
                                if ($LogPath) { Write-StructuredLog -Path $LogPath -Entry @{ Function='Invoke-MfcConsensusPlan'; Level='Info'; Status='WillRename'; Path=$folder; Destination=$target; DryRun = $true } }
                            }
                            if ($LogPath -and -not $WhatIfPreference) { Write-StructuredLog -Path $LogPath -Entry @{ Function='Invoke-MfcConsensusPlan'; Level='Info'; Status='Renamed'; Path=$folder; Destination=$target } }
                        } catch {
                            Write-Output ("Rename failed: {0} -> {1}: {2}" -f $folder, $target, $_)
                        } finally {
                            if ($movedOut -and $prevLocation) {
                                try { Set-Location -LiteralPath $prevLocation } catch { }
                            }
                        }
                    }
                }
            }

            $applied++
        }
    }

    end {
        Write-Output ("Applied={0} Skipped={1}" -f $applied, $skipped)
    }
}


<# function Invoke-MfcConsensusPlan {
    <#
    .SYNOPSIS
        Applies a consensus plan: updates tags and optionally renames folders, with guardrails.

    .DESCRIPTION
        Takes plan objects from New-MfcConsensusPlan and applies proposed AlbumArtist/Album/Year
        and optional folder renames. Re-checks StructureType just-in-time to avoid mutating
        BoxSets/ArtistFolders unless -AllowCollectionChanges is set. Honors -WhatIf/-Confirm.

    .PARAMETER Plan
        Plan objects from New-MfcConsensusPlan (pipeline input supported).

    .PARAMETER AllowCollectionChanges
        Permit applying changes to ArtistFolder/BoxSet roots.

    .PARAMETER Rename
        When set, rename folders to SuggestedFolderName (if different).

    .PARAMETER LogPath
        Optional structured log path (JSONL).

    .EXAMPLE
        New-MfcConsensusPlan -Path 'D:\Music' -Recurse | Invoke-MfcConsensusPlan -WhatIf

    .EXAMPLE
        $plan = New-MfcConsensusPlan -Path 'D:\BoxSets' -Recurse
        $plan | Invoke-MfcConsensusPlan -AllowCollectionChanges -Rename -WhatIf
    
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject[]]$Plan,

        [switch]$AllowCollectionChanges,
        [switch]$Rename,
        [string]$LogPath
    )

    begin {
        $items = @()
    }

    process {
        $items += $Plan
    }

    end {
        foreach ($p in $items) {
            $path = $p.Path
            if (-not (Test-Path -LiteralPath $path)) { Write-Output "Missing: $path"; continue }

            # Re-check structure just-in-time
            $analysis = $null
            try { $analysis = Get-FolderStructureAnalysis -Path $path } catch { }
            if ($analysis -and ($analysis.StructureType -in @('ArtistFolder','BoxSet')) -and -not $AllowCollectionChanges) {
                Write-Output "Skipping collection root without -AllowCollectionChanges: $path [$($analysis.StructureType)]"
                continue
            }

            # Apply tags via Update-MusicFolderMetadata (only proposed fields)
            $updateArgs = @{
                FolderPath = $path
                AllowCollectionChanges = $AllowCollectionChanges
            }
            if ($p.ProposedAlbumArtist) { $updateArgs.AlbumArtist = $p.ProposedAlbumArtist }
            if ($p.ProposedAlbum) { $updateArgs.Album = $p.ProposedAlbum }
            if ($p.ProposedYear) { $updateArgs.Year = [int]$p.ProposedYear }

            if ($PSCmdlet.ShouldProcess($path, 'Apply tag consensus')) {
                try {
                    Update-MusicFolderMetadata @updateArgs -Quiet -LogPath $LogPath -WhatIf:$WhatIfPreference | Out-Null
                } catch {
                    Write-Output ("Failed to update tags for {0}: {1}" -f $path, $_)
                }
            }

            # Optional folder rename
            if ($Rename -and $p.ProposedRename -and $p.SuggestedFolderName) {
                $parent = Split-Path -Parent $path
                $dest = Join-Path $parent $p.SuggestedFolderName
                if ($PSCmdlet.ShouldProcess($path, "Rename to $dest")) {
                    try {
                        if (-not $WhatIfPreference) {
                            Rename-Item -LiteralPath $path -NewName $p.SuggestedFolderName -ErrorAction Stop
                        } else {
                            if ($LogPath) { Write-LogEntry -Path $LogPath -Value ("{0}" -f ( @{ Timestamp=(Get-Date).ToString('s'); Status='WillRename'; Path=$path; Destination=$dest } | ConvertTo-Json -Compress )) }
                        }
                    } catch {
                        Write-Output ("Failed to rename {0} -> {1}: {2}" -f $path, $dest, $_)
                    }
                }
            }
        }
    }
}
 #>