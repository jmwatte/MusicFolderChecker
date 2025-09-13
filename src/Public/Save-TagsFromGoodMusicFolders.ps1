<#
.SYNOPSIS
    Extracts metadata from folder names and updates audio file tags accordingly.

.DESCRIPTION
    Save-TagsFromGoodMusicFolders reads properly structured music folder names and applies
    the extracted metadata (artist, album, year, track numbers) to the embedded audio file tags.
    It validates folder structure before processing and logs any issues encountered.

.PARAMETER FolderPath
    Path to the music folder to process. Accepts pipeline input.

.PARAMETER LogTo
    Optional path to save processing results. If not specified, automatically creates a timestamped log.

.PARAMETER LogFormat
    Format for the log file. Valid values: 'Text', 'JSON'. Default is 'JSON'.

.PARAMETER Quiet
    Switch parameter. When specified, suppresses detailed console output.

.PARAMETER hideTags
    Switch parameter. When specified, suppresses detailed tag information display.

.PARAMETER FoldersToSkip
    Array of paths to exclude from processing. Supports comma-separated strings and arrays.

.INPUTS
    System.String
    You can pipe folder paths to Save-TagsFromGoodMusicFolders.

.OUTPUTS
    PSCustomObject
    Returns an object with GoodFolders and CorruptFiles properties.

.EXAMPLE
    Save-TagsFromGoodMusicFolders -FolderPath 'E:\Music\Artist\2020 - Album'
    Processes the folder and updates all audio file tags with extracted metadata

.EXAMPLE
    Find-BadMusicFolderStructure -StartingPath 'E:\Music' -Good | Save-TagsFromGoodMusicFolders -Quiet
    Finds good folders and tags their audio files without console output

.EXAMPLE
    Save-TagsFromGoodMusicFolders -FolderPath 'E:\Music\Artist\2020 - Album' -LogTo 'C:\Temp\tagging.log' -WhatIf
    Shows what tags would be applied without actually modifying files

.NOTES
    Author: MusicFolderChecker Module
    Requires TagLib-Sharp.dll for audio file processing
    Validates folder structure before processing
    Preserves existing genre tags when updating other metadata
    Logs corrupt or problematic files for manual review
