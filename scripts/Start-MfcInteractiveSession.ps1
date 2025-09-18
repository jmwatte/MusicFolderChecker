[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory)]
    [string]$RootPath,

    [string]$DestinationFolder,

    [string]$StatePath = (Join-Path -Path $PWD -ChildPath ('mfc-session-{0:yyyyMMdd-HHmmss}.json' -f (Get-Date))),

    [switch]$Recurse,
    [switch]$Fast,
    [switch]$ShowProgress,

    [string[]]$ExcludePath,
    [string[]]$ExcludeName,

    [double]$YearThreshold = 0.6,
    [double]$AlbumThreshold = 0.6,
    [double]$ArtistThreshold = 0.6,
    [double]$MinYearCoverage = 0.4,

    [int]$MaxFolders = 0,

    [string]$LogPath
)

<#
.SYNOPSIS
Interactive, resumable session to review/apply MusicFolderChecker suggestions one folder at a time.

.DESCRIPTION
- Streams a plan from New-MfcConsensusPlan and persists session state to a JSON file so you can resume later.
- For each folder, shows the key analysis/suggestions, then prompts:
  [A]pply, [E]dit, [S]kip, [R]ename-only, [T]ags-only, [M]ove, [Q]uit.
- Applies changes non-interactively via Invoke-MfcConsensusPlan (consensus) or Update-MusicFolderMetadata (manual overrides).
- Honors guardrails (re-checks structure, requires -AllowCollectionChanges for ArtistFolder/BoxSet roots inside apply commands).

.PARAMETER RootPath
Root folder to scan (typically an artist folder or library root).

.PARAMETER DestinationFolder
When specified, the Move action places updated albums into this target path.

.PARAMETER StatePath
Where to store/load session state JSON for resuming later.

.PARAMETER Recurse
Scan subfolders recursively (recommended).

.PARAMETER Fast
Sample-limited consensus to speed up planning.

.PARAMETER ShowProgress
Show a progress bar during planning.

.PARAMETER ExcludePath
Full-path patterns to exclude from planning.

.PARAMETER ExcludeName
Leaf name patterns to exclude from planning.

.PARAMETER YearThreshold
Consensus threshold for Year.

.PARAMETER AlbumThreshold
Consensus threshold for Album.

.PARAMETER ArtistThreshold
Consensus threshold for Artist.

.PARAMETER MinYearCoverage
Require at least this coverage of numeric Tag.Year before applying Year.

.PARAMETER MaxFolders
Optional cap on how many folders to include in this session.

.PARAMETER LogPath
Optional structured JSONL log for apply operations.

.EXAMPLE
.\scripts\Start-MfcInteractiveSession.ps1 -RootPath 'D:\Tangerine Dream' -Recurse -Fast -ShowProgress -DestinationFolder 'D:\_CorrectedMusic'

# Resumes from previous state
.\scripts\Start-MfcInteractiveSession.ps1 -RootPath 'D:\Tangerine Dream' -Recurse -Fast -StatePath .\mfc-session-20250918-112233.json
#>

function Save-Session {
    param([hashtable]$State)
    $json = $State | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath $StatePath -Value $json -Encoding UTF8
    Write-Output ("Saved session to {0}" -f $StatePath)
}

function Load-Session {
    param([string]$Path)
    try {
        if (Test-Path -LiteralPath $Path) {
            $obj = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 6
            return @{'Version'=($obj.Version); 'RootPath'=($obj.RootPath); 'Created'=($obj.Created); 'Items'=([System.Collections.Generic.List[object]]$obj.Items); 'Index'=([int]$obj.Index) }
        }
    } catch {
        Write-Output ("Failed to load session: {0}" -f $_.Exception.Message)
    }
    return $null
}

function New-SessionState {
    param([string]$Root)
    return @{
        Version = 1
        RootPath = $Root
        Created = (Get-Date)
        Items = New-Object System.Collections.Generic.List[object]
        Index = 0
    }
}

function Format-PlanSummary {
    param($Item)
    $c = $Item.Consensus
    $line1 = "Path: {0}" -f $Item.Path
    $line2 = "Proposed: Artist='{0}', Album='{1}', Year={2} (coverage {3:P0})" -f ($Item.ProposedAlbumArtist ?? ''), ($Item.ProposedAlbum ?? ''), ($Item.ProposedYear ?? $null), ($c.YearCoverageRatio)
    $line3 = "Structure: {0} (conf {1}) Rename: {2}" -f $Item.StructureType, $Item.StructureConfidence, $Item.ProposedRename
    $line4 = if ($Item.SuggestedFolderName -and ($Item.SuggestedFolderName -ne $Item.CurrentFolderName)) {
        "Rename to: {0}" -f $Item.SuggestedFolderName
    } else { "Rename to: (no change)" }
    $notes = if ($Item.Notes -and $Item.Notes.Count -gt 0) { "Notes: {0}" -f ($Item.Notes -join ' | ') } else { $null }
    @($line1,$line2,$line3,$line4,$notes) | Where-Object { $_ } | ForEach-Object { Write-Output $_ }
}

