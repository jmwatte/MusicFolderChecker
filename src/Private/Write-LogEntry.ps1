function Write-LogEntry {
    param(
        [string]$Path,
        [string]$Value
    )
    # Ensure we start on a new line by checking if file ends with newline
    if (Test-Path $Path) {
        $fileInfo = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        if ($fileInfo -and -not $fileInfo.EndsWith("`n")) {
            # File doesn't end with newline, add one before appending
            [System.IO.File]::AppendAllText($Path, "`n", [System.Text.Encoding]::UTF8)
        }
    }
    # Use .NET method to bypass PowerShell WhatIf system
    [System.IO.File]::AppendAllText($Path, $Value, [System.Text.Encoding]::UTF8)
}
