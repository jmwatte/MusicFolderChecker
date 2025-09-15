function Set-DiscFromFolderName {
    <#
    .SYNOPSIS
        Sets disc number tags in audio files based on their parent folder name.

    .DESCRIPTION
        This function scans audio files in disc subfolders and sets the disc number tag
        in each file based on the folder name. It supports various disc naming patterns:
        - disc 1, disk 1, cd 1
        - (CD1), (CD 1) (parentheses)
        - CD1, CD 1 (space before)
        - [CD1], [CD 1] (square brackets)
        - - CD1, - CD 1 (dash before)
        It also sets the total number of discs if available.

    .PARAMETER FolderPath
        Path to the album folder containing disc subfolders, or a collection folder containing multiple albums.

    .PARAMETER Recursive
        If specified, recursively scan subdirectories for album folders (folders containing disc subfolders).
        Use with caution - review the album list before processing.

    .PARAMETER AlbumPattern
        Regex pattern to identify album folders when using -Recursive. Default: '^\d{4}\s*-\s*.+'
        (folders starting with year like "1965 - Help")

    .PARAMETER ConfirmAlbums
        When using -Recursive, prompt for confirmation before processing each album.

    .PARAMETER WhatIf
        Shows what would happen without actually making changes.

    .EXAMPLE
        Set-DiscFromFolderName -FolderPath "E:\Music\Album"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$FolderPath,

        [Parameter()]
        [switch]$Recursive,

        [Parameter()]
        [string]$AlbumPattern = '^\d{4}\s*-\s*.+',

        [Parameter()]
        [switch]$ConfirmAlbums
    )

    $musicExtensions = @('.mp3', '.flac', '.m4a', '.ogg', '.wav', '.aac', '.ape')

    # Check if the path exists
    if (-not (Test-Path -LiteralPath $FolderPath)) {
        Write-Output "Path does not exist: $FolderPath"
        return
    }

    # Determine processing mode: single album or recursive collection
    $albumPaths = @()
    
    # First, check if the provided path itself contains disc folders (single album mode)
    $discFolders = Get-ChildItem -LiteralPath $FolderPath -Directory | Where-Object {
        $_.Name -match '(?:^|\s|\(|\[|\-)[\s\-]*(?:disc|disk|cd)[\s\-]*(\d+)[\]\)]*'
    }
    
    if ($discFolders.Count -gt 0) {
        # Single album mode - process this folder directly
        Write-Verbose "Found $($discFolders.Count) disc folders in $FolderPath - processing as single album"
        $albumPaths = @($FolderPath)
    } elseif ($Recursive) {
        # Recursive mode - scan for album folders
        Write-Verbose "No disc folders found in $FolderPath - scanning for album folders with pattern: $AlbumPattern"
        
        $potentialAlbums = Get-ChildItem -LiteralPath $FolderPath -Directory | Where-Object {
            $_.Name -match $AlbumPattern
        }
        
        if ($potentialAlbums.Count -eq 0) {
            Write-Output "No album folders found matching pattern '$AlbumPattern' in $FolderPath"
            Write-Output "Try adjusting the -AlbumPattern parameter or check your folder structure."
            return
        }
        
        Write-Output "Found $($potentialAlbums.Count) potential album folders:"
        foreach ($album in $potentialAlbums) {
            Write-Output "  - $($album.Name)"
        }
        
        if ($ConfirmAlbums) {
            $confirmation = Read-Host "Process these $($potentialAlbums.Count) albums? (y/N)"
            if ($confirmation -notmatch '^y(es)?$') {
                Write-Output "Operation cancelled by user."
                return
            }
        }
        
        $albumPaths = $potentialAlbums | Select-Object -ExpandProperty FullName
    } else {
        Write-Output "No disc folders found in $FolderPath"
        Write-Output "Use -Recursive to scan subdirectories for album folders, or specify the exact album path."
        return
    }

    # Process each album
    $totalAlbums = $albumPaths.Count
    $albumIndex = 0
    
    foreach ($albumPath in $albumPaths) {
        $albumIndex++
        $albumName = Split-Path -Leaf $albumPath
        
        Write-Output "`n[$albumIndex/$totalAlbums] Processing album: $albumName"
        
        # Process this album (extracted logic from original function)
        Set-AlbumDiscTags -AlbumPath $albumPath -MusicExtensions $musicExtensions
    }
    
    Write-Output "`nBatch processing complete. Processed $totalAlbums album(s)."
}

