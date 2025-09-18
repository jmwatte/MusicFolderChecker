# MusicFolderChecker PowerShell Module

A comprehensive PowerShell module for validating, fixing, and organizing music album folders using embedded tag data. Supports interactive workflows, automated batch processing, structured logging, and seamless integration with music library management tools.

## Features

- **Interactive & Scripted Processing**: Choose between guided prompts or automated workflows
- **Intelligent Filename Analysis**: Automatically determines whether to preserve or rename filenames based on quality analysis
- **Metadata Correction**: Update album artist, album title, and release year tags
- **Smart File Organization**: Moves files to structured destination with proper artist/album hierarchy
- **Conflict Resolution**: Handles duplicate albums and file conflicts gracefully
- **Structured Logging**: JSONL logging for audit trails and troubleshooting
- **Skip Mode**: Postpone complex folders for later manual review
- **Pipeline Support**: Works seamlessly with PowerShell pipelines
- **WhatIf Support**: Safe preview of all operations before execution

## Dependencies
- TagLib-Sharp.dll (included in lib/ directory)
- PowerShell 7.0+ recommended (supports PowerShell 5.1)

## Installation
1. Clone this repository
2. Copy the module to your PowerShell modules directory
3. Import: `Import-Module MusicFolderChecker`

## Quick Start

### Interactive Processing
```powershell
# Process folders interactively with intelligent defaults
Update-MusicFolderMetadata -FolderPath 'E:\Music\Artist\2020 - Album' -Interactive -Move -DestinationFolder 'E:\Processed'
```

### Automated Processing
```powershell
# Update metadata and move with specific values
Update-MusicFolderMetadata -FolderPath 'E:\Music\Artist\2020 - Album' -AlbumArtist 'Artist Name' -Album 'Album Title' -Year 2020 -Move -DestinationFolder 'E:\Processed'
```

### Batch Processing with Pipeline
```powershell
# Find and process multiple folders
Find-BadMusicFolderStructure -StartingPath 'E:\Music' -Good | Update-MusicFolderMetadata -Interactive -SkipMode -Move -DestinationFolder 'E:\Processed' -WhatIf
```

## Core Functions

### Update-MusicFolderMetadata (Main Function)
**Primary function** for processing music folders with metadata updates and optional relocation.

**Key Features:**
- Interactive or scripted metadata correction
- Skip mode with '\' keyword for postponing complex folders
- Intelligent filename analysis and preservation recommendations
- JSON metadata import/export for automation
- Automatic folder structure validation
- Optional file relocation with conflict handling
- Comprehensive track number detection (01, 001, (01), [01], etc.)

**Parameters:**
- `-FolderPath`: Music folder(s) to process (mandatory, accepts pipeline)
- `-AlbumArtist`, `-Album`, `-Year`: Metadata values to apply
- `-Interactive`: Prompt for missing metadata values
- `-SkipMode`: Enable '\' option to postpone folders in interactive mode
- `-Move`: Move folders to destination after processing
- `-DestinationFolder`: Target directory for moved folders
- `-PreserveFilenames`: Preserve original filenames during move
- `-DefaultPreserveFilenames`: Set default for filename preservation in interactive mode
- `-LogPath`: JSONL log file for audit trail
- `-MetadataJson`: Load metadata from JSON file
- `-OutputMetadataJson`: Save collected metadata to JSON
- `-OnConflict`: Handle move conflicts ('Skip', 'Overwrite', 'Merge')

### Find-BadMusicFolderStructure
Scans folder structures and validates against expected naming conventions.

**Enhanced Analysis Features:**
- Semantic structure classification (ArtistFolder, SimpleAlbum, MixedAlbum, etc.)
- Confidence scoring for all classifications
- Pattern consistency analysis
- Comprehensive track number detection

### Get-MusicFolderStructureSummary
Provides comprehensive summaries of structure analysis results with beautiful reporting.

### Other Functions
- `Save-TagsFromGoodMusicFolders`: Extracts metadata from folder names and applies to audio files
- `Move-GoodFolders`: Moves validated folders to destination with proper organization
- `Import-LoggedFolders`: Processes folders from log files with tagging and optional relocation
- `Merge-AlbumInArtistFolder`: Organizes album folders into artist subfolders
- `Get-MfcLogSummary`: Analyzes JSONL log files and provides statistical summaries

## Guides

- Order in Your Music — Beginner → Advanced: `docs/ORDER_IN_YOUR_MUSIC.md`

## Usage Examples

### Basic Interactive Processing
```powershell
Update-MusicFolderMetadata -FolderPath 'E:\Music\Artist\2020 - Album' -Interactive
```

### Full Processing with Move
```powershell
Update-MusicFolderMetadata -FolderPath 'E:\Music\Artist\2020 - Album' -AlbumArtist 'Artist Name' -Album 'Album Title' -Year 2020 -Move -DestinationFolder 'E:\Processed'
```

