# Test script for compilation handling in Update-MusicFolderMetadata
# This simulates the compilation detection logic

function Test-CompilationLogic {
    param(
        [string]$AlbumArtist,
        [switch]$PreserveTrackArtists
    )

    Write-Output "Testing compilation logic with AlbumArtist: '$AlbumArtist', PreserveTrackArtists: $PreserveTrackArtists"

    # Simulate the logic from Update-MusicFolderMetadata
    if ($AlbumArtist -and $AlbumArtist -ne '') {
        # For compilations (Various Artists), preserve individual track artists unless explicitly told not to
        if ($AlbumArtist -eq 'Various Artists' -or $AlbumArtist -eq 'V.A.' -or $AlbumArtist -eq 'VA') {
            Write-Output "  -> Detected as compilation album"
            Write-Output "  -> AlbumArtists will be set to: '$AlbumArtist'"
            if (-not $PreserveTrackArtists) {
                Write-Output "  -> Performers will be overwritten to: '$AlbumArtist' (PreserveTrackArtists is false)"
            } else {
                Write-Output "  -> Performers will be preserved (original track artists kept)"
            }
        } else {
            Write-Output "  -> Detected as regular album"
            Write-Output "  -> Both AlbumArtists and Performers will be set to: '$AlbumArtist'"
        }
    } else {
        Write-Output "  -> No album artist provided"
    }
    Write-Output ""
}

# Test cases
Write-Output "=== Compilation Logic Tests ==="
Test-CompilationLogic -AlbumArtist 'Various Artists' -PreserveTrackArtists
Test-CompilationLogic -AlbumArtist 'Various Artists' -PreserveTrackArtists:$false
Test-CompilationLogic -AlbumArtist 'V.A.' -PreserveTrackArtists
Test-CompilationLogic -AlbumArtist 'VA' -PreserveTrackArtists
Test-CompilationLogic -AlbumArtist 'The Beatles' -PreserveTrackArtists
Test-CompilationLogic -AlbumArtist 'Pink Floyd' -PreserveTrackArtists