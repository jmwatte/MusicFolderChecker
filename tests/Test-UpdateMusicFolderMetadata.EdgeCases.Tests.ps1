# Edge-case Pester tests for Update-MusicFolderMetadata

Describe 'Update-MusicFolderMetadata - edge cases' {
    BeforeAll {
        $moduleRoot = Split-Path -Parent $PSScriptRoot
        # Dot-source private helpers into the test session so Mock can find them
        . "$moduleRoot\src\Private\Invoke-TagLibCreate.ps1"
        . "$moduleRoot\src\Private\Get-DestinationPath.ps1"
        . "$moduleRoot\src\Private\Write-LogEntry.ps1"

        # Import the module (loader) to ensure public functions are available
        Import-Module -Name "$moduleRoot\MusicFolderChecker.psm1" -Force -ErrorAction Stop
    }

    It 'Skips non-audio files and reports none found' {
        $tmp = Join-Path $env:TEMP ([Guid]::NewGuid().Guid)
        New-Item -ItemType Directory -Path $tmp | Out-Null
        New-Item -Path (Join-Path $tmp 'cover.jpg') -ItemType File | Out-Null

        $output = Update-MusicFolderMetadata -FolderPath $tmp -AlbumArtist 'TestArtist' -ErrorAction Stop | Out-String

        $output | Should -Match "No audio files found in:"

        Remove-Item -Recurse -Force $tmp
    }

    It 'Continues when TagLib throws for a corrupted file (no-throw)' {
        $tmp = Join-Path $env:TEMP ([Guid]::NewGuid().Guid)
        New-Item -ItemType Directory -Path $tmp | Out-Null
        $good = Join-Path $tmp 'good.mp3'; New-Item -Path $good -ItemType File | Out-Null
        $bad  = Join-Path $tmp 'bad.mp3';  New-Item -Path $bad  -ItemType File | Out-Null

        # Running against empty/invalid mp3 files may cause TagLib to throw for some files; ensure overall function does not throw
        { Update-MusicFolderMetadata -FolderPath $tmp -AlbumArtist 'TestArtist' } | Should -Not -Throw

        Remove-Item -Recurse -Force $tmp
    }

    It 'Logs and continues on readonly file write failure (no-throw)' {
        $tmp = Join-Path $env:TEMP ([Guid]::NewGuid().Guid); New-Item -ItemType Directory -Path $tmp | Out-Null
        $f = Join-Path $tmp 'song.mp3'; New-Item -Path $f -ItemType File | Out-Null
        # Make read-only
        (Get-Item $f).Attributes = 'ReadOnly'

        { Update-MusicFolderMetadata -FolderPath $tmp -AlbumArtist 'TestArtist' } | Should -Not -Throw

        Remove-Item -Recurse -Force $tmp
    }

    It 'Handles unicode filenames/tags (no-throw)' {
        $tmp = Join-Path $env:TEMP ([Guid]::NewGuid().Guid); New-Item -ItemType Directory -Path $tmp | Out-Null
        $f = Join-Path $tmp 'tést-únaíçódé.mp3'; New-Item -Path $f -ItemType File | Out-Null

        { Update-MusicFolderMetadata -FolderPath $tmp -Album 'Álbum' -AlbumArtist 'Årtíst' -Year 2000 -ErrorAction Stop } | Should -Not -Throw

        Remove-Item -Recurse -Force $tmp
    }
}