# Load or create session
$state = Load-Session -Path $StatePath
if (-not $state) {
    $state = New-SessionState -Root $RootPath

    # Stream plan items and collect into the session; show progress entries as they arrive
    $planParams = @{
        Path = $RootPath
        Recurse = $Recurse.IsPresent
        UseConsensusHints = $true
        YearThreshold = $YearThreshold
        AlbumThreshold = $AlbumThreshold
        ArtistThreshold = $ArtistThreshold
    }
    if ($Fast) { $planParams['Fast'] = $true }
    if ($ShowProgress) { $planParams['ShowProgress'] = $true }
    if ($ExcludePath) { $planParams['ExcludePath'] = $ExcludePath }
    if ($ExcludeName) { $planParams['ExcludeName'] = $ExcludeName }

    $count = 0
    New-MfcConsensusPlan @planParams | ForEach-Object {
        $state.Items.Add($_)
        $count++
        if ($MaxFolders -gt 0 -and $count -ge $MaxFolders) { return }
    }

    Save-Session -State $state
}

Write-Output ("Loaded session with {0} items; next index: {1}" -f $state.Items.Count, $state.Index)

# Main loop
for ($i = $state.Index; $i -lt $state.Items.Count; $i++) {
    $item = $state.Items[$i]
    Write-Output ('-' * 80)
    Format-PlanSummary -Item $item
    Write-Output "[A]pply  [E]dit  [D]iscogs  [R]ename-only  [T]ags-only  [M]ove  [S]kip  [Q]uit"
    $choice = Read-Host "Choose action"

    switch -Regex ($choice) {
        '^(?i)q' {
            $state.Index = $i
            Save-Session -State $state
            Write-Output "Quitting. You can resume with -StatePath '$StatePath'"
            break
        }
        '^(?i)s' {
            $item.Status = 'Skipped'
            $state.Index = $i + 1
            Save-Session -State $state
            continue
        }
        '^(?i)e' {
            # Manual overrides
            $aa = Read-Host ("Album Artist (blank=keep, current='{0}')" -f ($item.ProposedAlbumArtist ?? ''))
            $al = Read-Host ("Album (blank=keep, current='{0}')" -f ($item.ProposedAlbum ?? ''))
            $yr = Read-Host ("Year (blank=keep, current='{0}')" -f ($item.ProposedYear ?? ''))
            $params = @{
                FolderPath = $item.Path
                NonInteractive = $true
                UseConsensusHints = $true
            }
            if ($aa) { $params['AlbumArtist'] = $aa }
            if ($al) { $params['Album'] = $al }
            if ($yr) { $params['Year'] = [int]$yr }

            if ($PSCmdlet.ShouldProcess($item.Path, "Apply manual tags")) {
                try {
                    Update-MusicFolderMetadata @params
                    $item.Status = 'AppliedManual'
                } catch {
                    Write-Output ("Error applying manual tags: {0}" -f $_.Exception.Message)
                    $item.Status = 'ErrorManual'
                }
            }
            $state.Index = $i + 1
            Save-Session -State $state
            continue
        }
        '^(?i)d' {
            # Discogs-assisted edit
            Write-Output "Searching Discogs for: $($item.ProposedAlbumArtist) - $($item.ProposedAlbum) ($($item.ProposedYear))"
            $cands = $null
            try {
                $cands = Find-MfcDiscogsMatch -Path $item.Path -PerPage 15
            } catch { Write-Output ("Discogs search failed: {0}" -f $_.Exception.Message) }
            if (-not $cands) {
                Write-Output "No Discogs candidates found."
                $state.Index = $i + 1
                Save-Session -State $state
                continue
            }

            $j = 0
            foreach ($c in $cands) { $j++; Write-Output ("[{0}] {1}  Year={2}  Score={3}  {4}" -f $j, $c.Title, $c.Year, $c.Score, $c.Reasons) }
            $pick = Read-Host "Pick a release number (blank=skip)"
            if (-not $pick) { $state.Index = $i + 1; Save-Session -State $state; continue }
            $idx = 0; [void][int]::TryParse($pick, [ref]$idx)
            if ($idx -lt 1 -or $idx -gt $cands.Count) { $state.Index = $i + 1; Save-Session -State $state; continue }
            $chosen = $cands[$idx-1]

            $rel = $null
            try { $rel = Get-DiscogsRelease -Id $chosen.Id } catch { }
            if (-not $rel) { Write-Output "Failed to retrieve selected release."; $state.Index = $i + 1; Save-Session -State $state; continue }

            $mapped = ConvertFrom-DiscogsRelease -Release $rel
            $aa = $mapped.AlbumArtist
            $al = $mapped.Album
            $yr = $mapped.Year

            Write-Output ("Discogs proposes -> Artist='{0}', Album='{1}', Year={2}" -f $aa, $al, $yr)
            $confirm = Read-Host "Apply these tags? (Y/N)"
            if ($confirm -match '^(?i)y') {
                if ($PSCmdlet.ShouldProcess($item.Path, "Apply Discogs tags")) {
                    try {
                        Update-MusicFolderMetadata -FolderPath $item.Path -AlbumArtist $aa -Album $al -Year $yr -NonInteractive -UseConsensusHints -ErrorAction Stop
                        $item.Status = 'AppliedDiscogs'
                    } catch {
                        Write-Output ("Error applying Discogs tags: {0}" -f $_.Exception.Message)
                        $item.Status = 'ErrorDiscogs'
                    }
                }
            }
            $state.Index = $i + 1
            Save-Session -State $state
            continue
        }
        '^(?i)r' {
            # Rename-only
            if (-not $item.ProposedRename -or -not $item.SuggestedFolderName) {
                Write-Output "No rename proposed."
                $state.Index = $i + 1
                Save-Session -State $state
                continue
            }
            $one = $item
            if ($PSCmdlet.ShouldProcess($item.Path, "Rename to '{0}'" -f $item.SuggestedFolderName)) {
                try {
                    # Apply only rename path via plan apply with -Rename
                    $one | Invoke-MfcConsensusPlan -Rename -MinYearCoverage $MinYearCoverage -WhatIf:$WhatIfPreference -ErrorAction Stop
                    $item.Status = 'Renamed'
                } catch {
                    Write-Output ("Error renaming: {0}" -f $_.Exception.Message)
                    $item.Status = 'ErrorRename'
                }
            }
            $state.Index = $i + 1
            Save-Session -State $state
            continue
        }
        '^(?i)t' {
            # Tags-only via plan apply (no rename)
            $one = $item
            if ($PSCmdlet.ShouldProcess($item.Path, "Apply consensus tags")) {
                try {
                    $applyParams = @{
                        MinYearCoverage = $MinYearCoverage
                        ErrorAction = 'Stop'
                    }
                    if ($LogPath) { $applyParams['LogPath'] = $LogPath }
                    $one | Invoke-MfcConsensusPlan @applyParams
                    $item.Status = 'AppliedTags'
                } catch {
                    Write-Output ("Error applying tags: {0}" -f $_.Exception.Message)
                    $item.Status = 'ErrorTags'
                }
            }
            $state.Index = $i + 1
            Save-Session -State $state
            continue
        }
        '^(?i)m' {
            # Move (no rename here; filename strategy is handled by Update-MusicFolderMetadata)
            if (-not $DestinationFolder) {
                Write-Output "No -DestinationFolder specified for move."
                $state.Index = $i + 1
                Save-Session -State $state
                continue
            }
            if ($PSCmdlet.ShouldProcess($item.Path, "Move to '{0}'" -f $DestinationFolder)) {
                try {
                    Update-MusicFolderMetadata -FolderPath $item.Path -NonInteractive -Move -DestinationFolder $DestinationFolder -UseConsensusHints -ErrorAction Stop
                    $item.Status = 'Moved'
                } catch {
                    Write-Output ("Error moving: {0}" -f $_.Exception.Message)
                    $item.Status = 'ErrorMove'
                }
            }
            $state.Index = $i + 1
            Save-Session -State $state
            continue
        }
        default {
            # Default to consensus apply + optional rename (safer path)
            $one = $item
            if ($PSCmdlet.ShouldProcess($item.Path, "Apply consensus (tags+optional rename)")) {
                try {
                    $applyParams = @{
                        MinYearCoverage = $MinYearCoverage
                        ErrorAction = 'Stop'
                    }
                    if ($LogPath) { $applyParams['LogPath'] = $LogPath }
                    # Rename only when SuggestedFolderName differs
                    if ($item.ProposedRename -and $item.SuggestedFolderName) {
                        $applyParams['Rename'] = $true
                    }
                    $one | Invoke-MfcConsensusPlan @applyParams
                    $item.Status = if ($applyParams.ContainsKey('Rename')) { 'Applied+Renamed' } else { 'Applied' }
                } catch {
                    Write-Output ("Error applying consensus: {0}" -f $_.Exception.Message)
                    $item.Status = 'Error'
                }
            }
            $state.Index = $i + 1
            Save-Session -State $state
            continue
        }
    }

    if ($choice -match '^(?i)q') { break }
}

Write-Output "Session complete or paused. State stored at: $StatePath"