Describe 'Structured logging' {
    It 'Write-StructuredLog appends JSONL entries' {
        $temp = Join-Path $env:TEMP 'mfc_test_log.jsonl'
        if (Test-Path $temp) { Remove-Item $temp -Force }

    $modRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
    Import-Module -LiteralPath (Join-Path $modRoot '..\MusicFolderChecker.psm1') -Force

        $entry = @{ Function = 'Test'; Level = 'Info'; Message = 'Hello' }
        Write-StructuredLog -Path $temp -Entry $entry

        $lines = Get-Content -LiteralPath $temp -ErrorAction Stop
        $lines.Count | Should -Be 1
        $j = $lines[0] | ConvertFrom-Json
        $j.Function | Should -Be 'Test'
        $j.Level | Should -Be 'Info'
        $j.Message | Should -Be 'Hello'
    }

    It 'Get-MfcLogSummary returns summary object' {
        $temp = Join-Path $env:TEMP 'mfc_test_log.jsonl'
        $res = Get-MfcLogSummary -LogPath $temp
        $res.TotalEntries | Should -BeGreaterThan 0
        $res.ByLevel | Should -Not -Be $null
    }
}
