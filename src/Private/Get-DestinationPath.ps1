function Get-DestinationPath {
    param (
        [Parameter(Mandatory)]
        [string]$SourcePath,
        
        [Parameter(Mandatory)]
        [string]$DestinationFolder
    )
    
    # Extract artist and album from the path (same logic as Move-GoodFolders)
    $parentPath = Split-Path $SourcePath -Parent
    $artist = Split-Path $parentPath -Leaf

    # Handle different path scenarios
    if ($parentPath -match '^[A-Za-z]:\\$') {
        # Parent is drive root (e.g., "E:\") - current folder is the artist
        $artist = Split-Path $SourcePath -Leaf
        $album = ""  # No album subfolder
    } elseif ($artist -match '^([A-Za-z]):\\(.+)$') {
        $artist = $matches[2]
        $album = Split-Path $SourcePath -Leaf
    } else {
        $album = Split-Path $SourcePath -Leaf
    }

    $artistDest = Join-Path $DestinationFolder $artist
    if ($album) {
        $destinationPath = Join-Path $artistDest $album
    } else {
        $destinationPath = $artistDest
    }
    
    return $destinationPath
}
