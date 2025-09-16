<#
.SYNOPSIS
    Restores music files to their correct locations based on the BadResults2.txt log file.

.DESCRIPTION
    This script reads the BadResults2.txt file and moves files from their incorrect locations
    (after the -> arrow) back to their correct locations (before the -> arrow).
    It creates destination directories as needed and handles various error conditions.

.PARAMETER LogFile
    Path to the BadResults2.txt file. Defaults to ".\src\Private\BadResults2.txt"

.PARAMETER WhatIf
    Shows what would happen without actually moving files.

.EXAMPLE
    .\Restore-MusicFiles.ps1

.EXAMPLE
    .\Restore-MusicFiles.ps1 -LogFile "C:\Path\To\BadResults2.txt" -WhatIf

.NOTES
    Author: GitHub Copilot
    Requires: PowerShell 5.1 or later
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [string]$LogFile = ".\src\Private\BadResults2.txt"
)

# Function to create directory if it doesn't exist
function New-DirectoryIfNeeded {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$Path)

    $directory = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $directory)) {
        if ($PSCmdlet.ShouldProcess($directory, "Create directory")) {
            try {
                New-Item -ItemType Directory -Path $directory -Force | Out-Null
                Write-Verbose "Created directory: $directory"
            }
            catch {
                Write-Warning "Failed to create directory '$directory': $_"
                return $false
            }
        }
    }
    return $true
}

# Function to find a file with similar name (handling spacing issues)
function Find-SimilarFile {
    param(
        [string]$Directory,
        [string]$ExpectedName
    )

    # First try exact match
    $exactPath = Join-Path -Path $Directory -ChildPath $ExpectedName
    if (Test-Path -LiteralPath $exactPath) {
        return $exactPath
    }

    # If exact match fails, try to find files with similar names
    $fileName = [System.IO.Path]::GetFileName($ExpectedName)
    $extension = [System.IO.Path]::GetExtension($ExpectedName)
    $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($ExpectedName)

    # Try normalizing spaces (replace multiple spaces with single space)
    $normalizedName = $nameWithoutExt -replace '\s+', ' '
    $normalizedFileName = $normalizedName + $extension

    $normalizedPath = Join-Path -Path $Directory -ChildPath $normalizedFileName
    if (Test-Path -LiteralPath $normalizedPath) {
        Write-Verbose "Found file with normalized spacing: '$normalizedFileName' instead of '$fileName'"
        return $normalizedPath
    }

    # Try removing extra spaces after common patterns like "01 - ", "02 - ", etc.
    $pattern = '^(\d+\s*-\s*)(.+)$'
    if ($nameWithoutExt -match $pattern) {
        $prefix = $Matches[1]
        $rest = $Matches[2]

        # Remove extra spaces in prefix
        $cleanPrefix = $prefix -replace '\s+', ' '
        $cleanName = $cleanPrefix + $rest
        $cleanFileName = $cleanName + $extension

        $cleanPath = Join-Path -Path $Directory -ChildPath $cleanFileName
        if (Test-Path -LiteralPath $cleanPath) {
            Write-Verbose "Found file with cleaned prefix: '$cleanFileName' instead of '$fileName'"
            return $cleanPath
        }
    }

    return $null
}

# Function to move a single file
function Move-MusicFile {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )

    # Check if source file exists (exact match first)
    if (-not (Test-Path -LiteralPath $SourcePath)) {
        # Try to find a similar file
        $sourceDir = Split-Path -Path $SourcePath -Parent
        $sourceFile = Split-Path -Path $SourcePath -Leaf
        $similarFile = Find-SimilarFile -Directory $sourceDir -ExpectedName $sourceFile

        if ($similarFile) {
            $SourcePath = $similarFile
            Write-Verbose "Using similar file: $SourcePath"
        } else {
            Write-Warning "Source file does not exist: $SourcePath"
            return $false
        }
    }

    # Check if destination file already exists
    if (Test-Path -LiteralPath $DestinationPath) {
        Write-Warning "Destination file already exists: $DestinationPath"
        return $false
    }

    # Create destination directory if needed
    if (-not (New-DirectoryIfNeeded -Path $DestinationPath)) {
        return $false
    }

    # Move the file
    if ($PSCmdlet.ShouldProcess("$SourcePath -> $DestinationPath", "Move file")) {
        try {
            Move-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
            Write-Host "Moved: $SourcePath -> $DestinationPath" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Error "Failed to move '$SourcePath' to '$DestinationPath': $_"
            return $false
        }
    }

    return $true
}

# Main script logic
try {
    if (-not (Test-Path -Path $LogFile)) {
        throw "Log file not found: $LogFile"
    }

    Write-Host "Reading log file: $LogFile" -ForegroundColor Cyan
    $lines = Get-Content -Path $LogFile

    $totalMoves = 0
    $successfulMoves = 0
    $skippedMoves = 0

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].Trim()

        # Look for lines that start with a drive letter (source paths)
        if ($line -match '^[A-Z]:\\' -and $line -notmatch '^->') {
            $correctPath = $line

            # Check if next line exists and starts with ->
            if (($i + 1) -lt $lines.Count) {
                $nextLine = $lines[$i + 1].Trim()

                if ($nextLine -match '^-> (.+)$') {
                    $currentPath = $Matches[1]
                    Write-Verbose "Regex matched: '$nextLine' -> captured: '$currentPath'"
                    $totalMoves++

                    Write-Verbose "Processing: $correctPath <- $currentPath"

                    if (Move-MusicFile -SourcePath $currentPath -DestinationPath $correctPath) {
                        $successfulMoves++
                    } else {
                        $skippedMoves++
                    }

                    # Skip the next line since we processed it
                    $i++
                }
            }
        }
        # Skip lines that are just "-> ..." without a preceding source
        elseif ($line -match '^->') {
            Write-Verbose "Skipping orphaned destination line: $line"
        }
        # Skip empty lines and other content
        elseif ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        else {
            Write-Verbose "Skipping non-path line: $line"
        }
    }

    # Summary
    Write-Host "`n=== Summary ===" -ForegroundColor Yellow
    Write-Host "Total file pairs processed: $totalMoves"
    Write-Host "Successful moves: $successfulMoves" -ForegroundColor Green
    Write-Host "Skipped/failed moves: $skippedMoves" -ForegroundColor Red

    if ($skippedMoves -gt 0) {
        Write-Host "`nNote: Some files may have been skipped due to missing source files or existing destination files." -ForegroundColor Yellow
        Write-Host "Check the warnings above for details." -ForegroundColor Yellow
    }
}
catch {
    Write-Error "Script execution failed: $_"
    exit 1
}
