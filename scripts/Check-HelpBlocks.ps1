<#
.SYNOPSIS
    Validates that every public function file in src/Public contains a comment-based help block.

.DESCRIPTION
    Scans the src/Public folder for .ps1 files and checks whether each file contains a
    PowerShell comment-based help block (a block comment placed immediately before the function definition).
    Returns a list of files missing help and exits with non-zero code when issues are found.

.EXAMPLE
    .\scripts\Check-HelpBlocks.ps1

#>

[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$PublicPath = (Join-Path $PSScriptRoot '..\src\Public')
)

$errors = @()

if (-not (Test-Path -LiteralPath $PublicPath)) {
    Write-Output "Public path not found: $PublicPath"
    exit 2
}

Get-ChildItem -Path $PublicPath -Filter '*.ps1' -File | ForEach-Object {
    $file = $_.FullName
    $content = Get-Content -LiteralPath $file -Raw -ErrorAction Stop

    # Look for a comment-based help block prior to the function keyword
    # Strategy: find the first occurrence of 'function' at start of line and check if a '<#' exists above it
    $lines = $content -split "`n"
    $firstFunctionLine = $null
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].TrimStart() -match '^function\b') { $firstFunctionLine = $i; break }
    }

    if ($null -eq $firstFunctionLine) {
        $errors += [PSCustomObject]@{ File = $file; Issue = 'No function definition found' }
        return
    }

    # Search upwards for a '<#' block start before the function. Allow whitespace lines between help block and function.
    $foundHelp = $false
    for ($j = $firstFunctionLine - 1; $j -ge 0; $j--) {
        $line = $lines[$j].Trim()
        if ($line -eq '') { continue }
        if ($line -like '<#*') { $foundHelp = $true; break }
        # If we hit any code or a param block start, stop searching
        if ($line -match '^(param\(|\[CmdletBinding\(|function\b)') { break }
    }

    if (-not $foundHelp) {
        $errors += [PSCustomObject]@{ File = $file; Issue = 'Missing comment-based help block' }
    }
}

if ($errors.Count -gt 0) {
    Write-Output "Found $($errors.Count) files missing comment-based help:"
    $errors | ForEach-Object { Write-Output " - $($_.File): $($_.Issue)" }
    # Return non-zero so CI can catch it
    exit 1
}
else {
    Write-Output "All public function files include comment-based help."
    exit 0
}