function Set-AlbumDiscTags {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$AlbumPath,
        [array]$MusicExtensions
    )

    # Find all disc folders (supporting multiple disc naming patterns)
    $discFolders = Get-ChildItem -LiteralPath $AlbumPath -Directory | Where-Object {
        # Match various disc folder naming patterns:
        # - disc 1, disk 1, cd 1 (now includes disk!)
        # - (CD1), (CD 1) (parentheses)
        # - CD1, CD 1 (space before)
        # - [CD1], [CD 1] (square brackets)
        # - - CD1, - CD 1 (dash before)
        $_.Name -match '(?:^|\s|\(|\[|\-)[\s\-]*(?:disc|disk|cd)[\s\-]*(\d+)[\]\)]*'
    } | Sort-Object { 
        # Extract disc number from various patterns
        [int]($_.Name -replace '.*(?:^|\s|\(|\[|\-)[\s\-]*(?:disc|disk|cd)[\s\-]*(\d+)[\]\)]*.*', '$1')
    }

    if ($discFolders.Count -eq 0) {
        Write-Output "No disc folders found in $AlbumPath"
        return
    }

    $totalDiscs = $discFolders.Count

    # Track statistics for better reporting
    $stats = @{
        TotalFiles = 0
        AlreadyCorrect = 0
        WouldUpdate = 0
        Errors = 0
    }

    foreach ($discFolder in $discFolders) {
        # Extract disc number from various naming patterns
        $discNumber = [int]($discFolder.Name -replace '.*(?:^|\s|\(|\[|\-)[\s\-]*(?:disc|disk|cd)[\s\-]*(\d+)[\]\)]*.*', '$1')
        Write-Verbose "Processing disc folder: $($discFolder.Name) (disc $discNumber of $totalDiscs)"

        # Find audio files in this disc folder
        $audioFiles = Get-ChildItem -LiteralPath $discFolder.FullName -File -Recurse | Where-Object {
            $MusicExtensions -contains $_.Extension.ToLower()
        }

        Write-Verbose "Found $($audioFiles.Count) audio files in $($discFolder.Name)"

        foreach ($file in $audioFiles) {
            $stats.TotalFiles++
            Write-Verbose "Processing file: $($file.Name)"
            try {
                $tagFile = Invoke-TagLibCreate -Path $file.FullName
            }
            catch {
                Write-Output "Failed to read tags from $($file.FullName): $_"
                $stats.Errors++
                continue
            }

            $currentDisc = $tagFile.Tag.Disc
            $currentDiscCount = $tagFile.Tag.DiscCount

            $needsUpdate = $false
            if ($currentDisc -ne $discNumber) { $needsUpdate = $true }
            if ($currentDiscCount -ne $totalDiscs) { $needsUpdate = $true }

            if (-not $needsUpdate) {
                Write-Verbose "Disc tags already correct for $($file.FullName)"
                $stats.AlreadyCorrect++
                continue
            }

            $stats.WouldUpdate++
            if ($PSCmdlet.ShouldProcess($file.FullName, "Set disc to $discNumber/$totalDiscs")) {
                try {
                    $tagFile.Tag.Disc = $discNumber
                    $tagFile.Tag.DiscCount = $totalDiscs
                    $tagFile.Save()
                    Write-Output "Updated disc tags for $($file.FullName): $discNumber/$totalDiscs"
                }
                catch {
                    Write-Output "Failed to update disc tags for $($file.FullName): $_"
                    $stats.Errors++
                }
            }
        }
    }

    # Provide informative summary
    $isWhatIf = $PSCmdlet.MyInvocation.BoundParameters.ContainsKey('WhatIf') -or $WhatIfPreference
    Write-Verbose "WhatIf detection: BoundParameters=$($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('WhatIf')), WhatIfPreference=$WhatIfPreference, isWhatIf=$isWhatIf"
    Write-Verbose "Stats: TotalFiles=$($stats.TotalFiles), AlreadyCorrect=$($stats.AlreadyCorrect), WouldUpdate=$($stats.WouldUpdate), Errors=$($stats.Errors)"
    
    if ($isWhatIf) {
        if ($stats.WouldUpdate -gt 0) {
            Write-Output "WhatIf: Would update disc tags for $($stats.WouldUpdate) files across $($discFolders.Count) discs"
        }
        if ($stats.AlreadyCorrect -gt 0) {
            Write-Output "WhatIf: All $($stats.TotalFiles) files already have correct disc tags - no changes needed"
        }
        if ($stats.WouldUpdate -eq 0 -and $stats.AlreadyCorrect -eq 0) {
            Write-Output "WhatIf: No audio files found to process"
        }
    } else {
        if ($stats.WouldUpdate -gt 0) {
            Write-Output "Updated disc tags for $($stats.WouldUpdate) files"
        }
    }

    if ($stats.Errors -gt 0) {
        Write-Output "Warning: Encountered $($stats.Errors) errors during processing"
    }

    Write-Output "Disc tag setting complete for $AlbumPath"
}