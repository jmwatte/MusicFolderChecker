# Debug script for Music Folder Processing
# This script runs the same command as the launch configuration

Import-Module .\MusicFolderChecker.psm1 -Force

# Run the debug command
Find-BadMusicFolderStructure -FoldersToSkip "E:\_CorrectedMusic","E:\_test","E:\_testb" -StartingPath "E:" -LogTo "C:\temp\ELog.log"
(Get-MfcLogSummary -LogPath "C:\temp\ELog.log").Entries |
    Where-Object { $_.Status -eq "Good" } |
    Select-Object -First 20 |
    Update-MusicFolderMetadata -Move -SkipMode -DestinationFolder "E:\_CorrectedMusic" -PreserveFilenames -WhatIf