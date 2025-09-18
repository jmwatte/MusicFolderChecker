# Order in Your Music — A Practical Guide (Beginner → Advanced)

This guide shows how to bring order to a messy music library using the MusicFolderChecker module: scan structures, preview changes safely, fix tags, organize folders, and optionally enrich metadata from Discogs — all with reproducible, scriptable workflows.

If you're new, start with “Quick Start.” Power users: jump to “Discogs Integration,” “Planning at Scale,” or “Advanced Tips.”

---

## Quick Start

- Requirements: PowerShell 7+, TagLib-Sharp DLL in `lib/` (see module loader error for details).
- Import the module:

```powershell
Import-Module .\MusicFolderChecker.psd1 -Force
```

- Analyze a single folder:
```powershell
Get-FolderStructureAnalysis -Path 'D:\Music\Artist\1997 - Album'
```

- Preview suggested tags/renames for a tree:
```powershell
New-MfcConsensusPlan -Path 'D:\Music' -Recurse -ShowProgress |
  Format-Table Path, SuggestedFolderName, ProposedAlbum, ProposedYear -AutoSize
```

- Apply plan safely (no changes, just preview):
```powershell
New-MfcConsensusPlan -Path 'D:\Music' -Recurse |
  Invoke-MfcConsensusPlan -WhatIf -Verbose
```

- Apply to one folder (non-interactive tags):
```powershell
Update-MusicFolderMetadata -FolderPath 'D:\Music\Artist\1997 - Album' `
  -AlbumArtist 'Artist' -Album 'Album' -Year 1997 -NonInteractive -WhatIf
```

---

## Key Concepts

- WhatIf everywhere: All destructive/mutating commands support `-WhatIf` via `ShouldProcess`. Use `-WhatIf` first; commit later.
- Guardrails for collections: By default, `ArtistFolder`/`BoxSet` roots are protected. Use `-AllowCollectionChanges` only when you intend to update collection roots.
- Consensus planning: Find stable Artist/Album/Year across files; get a suggested folder name (`YYYY - Album`).
- Streaming & logs: Plans can stream to the pipeline; commands can emit JSONL logs for later analysis (`-JsonlPath`/`-LogPath`).
- Fast mode: Use `-Fast` to sample files for speed on large trees; good for previews.
- Exclusions: Use `-ExcludePath`/`-ExcludeName` to skip archives, temp folders, etc.

---

## Structure Analysis (What’s in this folder?)

```powershell
Get-FolderStructureAnalysis -Path 'D:\Music\Artist\1997 - Album'
```

- Classifies folders as `ArtistFolder`, `SimpleAlbum`, `MultiDiscAlbum`, `MixedAlbum`, `CompilationFolder`, `BoxSet`, or `AmbiguousStructure`.
- Adds details, confidence, and recommendations (e.g., manual review for mixed structures).
- Use with `-UseConsensusHints` for deeper hints on ambiguous collections.

---

## Build and Apply a Consensus Plan

Preview a plan:
```powershell
New-MfcConsensusPlan -Path 'D:\Music' -Recurse -ShowProgress -Fast `
  | Format-Table Path, SuggestedFolderName, ProposedAlbum, ProposedYear
```

Apply (with guardrails, WhatIf):
```powershell
New-MfcConsensusPlan -Path 'D:\Music' -Recurse |
  Invoke-MfcConsensusPlan -WhatIf -Verbose
```

- `Invoke-MfcConsensusPlan` respects guardrails and updates AlbumArtist/Album/Year, and can rename folders when asked (`-Rename`).
- For collection roots, pass `-AllowCollectionChanges` intentionally.

---

## Moving and Folder Organization

`Update-MusicFolderMetadata` can optionally move files after tagging.

```powershell
Update-MusicFolderMetadata -FolderPath 'D:\Album' -Move -DestinationFolder 'D:\_Organized' -WhatIf
```

- Default folder structure: `Artist\Year - Album\[Disc]\Track - Title.ext`.
- Disc subfolders are used only when discs > 1 are detected.
- Filename strategy: If not specified, a filename quality analysis suggests preserving or renaming.
  - Override with `-PreserveFilenames` or set default via `-DefaultPreserveFilenames`.
- Conflict handling: `-OnConflict Skip|Overwrite|Merge`.

---

## Discogs Integration (Optional)

Find candidates for a folder:
```powershell
Find-MfcDiscogsMatch -Path 'D:\Artist\1997 - Album' -OpenInBrowser
```

