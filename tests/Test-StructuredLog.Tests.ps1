Describe 'Structured logging' {
    It 'Write-StructuredLog appends JSONL entries' {
        $temp = Join-Path $env:TEMP 'mfc_test_log.jsonl'
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }

        $modRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $modRoot 'MusicFolderChecker.psd1') -Force
        . (Join-Path $modRoot 'src\Private\Write-StructuredLog.ps1')

        $entry = @{ Function = 'Test'; Level = 'Info'; Message = 'Hello' }
        Write-StructuredLog -Path $temp -Entry $entry

        Start-Sleep -Milliseconds 50
        $lines = Get-Content -LiteralPath $temp -ErrorAction Stop
        $lines | Where-Object { $_ -match '\S' } | Measure-Object | Select-Object -ExpandProperty Count | Should -Be 1
        $jsonLine = ($lines | Where-Object { $_ -match '\S' } | Select-Object -First 1)
        $j = $jsonLine | ConvertFrom-Json
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
