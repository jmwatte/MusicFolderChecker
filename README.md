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

When using `Import-LoggedFolders`, you may notice duplicate "🔍 Checking folder" and "✅ Measurement complete" messages for the same folder. This is **normal behavior** and occurs because the function performs layered validation for safety:

1. **First validation**: Before tagging files, the folder structure is checked
2. **Second validation**: Before moving folders, the structure is checked again

This double-checking ensures data integrity by catching any changes that might occur between the tagging and moving operations. The messages appear twice because the same validation function (`Find-BadMusicFolderStructure`) is called at two different stages of the process.

**This is not an error** - it's a safety feature designed to prevent processing corrupted or modified folders.

## License
This module includes TagLib-Sharp.dll, which is licensed under LGPL 2.1. See the [LICENSE](LICENSE) file for full details.