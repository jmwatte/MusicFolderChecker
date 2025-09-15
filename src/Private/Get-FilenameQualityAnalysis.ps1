function Get-FilenameQualityAnalysis {
    <#
    .SYNOPSIS
        Analyzes audio filenames to determine if they should be preserved or renamed to standardized format.

    .PARAMETER AudioFiles
        Array of audio file objects to analyze.

    .PARAMETER MusicExtensions
        Array of music file extensions to consider.

    .OUTPUTS
        PSCustomObject with analysis results and recommendation.

    .NOTES
        Track number detection supports various formats:
        - Standard: 01, 1., 001, 1-, 01_, 01
        - Parentheses: (01), (1), (001)
        - Brackets: [01], [1], [001]
        - Separators: -, _, space
    #>
    param(
        [Parameter(Mandatory=$true)]
        [object[]]$AudioFiles,

        [Parameter(Mandatory=$true)]
        [string[]]$MusicExtensions
    )

    # Initialize analysis variables
    $totalFiles = 0
    $goodPatternFiles = 0
    $consistentTrackNumbers = 0
    $reasonableLengthFiles = 0
    $filenameLengths = @()
    $trackNumberPatterns = @()
    $filenamePatterns = @()

    foreach ($file in $AudioFiles) {
        if ($MusicExtensions -notcontains $file.Extension.ToLower()) { continue }

        $totalFiles++
        # Handle both FileInfo objects and generic objects
        $filename = if ($file -is [System.IO.FileInfo]) {
            [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        } else {
            [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        }
        $filenameLengths += $filename.Length

        # Check for track number patterns (comprehensive detection)
        # Supports: 01, 1., 001, 1-, 01_, 01 , (01), [01], etc.
        $hasTrackNumber = $filename -match '^(?:\d{1,3}|\d{1,3}\.|\(\d{1,3}\)|\[\d{1,3}\])\s*[-_\s]'
        if ($hasTrackNumber) {
            $trackNumberPatterns += $matches[0].Trim()
            $consistentTrackNumbers++
        }

        # Check for reasonable filename patterns
        # Good patterns: "01 - Title", "1. Title", "(01) Title", "[01] Title", etc.
        $goodPattern = $filename -match '^(?:\d{1,3}|\d{1,3}\.|\(\d{1,3}\)|\[\d{1,3}\])\s*[-_\s]\s*.{3,}'
        if ($goodPattern) {
            $goodPatternFiles++
        }

        # Check for reasonable length (not too short, not too long)
        if ($filename.Length -ge 3 -and $filename.Length -le 80) {
            $reasonableLengthFiles++
        }

        # Analyze filename patterns for consistency
        $pattern = $filename -replace '\d+', '#'
        $filenamePatterns += $pattern
    }

    # Calculate analysis metrics
    $goodPatternRatio = if ($totalFiles -gt 0) { $goodPatternFiles / $totalFiles } else { 0 }
    $trackNumberRatio = if ($totalFiles -gt 0) { $consistentTrackNumbers / $totalFiles } else { 0 }
    $reasonableLengthRatio = if ($totalFiles -gt 0) { $reasonableLengthFiles / $totalFiles } else { 0 }

    # Calculate filename length variance (consistency)
    $avgLength = if ($filenameLengths.Count -gt 0) { ($filenameLengths | Measure-Object -Average).Average } else { 0 }
    $lengthVariance = if ($filenameLengths.Count -gt 1) {
        $sumSquares = ($filenameLengths | ForEach-Object { [math]::Pow($_ - $avgLength, 2) } | Measure-Object -Sum).Sum
        $sumSquares / ($filenameLengths.Count - 1)
    } else { 0 }

    # Check pattern consistency
    $uniquePatterns = $filenamePatterns | Select-Object -Unique
    $patternConsistencyRatio = if ($filenamePatterns.Count -gt 0) { 1 - ($uniquePatterns.Count / $filenamePatterns.Count) } else { 0 }

    # Determine recommendation based on analysis
    $shouldPreserve = $false
    $confidence = 0
    $reasons = @()

    # High confidence to rename (good filenames)
    if ($goodPatternRatio -ge 0.8 -and $trackNumberRatio -ge 0.7 -and $patternConsistencyRatio -ge 0.8) {
        $shouldPreserve = $false
        $confidence = 0.9
        $reasons += "High-quality, consistent naming patterns detected"
    }
    # Medium confidence to rename
    elseif ($goodPatternRatio -ge 0.6 -and $trackNumberRatio -ge 0.5) {
        $shouldPreserve = $false
        $confidence = 0.7
        $reasons += "Mostly good naming patterns with track numbers"
    }
    # Low confidence, mixed signals
    elseif ($goodPatternRatio -ge 0.4) {
        $shouldPreserve = $false
        $confidence = 0.5
        $reasons += "Mixed filename quality, leaning toward standardization"
    }
    # High confidence to preserve (bad filenames)
    elseif ($goodPatternRatio -le 0.2 -and $trackNumberRatio -le 0.3) {
        $shouldPreserve = $true
        $confidence = 0.8
        $reasons += "Poor filename quality with inconsistent patterns"
    }
    # Medium confidence to preserve
    elseif ($goodPatternRatio -le 0.4 -and $trackNumberRatio -le 0.5) {
        $shouldPreserve = $true
        $confidence = 0.6
        $reasons += "Inconsistent naming patterns suggest preservation"
    }
    else {
        # Default fallback
        $shouldPreserve = $false
        $confidence = 0.4
        $reasons += "Uncertain filename quality, defaulting to standardization"
    }

    # Additional factors
    if ($lengthVariance -gt 500) {
        $shouldPreserve = $true
        $confidence = [math]::Max($confidence, 0.7)
        $reasons += "High filename length variance indicates inconsistent naming"
    }

    if ($reasonableLengthRatio -lt 0.5) {
        $shouldPreserve = $true
        $confidence = [math]::Max($confidence, 0.6)
        $reasons += "Many filenames have unusual lengths"
    }

    # Return analysis results
    [PSCustomObject]@{
        TotalFiles = $totalFiles
        GoodPatternRatio = [math]::Round($goodPatternRatio, 2)
        TrackNumberRatio = [math]::Round($trackNumberRatio, 2)
        ReasonableLengthRatio = [math]::Round($reasonableLengthRatio, 2)
        PatternConsistencyRatio = [math]::Round($patternConsistencyRatio, 2)
        AverageLength = [math]::Round($avgLength, 1)
        LengthVariance = [math]::Round($lengthVariance, 1)
        ShouldPreserveFilenames = $shouldPreserve
        Confidence = [math]::Round($confidence, 2)
        Reasons = $reasons
        Recommendation = if ($shouldPreserve) { "Preserve" } else { "Rename" }
    }
}