#>
function Save-TagsFromGoodMusicFolders {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$FolderPath,

        [string]$LogTo,

        [Parameter()]
        [ValidateSet('Text', 'JSON')]
        [string]$LogFormat = 'JSON',

        [switch]$Quiet,

        [switch]$hideTags,

        [Parameter()]
        [string[]]$FoldersToSkip
    )

    begin {
        # TagLib is already loaded at module level
        [TagLib.Id3v2.Tag]::DefaultVersion = 4
        [TagLib.Id3v2.Tag]::ForceDefaultVersion = $true

        $musicExtensions = @('.mp3', '.flac', '.m4a', '.ogg', '.wav', '.aac')

        $badFolders = @{}
        $goodFolders = @()
        $allCorruptFiles = @{}

        if ($LogTo) {
            $logDir = Split-Path -Path $LogTo -Parent
            if (-not (Test-Path -Path $logDir)) {
                New-Item -ItemType Directory -Path $logDir -Force -WhatIf:$false | Out-Null
            }
            # Initialize a fresh log file
            "" | Out-File -FilePath $LogTo -Encoding UTF8 -WhatIf:$false
        }
    }

    process {
        # Safety: verify compliance before tagging
        $validationResults = Find-BadMusicFolderStructure -StartingPath $FolderPath -Good -Quiet:$Quiet -FoldersToSkip:$FoldersToSkip -Simple:$false
        
        # Handle both old and new result formats for backward compatibility
        if ($validationResults -is [array] -and $validationResults.Count -gt 0 -and $validationResults[0].PSObject.Properties.Name -contains 'IsValid') {
            # New detailed result format
            $validationResult = $validationResults | Where-Object { $_.Path -eq $FolderPath } | Select-Object -First 1
            
            if (-not $validationResult -or -not $validationResult.IsValid) {
                $reason = if ($validationResult) { $validationResult.Reason } else { "Unknown" }
                $details = if ($validationResult) { $validationResult.Details } else { "Validation failed" }
                
                # Provide specific, user-friendly messages based on failure reason
                switch ($reason) {
                    "Empty" {
                        if (-not $Quiet) {
                            Write-Host "ℹ️  Skipping empty folder: $FolderPath"
                        }
                    }
                    "NoMusicFiles" {
                        if (-not $Quiet) {
                            Write-Host "ℹ️  No music files found in: $FolderPath"
                        }
                    }
                    "CorruptedFile" {
                        Write-Host "WARNING: Corrupted audio file in: $FolderPath - $details" -ForegroundColor Red
                    }
                    "BadStructure" {
                        if (-not $Quiet) {
                            Write-Host "ℹ️  Folder structure doesn't match expected pattern: $FolderPath"
                        }
                    }
                    "Skipped" {
                        if (-not $Quiet) {
                            Write-Host "🚫 Skipping folder (in folders to skip): $FolderPath"
                        }
                    }
                    "NotFound" {
                        Write-Host "WARNING: Folder not found: $FolderPath" -ForegroundColor Red
                    }
                    default {
                        Write-Host "WARNING: Skipping folder ($reason): $FolderPath" -ForegroundColor Red
                    }
                }
                
                if ($LogTo) { 
                    $badFolders[$FolderPath] = @($reason)
                }
                return
            }
        }
        else {
            # Old boolean result format (backward compatibility)
            $isGoodMusic = $validationResults
            if (-not $isGoodMusic) {
                if (-not $Quiet) {
                    Write-Host "ℹ️  Skipping folder (validation failed): $FolderPath"
                }
                if ($LogTo) { $badFolders[$FolderPath] = @("NonCompliant") }
                return
            }
        }

        $musicFiles = Get-ChildItem -LiteralPath $FolderPath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $musicExtensions -contains $_.Extension.ToLower() }

        foreach ($file in $musicFiles) {
            $parts = $file.FullName -split '\\'

            # Extract album info - handle both nested and direct album structures
            $albumIndex = -1
            $year = ""
            $album = ""
            $albumArtist = ""

            for ($i = 1; $i -lt $parts.Count; $i++) {
                if ($parts[$i] -match '^(\d{4})\s*-\s*(.+)$') {
                    $albumIndex = $i
                    $year = $matches[1]
                    $album = $matches[2]
                    # Get artist from the previous part
                    if ($i -gt 1) {
                        $albumArtist = $parts[$i - 1]
                    }
                    break
                }
            }

            # If no album folder found in path, check if current folder is the album folder
            if ($albumIndex -eq -1) {
                $currentFolder = Split-Path $file.DirectoryName -Leaf
                if ($currentFolder -match '^(\d{4})\s*-\s*(.+)$') {
                    $albumIndex = $parts.Count - 1  # Point to the file's directory
                    $year = $matches[1]
                    $album = $matches[2]
                    # Get artist from parent directory
                    $parentDir = Split-Path $file.DirectoryName -Parent
                    $albumArtist = Split-Path $parentDir -Leaf
                }
            }

            if ($albumIndex -ge 1 -and $year -and $album) {
                $albumArtist = $albumArtist  # Already set above
                $fileName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)

                # Extract disc number from directory if it's a CD folder
                $directory = Split-Path $file.FullName -Parent
                $discNumber = 1
                if ($directory -match ".*\\$year - $album - CD(\d+)$") {
                    $discNumber = [uint]$matches[1]
                }

                if ($fileName -match '^([\d-]+)\s*-\s*(.+)$') {
                    $trackNumber = $matches[1]
                    $title = $matches[2].Trim()

                    if ($trackNumber -match '^(?:CD)?(\d+)[.-](\d+)$') {
                        if ($discNumber -eq 1) { $discNumber = [uint]$matches[1] }
                        $trackNumber = [uint]$matches[2]
                    }
                    else {
                        $trackNumber = [uint]$trackNumber
                    }

                    try {
                        $tagFile = [TagLib.File]::Create($file.FullName)
                        $existingGenres = $tagFile.Tag.Genres

                        if ($WhatIfPreference) {
                            if (-not $Quiet -and -not $hideTags) {
                                Write-Host "🔍 [WhatIf] Would tag: $($file.FullName)"
                                if (-not $hideTags) {
                                    Write-Host ("    👥 Album Artist : {0}" -f $albumArtist)
                                    Write-Host ("    🎤 Track Artist : {0}" -f $albumArtist)
                                    Write-Host ("    💿 Album        : {0}" -f $album)
                                    Write-Host ("    📅 Year         : {0}" -f $year)
                                    Write-Host ("    💽 Disc         : {0}" -f $discNumber)
                                    Write-Host ("    🔢 Track        : {0}" -f $trackNumber)
                                    Write-Host ("    🎵 Title        : {0}" -f $title)
                                    Write-Host ("    🎼 Genres       : {0}" -f (($existingGenres -join ', ') -replace '^\s*$','<none>'))
                                }
                            }
                        }

                        
                        
                        elseif ($PSCmdlet.ShouldProcess($file.FullName, "Update tags")) {
                            
                            
                            # Actual tagging
                            $tagFile.Tag.Title = ""
                            $tagFile.Tag.Performers = @()
                            $tagFile.Tag.AlbumArtists = @()
                            $tagFile.Tag.Album = ""
                            $tagFile.Tag.Comment = ""
                            $tagFile.Tag.Year = 0
                            $tagFile.Tag.Track = 0
                            $tagFile.Tag.Disc = 0
                            $tagFile.Tag.Composers = @()

                            if ($existingGenres) { $tagFile.Tag.Genres = $existingGenres }

                            $tagFile.Tag.Performers = @($albumArtist)
                            $tagFile.Tag.AlbumArtists = @($albumArtist)
                            $tagFile.Tag.Album = $album
                            $tagFile.Tag.Year = [uint]$year
                            $tagFile.Tag.Track = [uint]$trackNumber
                            $tagFile.Tag.Disc = [uint]$discNumber
                            $tagFile.Tag.Title = $title

                            $tagFile.Save()
                            if (-not $Quiet) {
                                Write-Host "✅ Retagged: $($file.Name)"
                            }
                            
                        }
                    }
                    catch {
                        Write-Host "WARNING: ⚠️ Failed to tag: $($file.FullName) — $_" -ForegroundColor Red
                        if (-not $allCorruptFiles.ContainsKey($FolderPath)) {
                            $allCorruptFiles[$FolderPath] = @()
                        }
                        $allCorruptFiles[$FolderPath] += [PSCustomObject]@{
                            FilePath = $file.FullName
                            Error = $_.Exception.Message
                            Reason = "TagLibError"
                        }
                        if ($LogTo) { $badFolders[$FolderPath] += "FailedTagging" }
                    }
                }
                else {
                    Write-Host "WARNING: ❌ Bad filename format: $fileName" -ForegroundColor Red
                    if (-not $allCorruptFiles.ContainsKey($FolderPath)) {
                        $allCorruptFiles[$FolderPath] = @()
                    }
                    $allCorruptFiles[$FolderPath] += [PSCustomObject]@{
                        FilePath = $file.FullName
                        Error = "Bad filename format: $fileName"
                        Reason = "BadFilename"
                    }
                    if ($LogTo) { $badFolders[$FolderPath] += "WrongTitleFormat" }
                }
            }
            else {
                Write-Host "WARNING: ❌ No album folder found: $($file.FullName)" -ForegroundColor Red
                if (-not $allCorruptFiles.ContainsKey($FolderPath)) {
                    $allCorruptFiles[$FolderPath] = @()
                }
                $allCorruptFiles[$FolderPath] += [PSCustomObject]@{
                    FilePath = $file.FullName
                    Error = "No album folder found in path structure"
                    Reason = "NoAlbumFolder"
                }
                if ($LogTo) { $badFolders[$FolderPath] += "ShallowPath" }
            }
        }
        
        # If no errors for this folder, mark as good
        if (-not $badFolders.ContainsKey($FolderPath)) {
            $goodFolders += $FolderPath
        }
    }

    end {
        if ($LogTo -and $badFolders.Count -gt 0) {
            foreach ($folder in $badFolders.Keys) {
                $reasons = ($badFolders[$folder] | Sort-Object -Unique) -join ", "
                if ($LogFormat -eq 'JSON') {
                    $logEntry = @{
                        Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                        Status = 'Error'
                        Path = $folder
                        Function = 'Save-TagsFromGoodMusicFolders'
                        Reasons = $reasons
                        Type = 'TaggingError'
                    } | ConvertTo-Json -Compress
                    Write-LogEntry -Path $LogTo -Value "$logEntry`r`n"
                } else {
                    Write-LogEntry -Path $LogTo -Value "$reasons`: $folder`r`n"
                }
            }
            if (-not $Quiet) {
                Write-Host "📝 Bad folders logged to: $LogTo"
            }
        }
        
        # Output successfully processed folders and corrupt files info
        [PSCustomObject]@{
            GoodFolders = $goodFolders
            CorruptFiles = $allCorruptFiles
        }
    }
}
