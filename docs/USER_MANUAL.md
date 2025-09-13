MusicFolderChecker - User Manual
===============================

Overview
--------
MusicFolderChecker is a comprehensive PowerShell module for validating, fixing, and organizing music album folders using embedded tag data. It supports interactive workflows, automated batch processing, structured logging, and seamless integration with music library management tools.

Quick Start
-----------
Import the module in PowerShell 7 (pwsh):

```powershell
Import-Module C:\Users\<you>\Documents\PowerShell\Modules\MusicFolderChecker\MusicFolderChecker.psm1
Get-Command -Module MusicFolderChecker
```

Core Functions
--------------

### Update-MusicFolderMetadata
**Main function** for processing music folders with metadata updates and optional relocation.

**Key Features:**
- Interactive or scripted metadata correction
- Skip mode with '\' keyword for postponing complex folders
- JSON metadata import/export for automation
- Automatic folder structure validation
- Optional file relocation with conflict handling

**Basic Usage:**
```powershell
# Interactive processing
Update-MusicFolderMetadata -FolderPath 'E:\Music\Artist\2020 - Album' -Interactive

# Scripted processing with move
Update-MusicFolderMetadata -FolderPath 'E:\Music\Artist\2020 - Album' -AlbumArtist 'Artist Name' -Album 'Album Title' -Year 2020 -Move -DestinationFolder 'E:\Processed'
```

**Parameters:**
- `-FolderPath`: Music folder(s) to process (mandatory, accepts pipeline)
- `-AlbumArtist`, `-Album`, `-Year`: Metadata values to apply
- `-Interactive`: Prompt for missing metadata values
- `-SkipMode`: Enable '\' option to postpone folders in interactive mode
- `-Move`: Move folders to destination after processing
- `-DestinationFolder`: Target directory for moved folders
- `-LogPath`: JSONL log file for audit trail
- `-MetadataJson`: Load metadata from JSON file
- `-OutputMetadataJson`: Save collected metadata to JSON
- `-OnConflict`: Handle move conflicts ('Skip', 'Overwrite', 'Merge')

### Find-BadMusicFolderStructure
Scans folder structures and validates against expected naming conventions.

**Expected Structure:**
```
ArtistName\YYYY - AlbumName\NN - TrackName.ext
ArtistName\YYYY - AlbumName\Disc X\NN - TrackName.ext
```

**Usage:**
```powershell
# Basic scan
Find-BadMusicFolderStructure -StartingPath 'E:\Music'

# Scan with folders to skip
Find-BadMusicFolderStructure -StartingPath 'E:\Music' -FoldersToSkip 'E:\Music\Various Artists','E:\Music\_Archive'

# Find only good folders
Find-BadMusicFolderStructure -StartingPath 'E:\Music' -Good
```

**Parameters:**
- `-StartingPath`: Root directory to scan (mandatory)
- `-Good`: Return only well-structured folders
- `-FoldersToSkip`: Paths to exclude (supports arrays and comma-separated strings)
- `-LogTo`: Save results to file (auto-generated if not specified)
- `-LogFormat`: 'JSON' or 'Text'
- `-Quiet`: Suppress console output
- `-AnalyzeStructure`: Enable enhanced semantic structure analysis with confidence scoring

### Enhanced Structure Analysis

**New Feature:** The `-AnalyzeStructure` parameter provides intelligent semantic analysis beyond simple pattern matching.

**Structure Types Detected:**
- **ArtistFolder**: `Artist/Album1, Artist/Album2` (no audio at artist level)
- **SimpleAlbum**: `Album/audiofiles` only
- **MixedAlbum**: ⚠️ `Album/audiofiles + Album/SubAlbum1` (AMBIGUOUS - needs review)
- **MultiDiscAlbum**: `Album/Disc1, Album/Disc2`
- **CompilationFolder**: `Various Artists/Artist1-Album`
- **AmbiguousStructure**: Can't determine - needs user review
- **NonMusicFolder**: No audio files found

**Usage:**
```powershell
# Enhanced analysis with structure detection
Find-BadMusicFolderStructure -StartingPath 'E:\Music' -AnalyzeStructure

# Combined with exclusions
Find-BadMusicFolderStructure -StartingPath 'E:\Music' -AnalyzeStructure -FoldersToSkip 'E:\Music\temp','E:\Music\backup'
```

**Analysis Results Include:**
- `StructureType`: Classified folder type
- `Confidence`: 0.0-1.0 confidence score
- `StructureDetails`: Analysis reasoning
- `Recommendations`: Suggested processing actions
- `Metadata`: Detailed folder statistics

### Get-MusicFolderStructureSummary

Provides comprehensive summaries of structure analysis results with beautiful reporting.

