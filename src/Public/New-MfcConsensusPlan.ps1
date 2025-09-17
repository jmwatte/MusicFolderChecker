function New-MfcConsensusPlan {
    <#
    .SYNOPSIS
        Builds a plan of suggested tag updates and folder renames using consensus from audio tags.

    .DESCRIPTION
        Scans one or more folders (optionally recursively), derives consensus for Year/Album/Artist from
        tags, and proposes a normalized folder name (e.g. "YYYY - Album"). Attaches structure analysis
        for guardrails (BoxSet/ArtistFolder). Outputs a plan you can review or pipe to Invoke-MfcConsensusPlan.

    .PARAMETER Path
        One or more root folders to analyze.

    .PARAMETER Recurse
        Include all subfolders under each Path.

    .PARAMETER UseConsensusHints
        When set, uses analyzer hints in addition to per-folder consensus. Defaults to on.

    .PARAMETER MinFiles
        Minimum audio files in a folder to consider for consensus. Default 3.

    .PARAMETER YearThreshold
        Ratio threshold (0-1) to consider Year consistent. Default 0.6.

    .PARAMETER AlbumThreshold
        Ratio threshold (0-1) to consider Album consistent. Default 0.6.

    .PARAMETER ArtistThreshold
        Ratio threshold (0-1) to consider Artist consistent. Default 0.6.

    .PARAMETER OutputPath
        Optional path to write the plan as JSON (array). If not specified, writes objects to the pipeline.

    .EXAMPLE
        New-MfcConsensusPlan -Path 'D:\Music' -Recurse | Format-Table Path,SuggestedFolderName,ProposedAlbum,ProposedYear

    .EXAMPLE
        New-MfcConsensusPlan -Path 'D:\BoxSets' -Recurse -OutputPath 'C:\temp\plan.json'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]]$Path,

        [switch]$Recurse,

    [switch]$UseConsensusHints,

        [int]$MinFiles = 3,
        [double]$YearThreshold = 0.6,
        [double]$AlbumThreshold = 0.6,
        [double]$ArtistThreshold = 0.6,

        [string]$OutputPath
    )

    begin {
        $audioExtensions = @('.mp3', '.flac', '.m4a', '.ogg', '.wav', '.aac', '.wma', '.ape', '.aiff', '.aif')
        $plan = @()
    }

    process {
        foreach ($root in $Path) {
            if (-not (Test-Path -LiteralPath $root)) { Write-Output "Skipping missing: $root"; continue }
            $targets = @($root)
            if ($Recurse) {
                $targets += (Get-ChildItem -LiteralPath $root -Directory -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
                $targets = $targets | Select-Object -Unique
            }

            foreach ($folder in $targets) {
                # Determine if folder has enough audio files
                $audioFiles = @()
                foreach ($ext in $audioExtensions) {
                    $audioFiles += Get-ChildItem -LiteralPath $folder -File -Filter "*${ext}" -ErrorAction SilentlyContinue
                }
                if ($audioFiles.Count -lt $MinFiles) { continue }

                # Structure analysis (for guardrails and extra hints)
                $analysis = $null
                try { $analysis = if ($UseConsensusHints) { Get-FolderStructureAnalysis -Path $folder -UseConsensusHints } else { Get-FolderStructureAnalysis -Path $folder } } catch { }

                # Consensus
                $cons = $null
                try {
                    $cons = Get-FolderTagConsensus -Path $folder -AudioExtensions $audioExtensions -MinFiles $MinFiles -YearThreshold $YearThreshold -AlbumThreshold $AlbumThreshold -ArtistThreshold $ArtistThreshold
                } catch { }
                if (-not $cons) { continue }

                $leaf = Split-Path $folder -Leaf
                $suggestedName = $cons.SuggestedFolderName
                $proposedRename = ($suggestedName -and $suggestedName -ne $leaf)

                $item = [PSCustomObject]@{
                    Path = $folder
                    CurrentFolderName = $leaf
                    SuggestedFolderName = $suggestedName
                    ProposedRename = $proposedRename
                    ProposedYear = $cons.SuggestedYear
                    ProposedAlbum = $cons.SuggestedAlbum
                    ProposedAlbumArtist = $cons.SuggestedArtist
                    Consensus = [PSCustomObject]@{
                        YearConsensus = $cons.YearConsensus
                        YearTopRatio = $cons.YearTopRatio
                        YearValidCount = $cons.YearValidCount
                        YearCoverageRatio = $cons.YearCoverageRatio
                        AlbumConsensus = $cons.AlbumConsensus
                        AlbumTopRatio = $cons.AlbumTopRatio
                        ArtistConsensus = $cons.ArtistConsensus
                        ArtistTopRatio = $cons.ArtistTopRatio
                        Confidence = $cons.Confidence
                    }
                    StructureType = if ($analysis) { $analysis.StructureType } else { $null }
                    StructureConfidence = if ($analysis) { $analysis.Confidence } else { $null }
                    RequiresAllowCollectionChanges = ($analysis -and ($analysis.StructureType -in @('ArtistFolder','BoxSet')))
                    Reason = if ($analysis -and $analysis.Details) { ($analysis.Details -join '; ') } else { 'Consensus-derived' }
                    Notes = $cons.Details
                }
                $plan += $item
            }
        }
    }

    end {
        if ($OutputPath) {
            try {
                $plan | ConvertTo-Json -Depth 6 | Out-File -FilePath $OutputPath -Encoding UTF8
                Write-Output "Plan written to $OutputPath ($($plan.Count) items)"
            }
            catch {
                Write-Output ("Failed to write plan to {0}: {1}" -f $OutputPath, $_)
            }
        } else {
            $plan
        }
    }
}
