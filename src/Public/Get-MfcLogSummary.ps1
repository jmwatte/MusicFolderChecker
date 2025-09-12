function Get-MfcLogSummary {
    <#
    .SYNOPSIS
        Summarize a JSONL (newline-delimited JSON) MusicFolderChecker log file.

    .PARAMETER LogPath
        Path to the JSONL log file.

    .PARAMETER FilterIssueType
        Optional issue type to filter (e.g., MissingYear).

    .PARAMETER FilterLevel
        Optional log level to filter (Info, Warning, Error).

    .PARAMETER Output
        Output format: 'Table' (default), 'JSON', or 'CSV'.
    #>
    param(
        [Parameter(Mandatory=$true)] [string]$LogPath,
        [string]$FilterIssueType,
        [string]$FilterLevel,
        [ValidateSet('Table','JSON','CSV')][string]$Output = 'Table'
    )

    if (-not (Test-Path -LiteralPath $LogPath)) { throw "Log file not found: $LogPath" }

    $lines = Get-Content -LiteralPath $LogPath -ErrorAction Stop | Where-Object { $_ -match '\S' }
    $entries = @()
    foreach ($l in $lines) {
        try {
            $o = $l | ConvertFrom-Json -ErrorAction Stop
            $entries += $o
        }
        catch {
            # ignore lines that are not valid JSON
        }
    }

    if ($FilterIssueType) { $entries = $entries | Where-Object { $_.IssueType -eq $FilterIssueType } }
    if ($FilterLevel) { $entries = $entries | Where-Object { $_.Level -eq $FilterLevel } }

    # Build summary
    $byType = $entries | Group-Object -Property IssueType | ForEach-Object {
        [PSCustomObject]@{ IssueType = $_.Name; Count = $_.Count }
    }
    $byLevel = $entries | Group-Object -Property Level | ForEach-Object {
        [PSCustomObject]@{ Level = $_.Name; Count = $_.Count }
    }

    $result = [PSCustomObject]@{
        LogPath = $LogPath
        TotalEntries = $entries.Count
        ByIssueType = $byType
        ByLevel = $byLevel
        Entries = $entries
    }

    switch ($Output) {
        'JSON' { $result | ConvertTo-Json -Depth 5 }
        'CSV' { $result.ByIssueType | ConvertTo-Csv -NoTypeInformation }
        default { return $result }
    }
}