### Batch Processing from Structure Analysis
```powershell
Find-BadMusicFolderStructure -StartingPath 'E:\Music' -AnalyzeStructure |
    Get-MusicFolderStructureSummary -OutputFormat Table

# Process good folders interactively
Find-BadMusicFolderStructure -StartingPath 'E:\Music' -Good |
    Update-MusicFolderMetadata -Interactive -SkipMode -Move -DestinationFolder 'E:\Processed' -WhatIf
```

### Compilation Album Processing
```powershell
Update-MusicFolderMetadata -FolderPath 'E:\Music\Compilations\Various Artists - 2020 Hits' -AlbumArtist 'Various Artists' -PreserveTrackArtists
```

### Filename Preservation Control
```powershell
# Preserve original filenames during move
Update-MusicFolderMetadata -FolderPath 'E:\Music\Artist\2020 - Album' -Interactive -Move -DestinationFolder 'E:\Processed' -PreserveFilenames

# Set default to preserve in interactive mode
Update-MusicFolderMetadata -FolderPath 'E:\Music\Artist\2020 - Album' -Interactive -Move -DestinationFolder 'E:\Processed' -DefaultPreserveFilenames:$true
```

### Metadata Collection and Automation
```powershell
# Collect metadata interactively
Update-MusicFolderMetadata -FolderPath 'E:\Music\Artist\2020 - Album' -Interactive -OutputMetadataJson 'C:\Temp\metadata.json'

# Apply collected metadata later
Update-MusicFolderMetadata -MetadataJson 'C:\Temp\metadata.json' -Move -DestinationFolder 'E:\Processed'
```

### Log Analysis
```powershell
# Analyze processing logs
Get-MfcLogSummary -LogPath 'C:\Temp\mfc_run.jsonl'

# Filter log entries
Get-Content 'C:\Temp\mfc_run.jsonl' | ConvertFrom-Json | Where-Object { $_.IssueType -eq 'MissingYear' }
```

## Folder Organization

Files are organized in the destination as:
```
ArtistName\Year - AlbumName\[Disc X]\NN - TrackTitle.ext
```

**Features:**
- Disc subfolders created only when multiple disc numbers detected
- Duplicate albums handled with numbered suffixes (Album (2), Album (3), etc.)
- Non-audio files (artwork, cues, logs) preserved alongside audio files
- Relative references maintained for cue sheets and artwork

## Intelligent Filename Analysis

The module includes sophisticated filename quality analysis that:

- **Detects track numbers** in multiple formats: `01`, `001`, `(01)`, `[01]`, `1-`, `01_`, etc.
- **Analyzes pattern consistency** across all files in an album
- **Considers filename length** and variance
- **Provides confidence scores** for recommendations
- **Automatically suggests** preserve vs. rename based on quality metrics

**Analysis Results Include:**
- Pattern consistency ratio
- Track number detection ratio
- Filename length statistics
- Confidence score and reasoning
- Clear preserve/rename recommendation

## Structured Logging

All operations can be logged to JSONL format for audit and troubleshooting:

```powershell
Update-MusicFolderMetadata -FolderPath 'E:\Music' -Interactive -Move -DestinationFolder 'E:\Processed' -LogPath 'C:\Temp\mfc_run.jsonl'
```

**Log Schema:**
- `Timestamp`: ISO 8601 timestamp
- `Function`: Source function name
- `Level`: Info, Warning, Error
- `Status`: Start, UpdatedTags, Moved, Issue, etc.
- `IssueType`: MissingYear, MissingAlbumArtist, InvalidTrackNumber, etc.
- `Path`, `File`, `Destination`: File system paths
- `Details`: Additional context as object

## Best Practices

### Always Preview First
```powershell
# Use -WhatIf for safe preview
Update-MusicFolderMetadata -FolderPath 'E:\Music' -Interactive -Move -DestinationFolder 'E:\Processed' -WhatIf
```

### Process Deepest Folders First
For nested structures, process child folders before parents to avoid conflicts.

### Use Skip Mode for Complex Cases
```powershell
Update-MusicFolderMetadata -FolderPath 'E:\Music' -Interactive -SkipMode -Move -DestinationFolder 'E:\Processed'
# Enter '\' during prompts to postpone complex folders
```

### Leverage Metadata Export/Import
```powershell
# Collect metadata interactively
Update-MusicFolderMetadata -Interactive -OutputMetadataJson 'C:\Temp\metadata.json' -SkipMode

# Apply later non-interactively
Update-MusicFolderMetadata -MetadataJson 'C:\Temp\metadata.json' -Move -DestinationFolder 'E:\Processed'
```

## Testing & Validation

The module includes comprehensive Pester tests covering:
- Pipeline input handling
- Parameter binding and validation
- Interactive prompt behavior
- File operation safety
- Error handling and edge cases

Run tests:
```powershell
Invoke-Pester -Script .\tests -OutputFormat NUnitXml -OutputFile .\test-results.xml
```

## License
This module includes TagLib-Sharp.dll, which is licensed under LGPL 2.1. See the [LICENSE](LICENSE) file for full details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## Support

For issues, questions, or feature requests:
1. Check the [USER_MANUAL.md](docs/USER_MANUAL.md) for detailed usage instructions
2. Review existing issues on GitHub
3. Create a new issue with detailed information about your problem or request