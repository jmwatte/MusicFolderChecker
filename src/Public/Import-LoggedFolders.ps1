<#
.SYNOPSIS
    Imports and processes music folders from a log file by tagging and moving them.
#>
function Import-LoggedFolders {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [string]$LogFile,

        [Parameter()]
        [ValidateSet('Good', 'Bad', 'CheckThisGoodOne', 'All')]
        [string]$Status = 'Good',

        [Parameter(Mandatory)]
        [string]$DestinationFolder,

        [Parameter()]
        [int]$MaxItems,

        [Parameter()]
        [ValidateSet('Auto', 'JSON', 'Text')]
        [string]$LogFormat = 'Auto',

        [switch]$Quiet,

        [switch]$hideTags,

        [switch]$DetailedLog,  # New parameter for detailed logging during dry runs

        [Parameter()]
        [ValidateSet('Overwrite', 'Skip', 'Rename')]
        [string]$DuplicateAction = 'Rename'
    )

    # Validate log file exists
    if (-not (Test-Path $LogFile)) {
        throw "Log file not found: $LogFile"
    }

    # Read and parse log file
    try {
        $logContent = Get-Content -Path $LogFile -Raw

        if ($LogFormat -eq 'Auto') {
            # Try to detect format
            if ($logContent.TrimStart().StartsWith('{')) {
                $LogFormat = 'JSON'
            } else {
                $LogFormat = 'Text'
            }
        }

        if ($LogFormat -eq 'JSON') {
            # Parse JSON (one object per line)
            $logEntries = $logContent -split "`n" | Where-Object { $_ -match '\S' } | ForEach-Object {
                try {
                    $_ | ConvertFrom-Json
                } catch {
                    Write-Host "WARNING: Skipping malformed JSON line: $_" -ForegroundColor Red
                    $null
                }
            } | Where-Object { $_ -ne $null }
        } else {
            # Parse text format
            $logEntries = $logContent -split "`n" | Where-Object { $_ -match '\S' } | ForEach-Object {
                $line = $_.Trim()
                if ($line -match '^(GoodFolder|BadFolder|CheckThisGoodOne)\s+(.+)$') {
                    [PSCustomObject]@{
                        Status = if ($matches[1] -eq 'GoodFolder') { 'Good' } elseif ($matches[1] -eq 'CheckThisGoodOne') { 'CheckThisGoodOne' } else { 'Bad' }
                        Path = $matches[2]
                        Function = 'Find-BadMusicFolderStructure'
                        Type = if ($matches[1] -eq 'GoodFolder' -or $matches[1] -eq 'CheckThisGoodOne') { 'ArtistFolder' } else { 'AlbumFolder' }
                    }
                } elseif ($line -match '^GoodFolder\s+(.+)$') {
                    # Handle lines that might have extra spaces or formatting issues
                    [PSCustomObject]@{
                        Status = 'Good'
                        Path = $matches[1]
                        Function = 'Find-BadMusicFolderStructure'
                        Type = 'ArtistFolder'
                    }
                } else {
                    if (-not $Quiet -and $line -notmatch '^\s*$') {
                        Write-Host "WARNING: Skipping malformed text line: '$line'" -ForegroundColor Red
                    }
                    $null
                }
            } | Where-Object { $_ -ne $null }
        }
    }
    catch {
        throw "Failed to read log file: $_"
    }

    # Filter entries by status
    if ($Status -ne 'All') {
        $logEntries = $logEntries | Where-Object { $_.Status -eq $Status }
    }

    # Limit number of items if specified
    if ($MaxItems -and $MaxItems -gt 0) {
        $logEntries = $logEntries | Select-Object -First $MaxItems
    }

    if (-not $logEntries -or $logEntries.Count -eq 0) {
        if (-not $Quiet) {
        Write-Host "No matching entries found in log file."
    }
        return
    }

    if (-not $Quiet) {
        Write-Host "Found $($logEntries.Count) folders to process..."
    }

    # Process each folder
    $processedCount = 0
    $processedEntries = @()
    foreach ($entry in $logEntries) {
        $folderPath = $entry.Path

        if (-not (Test-Path -LiteralPath $folderPath)) {
            Write-Host "WARNING: Folder not found, skipping: $folderPath" -ForegroundColor Red
            continue
        }

        if (-not $Quiet) {
            Write-Host "Processing: $folderPath"
        }

        try {
            # Check if this is an artist folder containing album subfolders
            $subfolders = Get-ChildItem -LiteralPath $folderPath -Directory -ErrorAction SilentlyContinue
            $albumSubfolders = @()
            foreach ($subfolder in $subfolders) {
                if ($subfolder.Name -match '^\d{4} - .+$') {
                    $albumSubfolders += $subfolder.FullName
                }
            }

            if ($albumSubfolders) {
                # This is an artist folder - process each album subfolder individually
                $allTaggedFolders = @()
                $allCorruptFiles = @{}
                
                foreach ($albumFolder in $albumSubfolders) {
                    if (-not $Quiet) {
                        Write-Host "Processing album: $albumFolder"
                    }
                    
                    $albumTaggingResult = Save-TagsFromGoodMusicFolders -FolderPath $albumFolder -WhatIf:$WhatIfPreference -Quiet:$Quiet -hideTags:$hideTags
                    $albumTaggedFolders = $albumTaggingResult.GoodFolders
                    $albumCorruptFiles = $albumTaggingResult.CorruptFiles
                    
                    if ($albumTaggedFolders) {
                        $allTaggedFolders += $albumTaggedFolders
                    }
                    
                    # Merge corrupt files
                    foreach ($key in $albumCorruptFiles.Keys) {
                        if (-not $allCorruptFiles.ContainsKey($key)) {
                            $allCorruptFiles[$key] = @()
                        }
                        $allCorruptFiles[$key] += $albumCorruptFiles[$key]
                    }
                }
                
                $taggedFolders = $allTaggedFolders
                $corruptFiles = $allCorruptFiles
            } else {
                # This is a single album folder - process normally
                $taggingResult = Save-TagsFromGoodMusicFolders -FolderPath $folderPath -WhatIf:$WhatIfPreference -Quiet:$Quiet -hideTags:$hideTags
                $taggedFolders = $taggingResult.GoodFolders
                $corruptFiles = $taggingResult.CorruptFiles
            }
            
            if (-not $Quiet) {
                Write-Host "DEBUG: taggedFolders result for $folderPath = '$($taggedFolders -join ', ')" -ForegroundColor Cyan
                if ($corruptFiles.ContainsKey($folderPath)) {
                    Write-Host "DEBUG: Found $($corruptFiles[$folderPath].Count) corrupt files in $folderPath" -ForegroundColor Yellow
                }
            }

            if ($taggedFolders) {
                # Move the successfully tagged folder(s)
                $taggedFolders | Move-GoodFolders -DestinationFolder $DestinationFolder -WhatIf:$WhatIfPreference -Quiet:$Quiet -DuplicateAction:$DuplicateAction
                
                # Create corrupt files log in destination if any corrupt files were found
                if ($corruptFiles.ContainsKey($folderPath) -and $corruptFiles[$folderPath].Count -gt 0 -and -not $WhatIfPreference) {
                    # Get the destination path for this folder
                    $destinationPath = Get-DestinationPath -SourcePath $folderPath -DestinationFolder $DestinationFolder
                    
                    if (Test-Path -LiteralPath $destinationPath) {
                        $corruptFilePath = Join-Path $destinationPath "CORRUPT_FILES.txt"
                        $corruptContent = @"
CORRUPT OR PROBLEMATIC FILES FOUND
==================================
Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Source Folder: $folderPath
Destination Folder: $destinationPath
Total files with issues: $($corruptFiles[$folderPath].Count)

DETAILS:
"@
                        foreach ($corruptFile in $corruptFiles[$folderPath]) {
                            # Convert source path to destination path for the corrupt file
                            $relativePath = $corruptFile.FilePath -replace [regex]::Escape($folderPath), ""
                            $destFilePath = Join-Path $destinationPath $relativePath.TrimStart('\\')
                            
                            $corruptContent += @"

FILE: $($destFilePath)
REASON: $($corruptFile.Reason)
ERROR: $($corruptFile.Error)
"@
                        }
                        
                        $corruptContent += @"

==================================
These files could not be processed automatically.
Please check and fix them manually before re-processing.
"@
                        
                        try {
                            $corruptContent | Out-File -FilePath $corruptFilePath -Encoding UTF8 -WhatIf:$false
                            if (-not $Quiet) {
                                Write-Host "📝 Created corrupt files log: $corruptFilePath" -ForegroundColor Yellow
                            }
                        }
                        catch {
                            Write-Host "WARNING: Failed to create corrupt files log: $_" -ForegroundColor Red
                        }
                    }
                }
                
                $processedCount++
                $processedEntries += $entry
                
                if ($DetailedLog -and $WhatIfPreference) {
                    Write-Host "📝 [DetailedLog] Successfully processed: $folderPath" -ForegroundColor Green
                }
            } else {
                # Save-TagsFromGoodMusicFolders already provided specific error messages
                # Only show generic message if DetailedLog is requested
                if (-not $Quiet) {
                    Write-Host "DEBUG: Entering CheckThisGoodOne marking block for $folderPath" -ForegroundColor Magenta
                }
                if ($DetailedLog) {
                    Write-Host "📝 [DetailedLog] No files processed in: $folderPath" -ForegroundColor Yellow
                }
                
                # Mark this entry as needing manual review by appending "CheckThisGoodOne" entry
                # and removing the original "GoodFolder" entry
                # Note: We do this even during -WhatIf since it's just updating the log file metadata
                try {
                    if (-not $Quiet) {
                        Write-Host "DEBUG: Starting log file update process" -ForegroundColor Magenta
                    }
                    
                    # First, remove the original "GoodFolder" entry
                    $updatedContent = $logContent
                    if ($LogFormat -eq 'JSON') {
                        # For JSON, find and remove the original entry
                        if (-not $Quiet) {
                            Write-Host "DEBUG: Removing original JSON entry for $folderPath" -ForegroundColor Cyan
                        }
                        $originalEntry = @{
                            Timestamp = $entry.Timestamp
                            Status = 'Good'
                            Path = $folderPath
                            Function = $entry.Function
                            Type = $entry.Type
                        } | ConvertTo-Json -Compress
                        $updatedContent = $updatedContent -replace [regex]::Escape("$originalEntry`r`n"), ""
                        $updatedContent = $updatedContent -replace [regex]::Escape("$originalEntry`n"), ""
                        $updatedContent = $updatedContent -replace [regex]::Escape($originalEntry), ""
                    } else {
                        # For text format, remove the original "GoodFolder" line
                        if (-not $Quiet) {
                            Write-Host "DEBUG: Removing original text entry for $folderPath" -ForegroundColor Cyan
                        }

                        # More robust line removal - split into lines, remove matching line, rejoin
                        $lines = $updatedContent -split "`n"
                        $targetLine = "GoodFolder $folderPath"
                        $lines = $lines | Where-Object {
                            $_.Trim() -ne $targetLine -and
                            $_.Trim() -ne "$targetLine`r" -and
                            $_ -ne $targetLine
                        }
                        $updatedContent = $lines -join "`n"
                    }
                    
                    # Write back the updated content (removing original entry)
                    if ($updatedContent.Trim() -ne $logContent.Trim()) {
                        [System.IO.File]::WriteAllText($LogFile, $updatedContent.Trim(), [System.Text.Encoding]::UTF8)
                        if (-not $Quiet) {
                            Write-Host "DEBUG: Removed original entry for $folderPath" -ForegroundColor Green
                        }
                    }
                    
                    # Then append the new CheckThisGoodOne entry
                    if ($LogFormat -eq 'JSON') {
                        # For JSON format, create a new CheckThisGoodOne entry
                        if (-not $Quiet) {
                            Write-Host "DEBUG: Appending CheckThisGoodOne JSON entry for $folderPath" -ForegroundColor Cyan
                        }
                        $checkThisEntry = @{
                            Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                            Status = 'CheckThisGoodOne'
                            Path = $folderPath
                            Function = 'Import-LoggedFolders'
                            Type = 'ArtistFolder'
                        } | ConvertTo-Json -Compress
                        Write-LogEntry -Path $LogFile -Value "$checkThisEntry`r`n"
                    } else {
                        # For text format, append the CheckThisGoodOne entry
                        if (-not $Quiet) {
                            Write-Host "DEBUG: Appending CheckThisGoodOne text entry for $folderPath" -ForegroundColor Cyan
                        }
                        Write-LogEntry -Path $LogFile -Value "CheckThisGoodOne $folderPath`r`n"
                    }
                    
                    if (-not $Quiet) {
                        if ($WhatIfPreference) {
                            Write-Host "📝 [WhatIf] Would mark folder for manual review: $folderPath" -ForegroundColor Cyan
                        } else {
                            Write-Host "📝 Marked folder for manual review: $folderPath"
                        }
                    }
                }
                catch {
                    Write-Host "WARNING: Failed to append log entry for manual review: $_" -ForegroundColor Red
                }
            }
        }
        catch {
            Write-Host "WARNING: Error processing folder $folderPath`: $_" -ForegroundColor Red
            if ($DetailedLog) {
                Write-Host "📝 [DetailedLog] Exception details: $_" -ForegroundColor Red
            }
        }
    }

    # Remove processed entries from log file
    if ($processedEntries.Count -gt 0 -and -not $WhatIfPreference) {
        try {
            $updatedContent = $logContent
            foreach ($processedEntry in $processedEntries) {
                if ($LogFormat -eq 'JSON') {
                    # For JSON, find and remove the line containing this entry
                    $entryJson = $processedEntry | ConvertTo-Json -Compress
                    $updatedContent = $updatedContent -replace [regex]::Escape("$entryJson`r`n"), ""
                    $updatedContent = $updatedContent -replace [regex]::Escape("$entryJson`n"), ""
                    $updatedContent = $updatedContent -replace [regex]::Escape($entryJson), ""
                } else {
                    # For text format, remove the line using robust line-by-line approach
                    $lines = $updatedContent -split "`n"
                    $targetLines = @(
                        "GoodFolder $($processedEntry.Path)",
                        "CheckThisGoodOne $($processedEntry.Path)"
                    )
                    $lines = $lines | Where-Object {
                        $line = $_.Trim()
                        -not ($targetLines | Where-Object { $line -eq $_ -or $line -eq "$`_`_`_`_`_`_`_`_`_`_`_`_`_`_`_`_`_`_" })
                    }
                    $updatedContent = $lines -join "`n"
                }
            }
            
            # Write back the updated content
            if ($updatedContent.Trim() -ne $logContent.Trim()) {
                # Use .NET method to bypass PowerShell's WhatIf mechanism for log file updates
                [System.IO.File]::WriteAllText($LogFile, $updatedContent.Trim(), [System.Text.Encoding]::UTF8)
                if (-not $Quiet) {
                    Write-Host "📝 Removed $($processedEntries.Count) processed entries from log file"
                }
            }
        }
        catch {
            Write-Host "WARNING: Failed to update log file: $_" -ForegroundColor Red
        }
    }

    if (-not $Quiet) {
        Write-Host "✅ Completed processing $processedCount folders."
    }
}
