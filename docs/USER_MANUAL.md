MusicFolderChecker - User Manual
===============================

Overview
--------
MusicFolderChecker is a PowerShell module to validate, fix, and relocate music album folders using embedded tag data. It supports interactive and scripted workflows, automatic folder normalization, and structured JSON logging for dry-runs and audit.

Quick start
-----------
Import the module in PowerShell 7 (pwsh):

```powershell
Import-Module C:\Users\<you>\Documents\PowerShell\Modules\MusicFolderChecker\MusicFolderChecker.psm1
Get-Command -Module MusicFolderChecker
```

Main function
-------------
`Update-MusicFolderMetadata` — inspects/updates album-level tags and optionally moves files to a destination folder with a consistent structure.

Basic usage:

```powershell
# Interactive: prompts per folder
Get-ChildItem -Directory C:\Music\ToFix | Update-MusicFolderMetadata -Interactive -DestinationFolder D:\CorrectedMusic -Move -LogPath C:\Temp\mfc_run.jsonl -WhatIf

# Non-interactive: set album-level values and move
Update-MusicFolderMetadata -FolderPath 'E:\Temp\Album1' -AlbumArtist 'Various' -Album 'New Album' -Year 2020 -Move -DestinationFolder D:\Music -LogPath C:\Temp\mfc_run.jsonl
```

Folder naming pattern
---------------------
By default files are moved into:

```
AlbumArtist\Year - Album\[Disc X]\NN - Title.ext
```

Disc subfolders are created only when the files in a folder contain multiple disc numbers or a disc number greater than 1. If only `Disc=1` (or no disc tags) are present, no disc subfolder is used.

Album duplicates
----------------
If a target album folder already exists, the module creates a numbered sibling: `Album (2)`, `Album (3)`, etc. This avoids destructive merges — the user can inspect duplicates later.

Structured logging
------------------
Use `-LogPath` to write newline-delimited JSON (JSONL) log entries which can be quickly filtered or parsed.

Example: list folders with missing year

```powershell
Get-Content C:\Temp\mfc_run.jsonl | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.IssueType -eq 'MissingYear' }
```

Log schema highlights
- `Timestamp`: ISO 8601
- `Function`: source function name (e.g., `Update-MusicFolderMetadata`)
- `Level`: `Info`, `Warning`, `Error`
- `Status`: `Start`, `UpdatedTags`, `WillMove`, `Moved`, `MoveFailed`, `Issue`
- `IssueType`: e.g., `MissingYear`, `MissingAlbumArtist`, `InvalidTrackNumber`
- `Path`, `File`, `Destination`, `Details` (object with specifics)

Problem 4: Complex Folder Structures
-----------------------------------
**Issue:** Some folders may have unusual structures requiring manual review

**Solution:** Skip mode allows deferring complex cases for later manual handling

### 📋 Workflow Recommendations

#### Discovery Phase:
```powershell
# Find folders with structural issues
Find-BadMusicFolderStructure -StartingPath 'E:\Music' -Blacklist 'E:\_CorrectedMusic','E:\_test' | 
    Where-Object { $_.IsValid -eq $false } | 
    Select-Object -First 20
```

#### Interactive Preview:
```powershell
# Interactive processing with skip option
Find-BadMusicFolderStructure -StartingPath 'E:\Music' -Blacklist 'E:\_CorrectedMusic' | 
    Update-MusicFolderMetadata -Interactive -DestinationFolder 'E:\_CorrectedMusic' -Move -WhatIf
```

#### Metadata Collection:
```powershell
# Collect metadata for automation
Find-BadMusicFolderStructure -StartingPath 'E:\Music' -Blacklist 'E:\_CorrectedMusic' | 
    Update-MusicFolderMetadata -Interactive -OutputMetadataJson 'C:\Temp\collected_metadata.json' -SkipMode
```

#### Automated Processing:
```powershell
# Process using collected metadata
Update-MusicFolderMetadata -InputMetadataJson 'C:\Temp\collected_metadata.json' -DestinationFolder 'E:\_CorrectedMusic' -Move -LogPath 'C:\Temp\automation_run.jsonl'
```

### 🔍 Testing Results
✅ **Pipeline Input:** Successfully accepts objects with Path property  
✅ **Parameter Binding:** Path alias works correctly  
✅ **Metadata Loading:** JSON metadata loads and applies automatically  
✅ **Skip Functionality:** Interactive prompts accept 'skip' input  
✅ **Blacklist Processing:** Supports comma-separated strings and arrays  
✅ **Subtree Skipping:** Entire folder hierarchies are excluded when parent is blacklisted  
✅ **JSON Export/Import:** Metadata collection and automated processing work seamlessly  

Utilities
---------
`Get-MfcLogSummary -LogPath <path>` summarizes the JSONL log and provides counts by issue type and level.

Tips & troubleshooting
----------------------
- Always run with `-WhatIf` first to preview moves. Use `-LogPath` to capture dry-run diagnostics.
- If a folder contains files with malformed track or disc tags (e.g., non-numeric), the module treats them as missing and logs `InvalidTrackNumber` or omits disc subfolders (unless other files indicate discs >1).
- To force disc subfolders regardless of tags, you can request a `-ForceDiscFolder` option (not implemented yet) — request it if desired.
- For very large libraries, log file sizes may grow; use `jq` or PowerShell to filter JSONL lines.

Extending / Development notes
-----------------------------
- Logger helper: `src/Private/Write-StructuredLog.ps1` (JSONL output).
- Summary: `src/Public/Get-MfcLogSummary.ps1`.
- Tests: Pester tests are in `tests/` and were run successfully.

Questions or changes
--------------------
Tell me which additional reports you'd like (CSV export, HTML report, or a `--dryrun-summary` command) and I can add them.
