function Confirm-MfcMutationAllowed {
    <#
    .SYNOPSIS
    Re-checks folder structure before a mutating operation and enforces collection guardrails.

    .DESCRIPTION
    Calls `Get-FolderStructureAnalysis` to classify the folder and, unless `-AllowCollectionChanges` is present,
    blocks mutations for `ArtistFolder` and `BoxSet`. Returns an object with `Allowed`, `StructureType`, `Confidence`,
    and `Reason`.

    .PARAMETER Path
    Folder to validate prior to mutation.

    .PARAMETER AllowCollectionChanges
    When set, allow mutations even for ArtistFolder/BoxSet structures.

    .OUTPUTS
    PSCustomObject with properties: Allowed (bool), StructureType, Confidence, Reason
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$AllowCollectionChanges
    )

    try {
        $analysis = Get-FolderStructureAnalysis -Path $Path -UseConsensusHints
    } catch {
        return [pscustomobject]@{ Allowed = $false; StructureType = $null; Confidence = 0.0; Reason = ("Analysis failed: {0}" -f $_) }
    }

    if (-not $analysis) {
        return [pscustomobject]@{ Allowed = $false; StructureType = $null; Confidence = 0.0; Reason = 'No analysis available' }
    }

    $st = $analysis.StructureType
    if ($st -in @('ArtistFolder','BoxSet')) {
        if (-not $AllowCollectionChanges) {
            return [pscustomobject]@{
                Allowed = $false
                StructureType = $st
                Confidence = $analysis.Confidence
                Reason = 'Collection guard: Use -AllowCollectionChanges to override'
            }
        }
    }
    return [pscustomobject]@{ Allowed = $true; StructureType = $st; Confidence = $analysis.Confidence; Reason = 'OK' }
}
