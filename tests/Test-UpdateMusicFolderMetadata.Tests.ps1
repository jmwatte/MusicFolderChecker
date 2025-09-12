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

    It 'Moves folders with mixed content and displays WhatIf summary correctly' {
        # Dot-source the functions for this test
        $helperPath = Join-Path $PSScriptRoot '..\src\Private\Invoke-TagLibCreate.ps1'
        if (Test-Path $helperPath) { . $helperPath }
        $functionPath = Join-Path $PSScriptRoot '..\src\Public\Update-MusicFolderMetadata.ps1'
        . $functionPath
        
        # Setup temporary folders
        $tmp = Join-Path $env:TEMP ([Guid]::NewGuid().Guid)
        $dest = Join-Path $env:TEMP ([Guid]::NewGuid().Guid)
        New-Item -ItemType Directory -Path $tmp | Out-Null
        New-Item -ItemType Directory -Path $dest | Out-Null
        
        # Create mixed content: audio files, non-audio files, and subfolders
        New-Item -Path (Join-Path $tmp 'track01.mp3') -ItemType File | Out-Null
        New-Item -Path (Join-Path $tmp 'track02.flac') -ItemType File | Out-Null
        New-Item -Path (Join-Path $tmp 'cover.jpg') -ItemType File | Out-Null
        New-Item -Path (Join-Path $tmp 'lyrics.txt') -ItemType File | Out-Null
        
        # Create a subfolder with files
        $subfolder = Join-Path $tmp 'bonus'
        New-Item -ItemType Directory -Path $subfolder | Out-Null
        New-Item -Path (Join-Path $subfolder 'bonus_track.mp3') -ItemType File | Out-Null
        New-Item -Path (Join-Path $subfolder 'bonus_cover.png') -ItemType File | Out-Null
        
        # Create a mock TagLib object with Tag and a ScriptMethod Save
        $tag = New-Object PSObject
        $tag | Add-Member -MemberType NoteProperty -Name AlbumArtists -Value @('TestArtist')
        $tag | Add-Member -MemberType NoteProperty -Name Performers -Value @('TestArtist')
        $tag | Add-Member -MemberType NoteProperty -Name Album -Value 'TestAlbum'
        $tag | Add-Member -MemberType NoteProperty -Name Year -Value 2023
        $tag | Add-Member -MemberType NoteProperty -Name Disc -Value 1
        $tag | Add-Member -MemberType NoteProperty -Name Track -Value 1
        $tag | Add-Member -MemberType NoteProperty -Name Title -Value 'TestTrack'

        $mockTagObj = New-Object PSObject
        $mockTagObj | Add-Member -MemberType NoteProperty -Name Tag -Value $tag
        $mockTagObj | Add-Member -MemberType ScriptMethod -Name Save -Value { }

        # Mock the Invoke-TagLibCreate function instead of the .NET method directly
        Mock -CommandName Invoke-TagLibCreate -MockWith { return $mockTagObj }
        Mock -CommandName Read-Host -MockWith { return 'y' }  # Auto-confirm prompts
        
        # Test WhatIf mode - should show summary of planned moves
        $whatIfOutput = Update-MusicFolderMetadata -FolderPath $tmp -DestinationFolder $dest -Move -WhatIf -AlbumArtist 'TestArtist' 2>&1 | Out-String
        
        # Verify WhatIf output contains expected information
        $whatIfOutput | Should -Match 'WhatIf planned moves'
        $whatIfOutput | Should -Match 'TestArtist'
        $whatIfOutput | Should -Match 'track01\.mp3'
        
        # Verify no actual moves occurred in WhatIf mode
        (Get-ChildItem -Path $tmp -Recurse -File).Count | Should -Be 6
        (Get-ChildItem -Path $dest -Recurse -File).Count | Should -Be 0
        
        # Cleanup
        Remove-Item -Recurse -Force $tmp
        Remove-Item -Recurse -Force $dest
        # Remove the function from test session
        Remove-Item -Path Function:\Update-MusicFolderMetadata -ErrorAction SilentlyContinue
    }
}
