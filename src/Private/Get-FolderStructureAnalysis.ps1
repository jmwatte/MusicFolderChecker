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
        Array of audio file extensions to consider when scanning for audio files within the folder tree.
        Defaults to common formats like '.mp3', '.flac', '.m4a', '.ogg', '.wav', '.aac', '.wma', '.ape', '.dsd', '.aiff', '.aif'.

    .PARAMETER UseConsensusHints
        Deprecated (kept for backward compatibility). Consensus-based hints are now always computed for
        ambiguous structures. This switch currently has no effect in that case. In the future it may enable
        extended hints for non-ambiguous structures.

    .OUTPUTS
        PSCustomObject with properties:
        - Path, FolderName
        - StructureType (ArtistFolder, SimpleAlbum, MixedAlbum, MultiDiscAlbum, CompilationFolder, BoxSet, AmbiguousStructure, NonMusicFolder)
        - Confidence (0.0 - 1.0)
        - Details (string[])
        - Recommendations (string[])
        - Metadata (hashtable: indicators and counts, e.g. HasDirectAudio, DiscSubfolderCount, ConsensusSuggestions)

    .EXAMPLE
        Get-FolderStructureAnalysis -Path 'D:\Music\Radiohead\1997 - OK Computer'
        Returns a classification and confidence for the specified folder.

    .EXAMPLE
        # For ambiguous or messy collections, enable consensus hints to surface album-like groups
        Get-FolderStructureAnalysis -Path 'D:\Music\_Unsorted\Collections' -UseConsensusHints
        # Output includes Metadata.ConsensusSuggestions with per-subfolder suggested Artist/Album/Year

    .NOTES
        Private helper. One function per file. No top-level execution. Follows module conventions.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        [string[]]$AudioExtensions = @('.mp3', '.flac', '.m4a', '.ogg', '.wav', '.aac', '.wma', '.ape', '.dsd', '.dsd', '.aiff', '.aif'),

        [switch]$UseConsensusHints
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

    # Check if path exists and is a folder
    if (-not (Test-Path -LiteralPath $Path)) {
        return [PSCustomObject]@{
            Path = $Path
            FolderName = Split-Path $Path -Leaf
            StructureType = "NonMusicFolder"
            Confidence = 0.9
            Details = @("Path does not exist")
            Recommendations = @("Verify the path exists")
            Metadata = @{ Exists = $false }
        }
    }

    $item = Get-Item -LiteralPath $Path
    if (-not $item.PSIsContainer) {
        return [PSCustomObject]@{
            Path = $Path
            FolderName = Split-Path $Path -Leaf
            StructureType = "NonMusicFolder"
            Confidence = 0.9
            Details = @("Path is a file, not a folder")
            Recommendations = @("Only folders can be analyzed for music structure")
            Metadata = @{ IsFile = $true; Extension = $item.Extension }
        }
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

    # Calculate album subfolder audio count
    $albumSubfolderAudioCount = 0
    foreach ($file in $audioFiles) {
        foreach ($albumFolder in $albumSubfolders) {
            if ($file.DirectoryName.StartsWith($albumFolder.FullName)) {
                $albumSubfolderAudioCount++
                break
            }
        }
    }

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
            AlbumSubfolderAudioCount = $albumSubfolderAudioCount
            TotalAudioCount = $audioFiles.Count
        }
    }

    # Analysis logic with confidence scoring

    # 0a. Prefer Multi-Disc classification when immediate subfolders are disc-like
    if ($discSubfolders.Count -gt 1 -and -not $hasDirectAudio) {
        $result.StructureType = $structureTypes.MultiDiscAlbum
        $result.Confidence = 0.85
        $result.Details += "Multi-disc album with $($discSubfolders.Count) discs (detected at parent level)"
        $result.Recommendations += "Process as multi-disc album"
        return $result
    }

    # 0a-2. If there is exactly one album-like subfolder that itself has disc subfolders, treat current as MultiDiscAlbum
    if (-not $hasDirectAudio -and $albumSubfolders.Count -eq 1) {
        try {
            $child = $albumSubfolders[0]
            $childDiscSubs = Get-ChildItem -LiteralPath $child.FullName -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)(?:disc|cd)\s*\d+' }
            if ($childDiscSubs.Count -gt 1) {
                $result.StructureType = $structureTypes.MultiDiscAlbum
                $result.Confidence = 0.8
                $result.Details += "Multi-disc album with $($childDiscSubs.Count) discs (detected in single album subfolder)"
                $result.Recommendations += "Process as multi-disc album"
                return $result
            }
        } catch { }
    }

    # 0b. Check for Box Set (before Artist Folder)
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
    if ($folderName -match '(?i)(?:complete|collection|box\s*set|box|set|songbook|years|anthology|works|recorded\s*works)') { $boxSetIndicators++ }
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

    # 1. Check for Compilation Folder (do this before generic ArtistFolder so it doesn't get shadowed)
    if ($compilationSubfolders.Count -gt 0 -and -not $hasDirectAudio) {
        $result.StructureType = $structureTypes.CompilationFolder
        $result.Confidence = 0.7
        $result.Details += "Compilation folder with $($compilationSubfolders.Count) artist-album subfolders"
        $result.Recommendations += "Process as compilation - each subfolder is Artist - Album"

        # Attach consensus suggestions for each artist-album subfolder to guide user actions
        try {
            $consensusSummaries = @()
            # Limit analysis to a reasonable number to avoid excessive work on giant collections
            $maxAnalyze = [Math]::Min(50, $compilationSubfolders.Count)
            foreach ($albumFolder in $compilationSubfolders | Select-Object -First $maxAnalyze) {
                $filesHere = Get-ChildItem -LiteralPath $albumFolder.FullName -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $AudioExtensions -contains $_.Extension.ToLower() }
                if ($filesHere.Count -lt 3) { continue }
                $cons = Get-FolderTagConsensus -Path $albumFolder.FullName -AudioExtensions $AudioExtensions -MinFiles 3
                if ($cons.FileCount -ge 3) {
                    $consensusSummaries += [PSCustomObject]@{
                        Folder = $albumFolder.FullName
                        Name = $albumFolder.Name
                        Suggested = $cons.SuggestedFolderName
                        Year = $cons.SuggestedYear
                        Album = $cons.SuggestedAlbum
                        Artist = $cons.SuggestedArtist
                        Confidence = $cons.Confidence
                    }
                }
            }
            if ($consensusSummaries.Count -gt 0) {
                $result.Metadata.ConsensusSuggestions = $consensusSummaries
                $result.Details += ("Consensus suggestions computed for {0} subfolder(s)" -f $consensusSummaries.Count)
                $top = $consensusSummaries | Sort-Object Confidence -Descending | Select-Object -First 3
                foreach ($s in $top) {
                    $result.Recommendations += ("Suggested: {0} — {1} - {2} ({3})" -f $s.Name, $s.Year, $s.Album, $s.Artist)
                }
            }
        } catch { }

        return $result
    }

    # 2. Check for Artist Folder (highest confidence after compilation check)
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

        # Attach consensus suggestions across album subfolders to guide next actions
        try {
            $consensusSummaries = @()
            $maxAnalyze = [Math]::Min(50, $albumSubfolders.Count)
            foreach ($albumFolder in $albumSubfolders | Select-Object -First $maxAnalyze) {
                $filesHere = Get-ChildItem -LiteralPath $albumFolder.FullName -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $AudioExtensions -contains $_.Extension.ToLower() }
                if ($filesHere.Count -lt 3) { continue }
                $cons = Get-FolderTagConsensus -Path $albumFolder.FullName -AudioExtensions $AudioExtensions -MinFiles 3
                if ($cons.FileCount -ge 3) {
                    $consensusSummaries += [PSCustomObject]@{
                        Folder = $albumFolder.FullName
                        Name = $albumFolder.Name
                        Suggested = $cons.SuggestedFolderName
                        Year = $cons.SuggestedYear
                        Album = $cons.SuggestedAlbum
                        Artist = $cons.SuggestedArtist
                        Confidence = $cons.Confidence
                    }
                }
            }
            if ($consensusSummaries.Count -gt 0) {
                $result.Metadata.ConsensusSuggestions = $consensusSummaries
                $result.Details += ("Consensus suggestions computed for {0} album subfolder(s)" -f $consensusSummaries.Count)
                $top = $consensusSummaries | Sort-Object Confidence -Descending | Select-Object -First 3
                foreach ($s in $top) {
                    $result.Recommendations += ("Suggested: {0} — {1} - {2}" -f $s.Name, $s.Year, $s.Album)
                }
            }
        } catch { }

        return $result
    }

    # 3. Check for Compilation (Various Artists)
    if ($hasDirectAudio -and $albumSubfolders.Count -eq 0 -and $subfolders.Count -le 2) {
        $isCompilation = $false
        
        # Check folder name for compilation indicators
        if ($folderName -match '^(?i)(VA|Various Artists?|V\.A\.?)') {
            $isCompilation = $true
        }
        
        # Check for large number of files (compilations often have many tracks)
        if ($audioFiles.Count -gt 50) {
            $isCompilation = $true
        }
        
        if ($isCompilation) {
            $result.StructureType = $structureTypes.CompilationFolder
            $result.Confidence = 0.8
            $result.Details += "Compilation detected: $($audioFiles.Count) tracks from various artists"
            $result.Recommendations += "Process as compilation - avoid setting uniform year/artist on all tracks"
            $result.Recommendations += "Consider using -PreserveTrackArtists to keep original track artists"
            return $result
        }
    }

    # 4. Check for Simple Album
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

    # 5. Check for Mixed Album (AMBIGUOUS - needs review)
    if ($hasDirectAudio -and $albumSubfolders.Count -gt 0) {
        $result.StructureType = $structureTypes.MixedAlbum
        $result.Confidence = 0.3
        # Add a plain marker for exact-match based tests, and a detailed string for humans
        $result.Details += "MIXED STRUCTURE"
        $result.Details += "MIXED STRUCTURE: $($audioFiles.Count) audio files at root + $($albumSubfolders.Count) album subfolders"
        $result.Details += "This requires manual review - unclear if subfolders are bonus content or separate albums"
        # Include a plain recommendation line as well as detailed guidance
        $result.Recommendations += "MANUAL REVIEW REQUIRED"
        $result.Recommendations += "MANUAL REVIEW REQUIRED: Determine if subfolders are part of this album or separate releases"
        $result.Recommendations += "Option 1: Process root files as main album, ignore subfolders"
        $result.Recommendations += "Option 2: Process each subfolder as separate album"
        return $result
    }

    # 6. Check for Multi-Disc Album (alternative detection)
    if ($discSubfolders.Count -gt 1 -and -not $hasDirectAudio) {
        $result.StructureType = $structureTypes.MultiDiscAlbum
        $result.Confidence = 0.8
        $result.Details += "Multi-disc album with $($discSubfolders.Count) discs"
        $result.Recommendations += "Process as multi-disc album"
        return $result
    }

    # 7. Default: Ambiguous or Non-Music, with tag-consensus assistance
    if ($audioFiles.Count -gt 0) {
        # Attempt consensus-based hints for folders that don't match naming patterns
        $result.StructureType = $structureTypes.AmbiguousStructure
        $result.Confidence = 0.2
        $result.Details += "Ambiguous structure: audio files found but unclear organization"

        # Always compute consensus-based hints for ambiguous structures
        # Try to detect album-like sub-subfolders (e.g., nested under 'vol1', etc.)
        $deepAlbumCandidates = Get-ChildItem -LiteralPath $Path -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -ne $Path -and (Get-ChildItem -LiteralPath $_.FullName -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $AudioExtensions -contains $_.Extension.ToLower() }).Count -gt 0 } |
            Sort-Object FullName -Unique

        $consensusSummaries = @()
        $albumLikeCount = 0
        foreach ($cand in $deepAlbumCandidates) {
            # Skip the root itself
            if ($cand.FullName -eq $Path) { continue }
            # Gather consensus for each leaf folder that directly contains audio or disc subfolders
            $filesHere = Get-ChildItem -LiteralPath $cand.FullName -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $AudioExtensions -contains $_.Extension.ToLower() }
            if ($filesHere.Count -lt 3) { continue }

            $cons = Get-FolderTagConsensus -Path $cand.FullName -AudioExtensions $AudioExtensions -MinFiles 3
            if ($cons.FileCount -ge 3) {
                $albumLikeCount++
                $consensusSummaries += [PSCustomObject]@{
                    Folder = $cand.FullName
                    Name = $cand.Name
                    Suggested = $cons.SuggestedFolderName
                    Year = $cons.SuggestedYear
                    Album = $cons.SuggestedAlbum
                    Artist = $cons.SuggestedArtist
                    Confidence = $cons.Confidence
                }
            }
        }

        if ($albumLikeCount -ge 3) {
            # If many album-like groups exist and folder name hints at collection, elevate to BoxSet with moderate confidence
            $nameHint = ($folderName -match '(?i)(complete|collection|box|set|songbook)')
            $result.StructureType = $structureTypes.BoxSet
            $result.Confidence = if ($nameHint) { 0.7 } else { 0.6 }
            $result.Details += "Consensus-based BoxSet hint: $albumLikeCount album-like groups detected"
            if ($nameHint) { $result.Details += "Folder name contains collection keyword" }
            $result.Recommendations += "Process as box set or confirm per-album processing"
        } else {
            $result.Recommendations += "Manual review recommended - unclear folder structure"
        }

        # Attach consensus suggestions to metadata so interactive flows can propose defaults
        $result.Metadata.ConsensusSuggestions = $consensusSummaries
        $result.Metadata.AlbumLikeCount = $albumLikeCount
    } else {
        $result.StructureType = $structureTypes.NonMusicFolder
        $result.Confidence = 0.9
        $result.Details += "No audio files found in folder or subfolders"
        $result.Recommendations += "Skip this folder - no music content detected"
    }

    return $result
}