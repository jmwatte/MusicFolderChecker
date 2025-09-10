# MusicFolderChecker PowerShell Module

This module checks music folder structures and tags audio files.

## Dependencies
- TagLib-Sharp.dll (included in lib/ directory)

## Installation
1. Clone this repository
2. Copy the module to your PowerShell modules directory
3. Import: `Import-Module MusicFolderChecker`

## Functions

### Find-BadMusicFolderStructure
Validates music folder structures against expected patterns.

### Save-TagsFromGoodMusicFolders
Tags audio files in folders that pass structure validation.

### Move-GoodFolders
Moves validated music folders to a destination directory.

### Import-LoggedFolders
Processes folders from a log file by tagging and moving them.

## Usage Examples

### Basic Folder Validation
```powershell
Find-BadMusicFolderStructure -StartingPath "E:\Music" -Good
```

### Tag and Move Folders
```powershell
Save-TagsFromGoodMusicFolders -FolderPath "E:\Music\Artist\1992 - Album" | Move-GoodFolders -DestinationFolder "E:\Processed"
```

### Process Logged Folders
```powershell
Import-LoggedFolders -LogFile "C:\Logs\structure.json" -DestinationFolder "E:\CorrectedMusic" -WhatIf
```

## Important Notes

### Duplicate Validation Messages

When using `Import-LoggedFolders`, you may notice duplicate "🔍 Checking folder" and "✅ Measurement complete"
messages for the same folder. This is **normal behavior** - the function performs layered
validation for safety by checking folder structure both before tagging AND before moving.
This double-checking ensures data integrity and is not an error.

### Detailed Error Messages

The module now provides specific, user-friendly messages for different failure scenarios:

- **Empty folder**: "ℹ️ Skipping empty folder: [path]"
- **No music files**: "ℹ️ No music files found in: [path]"
- **Corrupted files**: "Corrupted audio file in: [path] - [details]"
- **Bad structure**: "ℹ️ Folder structure doesn't match expected pattern: [path]"
- **Blacklisted**: "🚫 Skipping blacklisted folder: [path]"

### Detailed Logging

Use the `-DetailedLog` parameter with `-WhatIf` for verbose logging during dry runs:

```powershell
Import-LoggedFolders -LogFile "C:\Logs\structure.json" -DestinationFolder "E:\CorrectedMusic" -DetailedLog -WhatIf
```

This shows specific validation results for each folder without cluttering normal operation output.

## License
This module includes TagLib-Sharp.dll, which is licensed under LGPL 2.1. See the [LICENSE](LICENSE) file for full details.