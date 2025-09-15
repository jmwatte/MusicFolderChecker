function Set-DiscFromFolderName {
    <#
    .SYNOPSIS
        Sets disc number tags in audio files based on their parent folder name.

    .DESCRIPTION
        This function scans audio files in disc subfolders and sets the disc number tag
        in each file based on the folder name. It supports various disc naming patterns:
        - disc 1, cd 1
        - (CD1), (CD 1)
        - CD1, CD 1
        - [CD1], [CD 1]
        - - CD1, - CD 1
        It also sets the total number of discs if available.

    .PARAMETER FolderPath
        Path to the album folder containing disc subfolders.

    .PARAMETER WhatIf
        Shows what would happen without actually making changes.

    .EXAMPLE
        Set-DiscFromFolderName -FolderPath "E:\Music\Album"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$FolderPath
    )

    $musicExtensions = @('.mp3', '.flac', '.m4a', '.ogg', '.wav', '.aac', '.ape')

    # Find all disc folders (supporting multiple disc naming patterns)
    $discFolders = Get-ChildItem -LiteralPath $FolderPath -Directory | Where-Object {
        # Match various disc folder naming patterns:
        # - disc 1, cd 1 (current)
        # - (CD1), (CD 1) (parentheses)
        # - CD1, CD 1 (space before)
        # - [CD1], [CD 1] (square brackets)
        # - - CD1, - CD 1 (dash before)
        $_.Name -match '(?:^|\s|\(|\[|\-)[\s\-]*(?:disc|cd)[\s\-]*(\d+)[\]\)]*'
    } | Sort-Object { 
        # Extract disc number from various patterns
        [int]($_.Name -replace '.*(?:^|\s|\(|\[|\-)[\s\-]*(?:disc|cd)[\s\-]*(\d+)[\]\)]*.*', '$1')
    }

    if ($discFolders.Count -eq 0) {
        Write-Output "No disc folders found in $FolderPath"
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
        $discNumber = [int]($discFolder.Name -replace '.*(?:^|\s|\(|\[|\-)[\s\-]*(?:disc|cd)[\s\-]*(\d+)[\]\)]*.*', '$1')
        Write-Verbose "Processing disc folder: $($discFolder.Name) (disc $discNumber of $totalDiscs)"

        # Find audio files in this disc folder
        $audioFiles = Get-ChildItem -LiteralPath $discFolder.FullName -File -Recurse | Where-Object {
            $musicExtensions -contains $_.Extension.ToLower()
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

    Write-Output "Disc tag setting complete for $FolderPath"
}