Plan across a library with Discogs-derived proposals:
```powershell
New-MfcDiscogsPlan -Path 'D:\Music' -Recurse -ShowProgress |
  Format-Table Path, ReleaseId, ProposedAlbumArtist, ProposedAlbum, ProposedYear, Confidence
```

Apply Discogs plan (tags only), with optional per-track fields:
```powershell
New-MfcDiscogsPlan -Path 'D:\Music' -Recurse |
  Invoke-MfcDiscogsPlan -Tracks -WhatIf -Verbose
```

Per-track apply directly to a folder:
```powershell
Set-TrackTagsFromDiscogs -Path 'D:\Artist\1997 - Album' -ReleaseId 123456 `
  -MatchBy Number -WhatIf -Verbose
```

- Match strategies:
  - `Number`: pair by Disc/Track numbers (fallback to filename order for unnumbered files).
  - `Order`: pair purely by order (filename sort vs. track order).
- Count mismatches:
  - Only the first `min(localFiles, discogsTracks)` pairs are updated; extras are skipped.
  - Missing disc groups are skipped with a Verbose note; summary reports updates/skips.
- Optional duration validation (no length is written):
  - `-ValidateLength [-LengthToleranceSec 2] [-StrictLength]` checks file duration vs. Discogs track seconds; logs mismatches.

---

## Interactive Session (Optional)

Run a guided session that streams a plan and lets you apply changes step-by-step:
```powershell
.\scripts\Start-MfcInteractiveSession.ps1 -RootPath 'D:\Music' -Recurse -ShowProgress
```
- Review per-folder proposals, choose actions (apply, edit, rename-only, tags-only, move, skip).
- Supports Discogs exploration, WhatIf previews, and session state resume.

---

## Logging and Post-Processing

- Structured JSONL logs via `-LogPath` on apply commands.
- Summarize logs:
```powershell
Get-MfcLogSummary -LogPath '.\mfc_run.jsonl'
```
- Filter entries:
```powershell
Get-Content '.\mfc_run.jsonl' | ConvertFrom-Json | Where-Object Level -eq 'Warning'
```

---

## Common Recipes

- Speedy sampling preview:
```powershell
New-MfcConsensusPlan -Path 'D:\Music' -Recurse -Fast -MaxFolders 200 -ShowProgress
```

- Exclude archives and scratch folders:
```powershell
New-MfcConsensusPlan -Path 'D:\Music' -Recurse `
  -ExcludeName '_Archive*','_Scratch*' -ExcludePath 'D:\Music\Various*'
```

- Only rename, no tag changes:
```powershell
New-MfcConsensusPlan -Path 'D:\Music' -Recurse |
  Invoke-MfcConsensusPlan -Rename -WhatIf
```

- Apply to BoxSets/Artist roots (intentional):
```powershell
New-MfcConsensusPlan -Path 'D:\BoxSets' -Recurse |
  Invoke-MfcConsensusPlan -AllowCollectionChanges -WhatIf
```

---

## Troubleshooting

- TagLib-Sharp not found:
  - Place a compatible DLL in `lib\` (loader probes common filenames) or run `scripts\Install-TagLibSharp.ps1`.
- Slow runs on large trees: add `-Fast`, limit with `-MaxFolders`, and use `-ExcludeName`/`-ExcludePath`.
- Nothing changes with `-WhatIf`:
  - That’s expected — `-WhatIf` previews; drop it to enact.
- “No tag changes for …” messages:
  - Your files already match proposed tags; moves can still proceed if `-Move` is specified.
- Collections blocked:
  - You’re at an `ArtistFolder`/`BoxSet` root. Use `-AllowCollectionChanges` if that’s intended.

---

## Safety Checklist

- Always start with `-WhatIf` and `-Verbose`.
- Keep a backup or use logs to generate revert scripts.
- Use exclusions for archives/special cases.
- Don’t mutate collection roots unless explicitly intended.

---

## Appendix: Command Reference (Quick)

- Structure:
  - `Get-FolderStructureAnalysis`
- Planning:
  - `New-MfcConsensusPlan`, `Invoke-MfcConsensusPlan`
  - `New-MfcDiscogsPlan`, `Invoke-MfcDiscogsPlan`
- Tagging and moving:
  - `Update-MusicFolderMetadata`
  - `Set-TrackTagsFromDiscogs`
- Utilities:
  - `Find-MfcDiscogsMatch`, `Get-MfcLogSummary`

---

If you want this guide expanded with deeper Discogs scoring, per-track rename strategy, or automation pipelines, open an issue with your specific scenario.
