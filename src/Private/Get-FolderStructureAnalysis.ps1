function Get-FolderStructureAnalysis {
    <#
    .SYNOPSIS
        Analyzes a folder's structure to determine its type and confidence level.

    .DESCRIPTION
        Performs semantic analysis of music folder structures beyond simple pattern matching.
        Uses multiple criteria including naming patterns, tag consistency, and structural hints
        to classify folders and provide confidence scores.

    .PARAMETER Path
        The folder path to analyze.

    .PARAMETER AudioExtensions
        Array of audio file extensions to consider.

    .OUTPUTS
        PSCustomObject with StructureType, Confidence, Details, and Recommendations
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        [string[]]$AudioExtensions = @('.mp3', '.flac', '.m4a', '.ogg', '.wav', '.aac', '.wma', '.ape', '.dsd', '.dsd', '.aiff', '.aif')
    )

    # Define structure types as strings (PowerShell enum support varies)
    $structureTypes = @{
        ArtistFolder = "ArtistFolder"
        SimpleAlbum = "SimpleAlbum"
        MixedAlbum = "MixedAlbum"
        MultiDiscAlbum = "MultiDiscAlbum"
        CompilationFolder = "CompilationFolder"
        BoxSet = "BoxSet"
        AmbiguousStructure = "AmbiguousStructure"
        NonMusicFolder = "NonMusicFolder"
    }

    # Normalize path to handle accidentally escaped brackets
    $Path = $Path -replace '`\[', '[' -replace '`\]', ']'

    # Get folder information
    $folderName = Split-Path $Path -Leaf

    # Analyze subfolders
    $subfolders = Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue
    $albumSubfolders = $subfolders | Where-Object { $_.Name -match '^\d{4}\s*-\s*.+' }
    $discSubfolders = $subfolders | Where-Object { $_.Name -match '(?i)(?:disc|cd)\s*\d+' }
    $compilationSubfolders = $subfolders | Where-Object { $_.Name -match '^\d{4}\s*-\s*.+\s*-\s*.+' } # Artist - Album pattern

    # Analyze audio files (search recursively throughout the entire folder tree)
    $audioFiles = @()
    foreach ($ext in $AudioExtensions) {
        $audioFiles += Get-ChildItem -LiteralPath $Path -File -Filter "*$ext" -Recurse -ErrorAction SilentlyContinue
    }
    $hasDirectAudio = ($audioFiles | Where-Object { $_.DirectoryName -eq $Path }).Count -gt 0
    $totalAudioCount = $audioFiles.Count

    # Initialize analysis result
    $result = [PSCustomObject]@{
        Path = $Path
        FolderName = $folderName
        StructureType = $structureTypes.AmbiguousStructure
        Confidence = 0.0
        Details = @()
        Recommendations = @()
        Metadata = @{
            HasDirectAudio = $hasDirectAudio
            DirectAudioCount = ($audioFiles | Where-Object { $_.DirectoryName -eq $Path }).Count
            SubfolderCount = $subfolders.Count
            AlbumSubfolderCount = $albumSubfolders.Count
            DiscSubfolderCount = $discSubfolders.Count
            CompilationSubfolderCount = $compilationSubfolders.Count
            TotalSubfolderAudioCount = ($audioFiles | Where-Object { $_.DirectoryName -ne $Path }).Count
            AlbumSubfolderAudioCount = ($audioFiles | Where-Object { $_.FullName -like "$Path\*" -and $_.DirectoryName -ne $Path }).Count
            TotalAudioCount = $audioFiles.Count
        }
    }

    # Analysis logic with confidence scoring

    # 0. Check for Box Set (highest priority - before Artist Folder)
    if ($albumSubfolders.Count -gt 2 -and -not $hasDirectAudio -and $albumSubfolderAudioCount -gt 0) {
        # Analyze if this looks like a box set
        $boxSetIndicators = 0
        $totalDiscsInBoxSet = 0
        $artistNames = @()

        # Check each album subfolder for disc structure
        foreach ($albumFolder in $albumSubfolders) {
            $albumDiscs = Get-ChildItem -LiteralPath $albumFolder.FullName -Directory -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -match '(?i)(?:disc|cd)\s*\d+' }
            $totalDiscsInBoxSet += $albumDiscs.Count

            # Try to extract artist from album folder name (for compilations)
            if ($albumFolder.Name -match '^(.+?)\s*-\s*(.+)$') {
                if ($matches[1]) {
                    $artistNames += $matches[1].Trim()
                }
            }
        }

        # Box set indicators
        if ($folderName -match '(?i)(?:complete|collection|box|set|songbook)') { $boxSetIndicators++ }
        if ($albumSubfolders.Count -gt 3) { $boxSetIndicators++ } # Many albums suggest collection
        if ($totalDiscsInBoxSet -gt $albumSubfolders.Count) { $boxSetIndicators++ } # Multiple discs per album
        if ($artistNames.Count -gt 0 -and ($artistNames | Select-Object -Unique).Count -le 2) { $boxSetIndicators++ } # Consistent artist

        if ($boxSetIndicators -gt 2) {
            $result.StructureType = $structureTypes.BoxSet
            $result.Confidence = 0.85
            $result.Details += "BOX SET DETECTED: $($albumSubfolders.Count) albums, $totalDiscsInBoxSet total discs"
            $result.Details += "Collection appears to be: '$folderName'"
            $result.Recommendations += "Process as box set - each album subfolder is a separate release"
            $result.Recommendations += "Consider processing albums individually or as collection"
            $result.Metadata.BoxSetIndicators = $boxSetIndicators
            $result.Metadata.TotalDiscsInBoxSet = $totalDiscsInBoxSet
            return $result
        }
    }

    # 1. Check for Artist Folder (highest confidence)
    if ($albumSubfolders.Count -gt 0 -and -not $hasDirectAudio -and $albumSubfolderAudioCount -gt 0) {
        $confidence = 0.9

        # Reduce confidence for suspicious patterns
        if ($folderName -match '^(?:[A-Z]:|[Cc]ompilations?|[Tt]emp|[Bb]ackup)$') {
            $confidence -= 0.3
            $result.Details += "Suspicious folder name for artist: '$folderName'"
        }

        if ($albumSubfolders.Count -lt 2) {
            $confidence -= 0.2
            $result.Details += "Only $($albumSubfolders.Count) album subfolder(s) found"
        }

        $result.StructureType = $structureTypes.ArtistFolder
        $result.Confidence = [math]::Max(0.1, $confidence)
        $result.Details += "Artist folder with $($albumSubfolders.Count) album subfolders"
        $result.Recommendations += "Process as artist '$folderName' with $($albumSubfolders.Count) albums"
        return $result
    }

    # 2. Check for Simple Album
    if ($hasDirectAudio -and $albumSubfolders.Count -eq 0 -and $subfolders.Count -le 2) {
        $confidence = 0.8

        if ($folderName -match '^\d{4} - .+') {
            $confidence += 0.1
            $result.Details += "Folder name matches album pattern"
        } else {
            $confidence -= 0.2
            $result.Details += "Folder name doesn't match album pattern"
        }

        if ($discSubfolders.Count -gt 0) {
            $result.StructureType = $structureTypes.MultiDiscAlbum
            $result.Confidence = 0.85
            $result.Details += "Multi-disc album with $($discSubfolders.Count) discs"
            $result.Recommendations += "Process as multi-disc album"
        } else {
            $result.StructureType = $structureTypes.SimpleAlbum
            $result.Confidence = $confidence
            $result.Details += "Simple album with $($audioFiles.Count) audio files"
            $result.Recommendations += "Process as single album"
        }
        return $result
    }

    # 3. Check for Mixed Album (AMBIGUOUS - needs review)
    if ($hasDirectAudio -and $albumSubfolders.Count -gt 0) {
        $result.StructureType = $structureTypes.MixedAlbum
        $result.Confidence = 0.3
        $result.Details += "MIXED STRUCTURE: $($audioFiles.Count) audio files at root + $($albumSubfolders.Count) album subfolders"
        $result.Details += "This requires manual review - unclear if subfolders are bonus content or separate albums"
        $result.Recommendations += "MANUAL REVIEW REQUIRED: Determine if subfolders are part of this album or separate releases"
        $result.Recommendations += "Option 1: Process root files as main album, ignore subfolders"
        $result.Recommendations += "Option 2: Process each subfolder as separate album"
        return $result
    }

    # 4. Check for Compilation Folder
    if ($compilationSubfolders.Count -gt 0 -and -not $hasDirectAudio) {
        $result.StructureType = $structureTypes.CompilationFolder
        $result.Confidence = 0.7
        $result.Details += "Compilation folder with $($compilationSubfolders.Count) artist-album subfolders"
        $result.Recommendations += "Process as compilation - each subfolder is Artist - Album"
        return $result
    }

    # 5. Check for Multi-Disc Album (alternative detection)
    if ($discSubfolders.Count -gt 1 -and -not $hasDirectAudio) {
        $result.StructureType = $structureTypes.MultiDiscAlbum
        $result.Confidence = 0.8
        $result.Details += "Multi-disc album with $($discSubfolders.Count) discs"
        $result.Recommendations += "Process as multi-disc album"
        return $result
    }

    # 6. Default: Ambiguous or Non-Music
    if ($totalAudioCount -gt 0) {
        $result.StructureType = $structureTypes.AmbiguousStructure
        $result.Confidence = 0.2
        $result.Details += "Ambiguous structure: audio files found but unclear organization"
        $result.Recommendations += "Manual review recommended - unclear folder structure"
    } else {
        $result.StructureType = $structureTypes.NonMusicFolder
        $result.Confidence = 0.9
        $result.Details += "No audio files found in folder or subfolders"
        $result.Recommendations += "Skip this folder - no music content detected"
    }

    return $result
}