**Usage:**
```powershell
# Get analysis results and create summary
$results = Find-BadMusicFolderStructure -StartingPath 'E:\Music' -AnalyzeStructure
Get-MusicFolderStructureSummary -AnalysisResults $results

# Filter from summary (post-analysis exclusion)
Get-MusicFolderStructureSummary -AnalysisResults $results -ExcludePatterns '*temp*','*backup*'

# Different output formats
Get-MusicFolderStructureSummary -AnalysisResults $results -OutputFormat JSON
```

**Parameters:**
- `-AnalysisResults`: Results from Find-BadMusicFolderStructure -AnalyzeStructure (mandatory, accepts pipeline)
- `-OutputFormat`: 'Table', 'List', or 'JSON'
- `-ExcludePatterns`: Wildcard patterns to exclude from summary

**Sample Output:**
```
🎵 Music Folder Structure Analysis Summary
========================================

📊 Overall Statistics:
  Total folders analyzed: 150
  High confidence (>80%): 120
  Needs manual review: 5

📁 Structure Breakdown:
  ArtistFolder: 45 folders (avg confidence: 0.85)
    Examples: Radiohead, Nirvana, Tool
  MixedAlbum: 5 folders (avg confidence: 0.3)
    Examples: Compilations, Live Shows
  SimpleAlbum: 95 folders (avg confidence: 0.82)
    Examples: 1997 - OK Computer, 1991 - Nevermind

⚠️ Cases Needing Review:
  Compilations - MixedAlbum (0.3)
  Live Shows - MixedAlbum (0.3)
```

### Save-TagsFromGoodMusicFolders
Extracts metadata from folder names and applies it to audio file tags.

**Usage:**
```powershell
# Process single folder
Save-TagsFromGoodMusicFolders -FolderPath 'E:\Music\Artist\2020 - Album'

# Process multiple folders
Find-BadMusicFolderStructure -StartingPath 'E:\Music' -Good | Save-TagsFromGoodMusicFolders
```

**Parameters:**
- `-FolderPath`: Folder to process (accepts pipeline)
- `-LogTo`: Save processing results
- `-FoldersToSkip`: Paths to exclude
- `-Quiet`: Suppress output
- `-hideTags`: Hide detailed tag information

### Move-GoodFolders
Moves validated folders to destination with proper artist/album organization.

**Usage:**
```powershell
# Move single folder
Move-GoodFolders -FolderPath 'E:\Temp\GoodAlbum' -DestinationFolder 'E:\Music'

# Move from scan results
Find-BadMusicFolderStructure -StartingPath 'E:\Temp' -Good | Move-GoodFolders -DestinationFolder 'E:\Music'
```

**Parameters:**
- `-FolderPath`: Folder to move (accepts pipeline)
- `-DestinationFolder`: Target directory
- `-DuplicateAction`: Handle conflicts ('Rename', 'Skip', 'Overwrite')
- `-Quiet`: Suppress output

### Import-LoggedFolders
Processes folders listed in log files with tagging and optional relocation.

**Usage:**
```powershell
# Process from JSON log
Import-LoggedFolders -LogFile 'C:\Temp\scan_results.json' -DestinationFolder 'E:\Processed'

# Process specific status
Import-LoggedFolders -LogFile 'C:\Temp\scan_results.json' -Status 'CheckThisGoodOne' -MaxItems 5
```

**Parameters:**
- `-LogFile`: Log file to process (mandatory)
- `-Status`: Filter by status ('Good', 'Bad', 'CheckThisGoodOne', 'All')
- `-DestinationFolder`: Target for moved folders
- `-MaxItems`: Limit number of folders to process
- `-DuplicateAction`: Handle conflicts

### Merge-AlbumInArtistFolder
Organizes album folders into artist subfolders based on metadata.

**Usage:**
```powershell
# Merge single album
Merge-AlbumInArtistFolder -FolderPath 'E:\Temp\Album1' -DestinationFolder 'E:\Music'

# Merge multiple albums
Get-ChildItem 'E:\Unsorted' -Directory | Merge-AlbumInArtistFolder -DestinationFolder 'E:\Music'
```

**Parameters:**
- `-FolderPath`: Album folder to merge (accepts pipeline)
- `-DestinationFolder`: Root destination directory
- `-DuplicateAction`: Handle conflicts

### Get-MfcLogSummary
Analyzes JSONL log files and provides statistical summaries.

**Usage:**
```powershell
# Basic summary
Get-MfcLogSummary -LogPath 'C:\Temp\mfc_run.jsonl'

# Filter by issue type
Get-MfcLogSummary -LogPath 'C:\Temp\mfc_run.jsonl' -FilterIssueType 'MissingYear'

# Export as JSON
Get-MfcLogSummary -LogPath 'C:\Temp\mfc_run.jsonl' -Output JSON
```

**Parameters:**
- `-LogPath`: Log file to analyze (mandatory)
- `-FilterIssueType`: Filter by specific issue type
- `-FilterLevel`: Filter by log level ('Info', 'Warning', 'Error')
- `-Output`: Format ('Table', 'JSON', 'CSV')

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
Find-BadMusicFolderStructure -StartingPath 'E:\Music' -FoldersToSkip 'E:\_CorrectedMusic','E:\_test' |
    Where-Object { $_.IsValid -eq $false } |
    Select-Object -First 20
