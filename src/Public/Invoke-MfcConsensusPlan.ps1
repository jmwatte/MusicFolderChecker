function Invoke-MfcConsensusPlan {
    <#
    .SYNOPSIS
    Applies a New-MfcConsensusPlan: tags, optional folder rename, with guardrails and WhatIf.

    .DESCRIPTION
    Takes items produced by `New-MfcConsensusPlan` and applies suggested tag updates and optional folder renames.
    Before any mutation, re-checks structure via `Confirm-MfcMutationAllowed` and blocks ArtistFolder/BoxSet unless
    `-AllowCollectionChanges` is set. Honors `-WhatIf` via SupportsShouldProcess.

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

    begin { $applied = 0; $skipped = 0 }

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

            # Apply tag updates using existing updater in scripted mode (no prompts)
            if ($applyYear -or $applyAlbum -or $applyArtist) {
                if ($PSCmdlet.ShouldProcess($folder, 'Apply tag consensus')) {
                    Update-MusicFolderMetadata -FolderPath $folder `
                        -Year $applyYear -Album $applyAlbum -AlbumArtist $applyArtist `
                        -NonInteractive -UseConsensusHints -AllowCollectionChanges:$AllowCollectionChanges `
                        -LogPath $LogPath -WhatIf:$WhatIfPreference
                }
            }

            # Optional rename
            if ($Rename -and $item.ProposedRename -and $item.SuggestedFolderName) {
                $parent = Split-Path -Parent $folder
                $target = Join-Path $parent $item.SuggestedFolderName
                if ((Test-Path -LiteralPath $target) -and $OnConflict -eq 'Skip') {
                    Write-Output ("Rename skipped (exists): {0} -> {1}" -f $folder, $target)
                } else {
                    if ($PSCmdlet.ShouldProcess((Split-Path $folder -Leaf), ("Rename to {0}" -f $target))) {
                        try {
                            if ((Test-Path -LiteralPath $target) -and $OnConflict -eq 'Overwrite') {
                                Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
                            }
                            Rename-Item -LiteralPath $folder -NewName $item.SuggestedFolderName -Force
                            if ($LogPath) { Write-StructuredLog -Path $LogPath -Entry @{ Function='Invoke-MfcConsensusPlan'; Level='Info'; Status='Renamed'; Path=$folder; Destination=$target } }
                        } catch {
                            Write-Output ("Rename failed: {0} -> {1}: {2}" -f $folder, $target, $_)
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