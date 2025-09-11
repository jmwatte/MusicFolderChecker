function Write-StructuredLog {
    <#
    .SYNOPSIS
        Append a newline-delimited JSON (JSONL) entry to a log file.

    .PARAMETER Path
        The log file path to write to. The parent directory will be created if missing.

    .PARAMETER Entry
        A hashtable or PSObject representing the data to serialize as JSON.

    .PARAMETER Depth
        JSON serialization depth passed to ConvertTo-Json. Default 5.
    #>
    param(
        [Parameter(Mandatory=$true)] [string]$Path,
        [Parameter(Mandatory=$true)] [object]$Entry,
        [int]$Depth = 5
    )

    try {
        $dir = Split-Path -Path $Path -Parent
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        # Ensure we have a plain PSCustomObject for predictable serialization
        if ($Entry -isnot [PSCustomObject]) { $entryObj = [PSCustomObject]$Entry } else { $entryObj = $Entry }

        # Add an ISO timestamp if not already present
        if (-not $entryObj.PSObject.Properties.Name -contains 'Timestamp') { $entryObj | Add-Member -NotePropertyName Timestamp -NotePropertyValue ((Get-Date).ToString('o')) }

        $json = $entryObj | ConvertTo-Json -Depth $Depth
        # ConvertTo-Json may produce multi-line JSON; collapse to a single line for JSONL
        $oneLine = $json -replace "[\r\n]+", ' '

        # Append newline-delimited JSON
        [System.IO.File]::AppendAllText($Path, $oneLine + "`n", [System.Text.Encoding]::UTF8)
    }
    catch {
        # Fail quietly to avoid breaking primary operations; write a simple text fallback
        try {
            $fb = @{"Timestamp" = (Get-Date -Format o); "Function" = 'Write-StructuredLog'; "Level" = 'Error'; "Message" = $_.ToString() }
            $fbJson = $fb | ConvertTo-Json -Depth 2 -Compress
            [System.IO.File]::AppendAllText($Path, $fbJson + "`n", [System.Text.Encoding]::UTF8)
        } catch { }
    }
}