```

#### Enhanced Structure Analysis:
```powershell
# Analyze folder structures with confidence scoring
Find-BadMusicFolderStructure -StartingPath 'E:\Music' -AnalyzeStructure -FoldersToSkip 'E:\_CorrectedMusic' |
    Get-MusicFolderStructureSummary -Output Table

# Get detailed analysis for ambiguous structures
Find-BadMusicFolderStructure -StartingPath 'E:\Music' -AnalyzeStructure |
    Where-Object { $_.StructureType -eq 'AmbiguousStructure' } |
    Get-MusicFolderStructureSummary -Output List -ExcludePatterns '*Compilation*'
```

#### Interactive Preview:
```powershell
# Interactive processing with skip option
Find-BadMusicFolderStructure -StartingPath 'E:\Music' -FoldersToSkip 'E:\_CorrectedMusic' |
    Update-MusicFolderMetadata -Interactive -DestinationFolder 'E:\_CorrectedMusic' -Move -WhatIf
```
*Note: Use '\' to postpone complex folders (short and unlikely to conflict with album names)*

#### Metadata Collection:
```powershell
# Collect metadata for automation
Find-BadMusicFolderStructure -StartingPath 'E:\Music' -FoldersToSkip 'E:\_CorrectedMusic' |
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
✅ **Skip Functionality:** Interactive prompts accept '\' input
✅ **FoldersToSkip Processing:** Supports comma-separated strings and arrays
✅ **Subtree Skipping:** Entire folder hierarchies are excluded when parent is in folders to skip
✅ **JSON Export/Import:** Metadata collection and automated processing work seamlessly
✅ **Enhanced Structure Analysis:** -AnalyzeStructure parameter provides semantic classification with confidence scoring
✅ **Structure Type Detection:** Correctly identifies ArtistFolder, SimpleAlbum, MixedAlbum, MultiDiscAlbum, CompilationFolder, AmbiguousStructure, NonMusicFolder
✅ **Confidence Scoring:** Provides reliable certainty metrics (0.0-1.0) for all classifications
✅ **Report Filtering:** -ExcludePatterns works at report-time for Get-MusicFolderStructureSummary
✅ **Multiple Output Formats:** Table, List, and JSON formats work correctly for structure summaries

### Processing order and moving behavior

When you run `Update-MusicFolderMetadata` and request a move, the module will move the files and folders it has identified for that album. That means:

- If you run the command against a parent folder that contains subfolders with audio, moving the parent will also move those subfolders and their contents to the destination. After the move, the original subpaths will no longer be available at their original locations.
- If you only update tags and do not move (no `-Move`), the files remain in place and you can later run processing on their subfolders.

Best practice: process deepest folders first

- Run `Find-BadMusicFolderStructure` once and save a JSONL log. Then process folders sorted by path depth (deepest first). This ensures you correct and move children (e.g., Disc 1, Extras) before their parent album folders are moved.

Example: process deepest-first (interactive preview)

```powershell
Get-Content 'E:\scan_results.json' | ConvertFrom-Json |
  Sort-Object @{ Expression = { ($_ .Path -split '\\').Count } } -Descending |
  ForEach-Object { $_.Path | Update-MusicFolderMetadata -Interactive -SkipMode -WhatIf }
```

When to use `-WhatIf` and `-SkipMode`

- Use `-WhatIf` for a full dry-run so you can verify intended destination paths and detect collisions.
- Use `-SkipMode` and enter `\` to postpone complex cases; they remain in the log and can be revisited.

Batching and metadata export/import

- You can collect corrected metadata during interactive passes with `-OutputMetadataJson` and later apply it non-interactively using `-MetadataJson` and `-Move`. This avoids re-opening the same folders interactively multiple times.

Example: collect metadata then apply it

```powershell
# Collect metadata interactively (safe preview)
Get-Content 'E:\scan_results.json' | ConvertFrom-Json | Select-Object -First 20 | ForEach-Object { $_.Path } |
  Update-MusicFolderMetadata -Interactive -SkipMode -OutputMetadataJson 'E:\collected.json' -WhatIf

# Later, apply the collected metadata and move
Update-MusicFolderMetadata -MetadataJson 'E:\collected.json' -Move -DestinationFolder 'E:\_Processed'
```

Notes and caveats

- Multi-disc and nested structures: treat disc subfolders and deeply nested albums first.
- Moving a parent folder is usually atomic: it removes the original folder and moves everything beneath it. If you rely on processing children later, process children first.
- If a folder contains a single music file and several subfolders with other music, decide whether the parent is really the album (move whole parent) or the children are separate albums (process children first or skip parent until children are done).
- Always preview with `-WhatIf` before committing large batches.

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