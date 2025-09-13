Describe "Get-FolderStructureAnalysis" {
    BeforeAll {
        # Import the module
        $modulePath = Join-Path $PSScriptRoot "..\..\MusicFolderChecker.psm1"
        Import-Module $modulePath -Force

        # Test fixtures path
        $fixturesPath = Join-Path $PSScriptRoot "fixtures"
    }

    Context "Artist Folder Detection" {
        It "Should correctly identify Radiohead as an Artist Folder" {
            $result = Get-FolderStructureAnalysis -Path (Join-Path $fixturesPath "Radiohead")

            $result.StructureType | Should -Be "ArtistFolder"
            $result.Confidence | Should -BeGreaterThan 0.8
            $result.Details | Should -Contain "Artist folder with 2 album subfolders"
        }

        It "Should have high confidence for proper artist structure" {
            $result = Get-FolderStructureAnalysis -Path (Join-Path $fixturesPath "Radiohead")
            $result.Confidence | Should -BeGreaterThan 0.8
        }
    }

    Context "Simple Album Detection" {
        It "Should correctly identify '1995 - The Bends' as a Simple Album" {
            $result = Get-FolderStructureAnalysis -Path (Join-Path $fixturesPath "1995 - The Bends")

            $result.StructureType | Should -Be "SimpleAlbum"
            $result.Confidence | Should -BeGreaterThan 0.7
        }
    }

    Context "Mixed Album Detection" {
        It "Should detect MixedAlbum as ambiguous (MIXED STRUCTURE)" {
            $result = Get-FolderStructureAnalysis -Path (Join-Path $fixturesPath "MixedAlbum")

            $result.StructureType | Should -Be "MixedAlbum"
            $result.Confidence | Should -BeLessThan 0.5
            $result.Details | Should -Contain "MIXED STRUCTURE"
            $result.Recommendations | Should -Contain "MANUAL REVIEW REQUIRED"
        }
    }

    Context "Multi-Disc Album Detection" {
        It "Should correctly identify MultiDisc as a Multi-Disc Album" {
            $result = Get-FolderStructureAnalysis -Path (Join-Path $fixturesPath "MultiDisc")

            $result.StructureType | Should -Be "MultiDiscAlbum"
            $result.Confidence | Should -BeGreaterThan 0.7
        }
    }

    Context "Compilation Folder Detection" {
        It "Should correctly identify Various Artists as a Compilation Folder" {
            $result = Get-FolderStructureAnalysis -Path (Join-Path $fixturesPath "Various Artists")

            $result.StructureType | Should -Be "CompilationFolder"
            $result.Confidence | Should -BeGreaterThan 0.6
        }
    }

    Context "Metadata Collection" {
        It "Should collect correct metadata for Radiohead folder" {
            $result = Get-FolderStructureAnalysis -Path (Join-Path $fixturesPath "Radiohead")

            $result.Metadata.HasDirectAudio | Should -Be $false
            $result.Metadata.DirectAudioCount | Should -Be 0
            $result.Metadata.AlbumSubfolderCount | Should -Be 2
            $result.Metadata.AlbumSubfolderAudioCount | Should -Be 2
        }

        It "Should collect correct metadata for MixedAlbum folder" {
            $result = Get-FolderStructureAnalysis -Path (Join-Path $fixturesPath "MixedAlbum")

            $result.Metadata.HasDirectAudio | Should -Be $true
            $result.Metadata.DirectAudioCount | Should -Be 1
            $result.Metadata.AlbumSubfolderCount | Should -Be 1
            $result.Metadata.AlbumSubfolderAudioCount | Should -Be 1
        }
    }

    Context "Confidence Scoring" {
        It "Should give high confidence to clear structures" {
            $artistResult = Get-FolderStructureAnalysis -Path (Join-Path $fixturesPath "Radiohead")
            $albumResult = Get-FolderStructureAnalysis -Path (Join-Path $fixturesPath "1995 - The Bends")

            $artistResult.Confidence | Should -BeGreaterThan 0.8
            $albumResult.Confidence | Should -BeGreaterThan 0.7
        }

        It "Should give low confidence to ambiguous structures" {
            $mixedResult = Get-FolderStructureAnalysis -Path (Join-Path $fixturesPath "MixedAlbum")

            $mixedResult.Confidence | Should -BeLessThan 0.5
        }
    }

    Context "Recommendations" {
        It "Should provide appropriate recommendations for mixed structures" {
            $result = Get-FolderStructureAnalysis -Path (Join-Path $fixturesPath "MixedAlbum")

            $result.Recommendations | Should -Contain "MANUAL REVIEW REQUIRED"
            $result.Recommendations | Should -Contain "Option 1: Process root files as main album, ignore subfolders"
            $result.Recommendations | Should -Contain "Option 2: Process each subfolder as separate album"
        }

        It "Should provide processing recommendations for clear structures" {
            $result = Get-FolderStructureAnalysis -Path (Join-Path $fixturesPath "Radiohead")

            $result.Recommendations | Should -Contain "Process as artist 'Radiohead' with 2 albums"
        }
    }
}