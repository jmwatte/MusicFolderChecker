function Invoke-MfcConsensusPlan {
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
    #>
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
