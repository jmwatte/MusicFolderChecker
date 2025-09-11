Import-Module Pester -ErrorAction Stop

Describe 'Update-MusicFolderMetadata' {
    BeforeAll {
        # Dot-source the private helper and public function into the test scope so Mock can intercept calls
        $helperPath = Join-Path $PSScriptRoot '..\src\Private\Invoke-TagLibCreate.ps1'
        if (Test-Path $helperPath) { . $helperPath }
        $functionPath = Join-Path $PSScriptRoot '..\src\Public\Update-MusicFolderMetadata.ps1'
        . $functionPath
    }

    It 'calls Invoke-TagLibCreate and Save for each audio file' {
        # Setup temporary folder with fake audio files
        $temp = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $temp | Out-Null
    $files = @( (Join-Path $temp '01 - Track One.mp3'), (Join-Path $temp '02 - Track Two.mp3') )
    foreach ($f in $files) { New-Item -Path $f -ItemType File | Out-Null }

    # Create a mock TagLib object with Tag and a ScriptMethod Save
    $tag = New-Object PSObject
    $tag | Add-Member -MemberType NoteProperty -Name AlbumArtists -Value @()
    $tag | Add-Member -MemberType NoteProperty -Name Performers -Value @()
    $tag | Add-Member -MemberType NoteProperty -Name Album -Value ''
    $tag | Add-Member -MemberType NoteProperty -Name Year -Value 0

    $mockTagObj = New-Object PSObject
    $mockTagObj | Add-Member -MemberType NoteProperty -Name Tag -Value $tag
    $mockTagObj | Add-Member -MemberType ScriptMethod -Name Save -Value { }

    Mock -CommandName Invoke-TagLibCreate -MockWith { return $mockTagObj }

        # Run the function non-interactively
        Update-MusicFolderMetadata -FolderPath $temp -AlbumArtist 'Test Artist' -Album 'Test Album' -Year 2025 -Quiet

        # Assert Invoke-TagLibCreate was called twice (once per file)
        Assert-MockCalled -CommandName Invoke-TagLibCreate -Times 2

    # Cleanup
    Remove-Item -LiteralPath $temp -Recurse -Force
    # Remove the function from test session
    Remove-Item -Path Function:\Update-MusicFolderMetadata -ErrorAction SilentlyContinue
    }
}
