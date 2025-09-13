function Get-MusicFolderStructureSummary {
    <#
    .SYNOPSIS
        Analyzes and summarizes music folder structure analysis results.

    .DESCRIPTION
        Takes the output from Find-BadMusicFolderStructure -AnalyzeStructure and provides
        a comprehensive summary of folder types, confidence levels, and recommendations.

    .PARAMETER AnalysisResults
        The results from Find-BadMusicFolderStructure with -AnalyzeStructure parameter.

    .PARAMETER OutputFormat
        Format for the output. Valid values: 'Table', 'List', 'JSON'.

    .EXAMPLE
        $results = Find-BadMusicFolderStructure -StartingPath 'E:\Music' -AnalyzeStructure
        Get-MusicFolderStructureSummary -AnalysisResults $results

    .EXAMPLE
        $results = Find-BadMusicFolderStructure -StartingPath 'E:\Music' -AnalyzeStructure
        Get-MusicFolderStructureSummary -AnalysisResults $results -OutputFormat JSON
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject[]]$AnalysisResults,

        [ValidateSet('Table', 'List', 'JSON')]
        [string]$OutputFormat = 'Table'
    )

    begin {
        $collectedResults = @()
    }

    process {
        $collectedResults += $AnalysisResults
    }

    end {
        # Filter out results without structure analysis
        $analyzedResults = $collectedResults | Where-Object { $_.StructureType }

        if (-not $analyzedResults) {
            Write-Warning "No structure analysis results found. Make sure to use -AnalyzeStructure parameter with Find-BadMusicFolderStructure."
            return
        }

        # Group by structure type
        $structureSummary = $analyzedResults | Group-Object -Property StructureType | ForEach-Object {
            $type = $_.Name
            $count = $_.Count
            $avgConfidence = [math]::Round(($_.Group | Measure-Object -Property Confidence -Average).Average, 2)
            $examples = $_.Group | Select-Object -First 3 | ForEach-Object {
                Split-Path $_.Path -Leaf
            }

            [PSCustomObject]@{
                StructureType = $type
                Count = $count
                AverageConfidence = $avgConfidence
                Examples = $examples -join ", "
            }
        }

        # Calculate overall statistics
        $totalAnalyzed = $analyzedResults.Count
        $highConfidence = ($analyzedResults | Where-Object { $_.Confidence -ge 0.8 }).Count
        $needsReview = ($analyzedResults | Where-Object { $_.StructureType -eq "MixedAlbum" -or $_.StructureType -eq "AmbiguousStructure" }).Count

        # Get recommendations for ambiguous cases
        $ambiguousCases = $analyzedResults | Where-Object {
            $_.StructureType -eq "MixedAlbum" -or
            $_.StructureType -eq "AmbiguousStructure" -or
            $_.Confidence -lt 0.5
        }

        $summary = [PSCustomObject]@{
            Timestamp = Get-Date
            TotalFoldersAnalyzed = $totalAnalyzed
            HighConfidenceFolders = $highConfidence
            NeedsReview = $needsReview
            StructureBreakdown = $structureSummary
            AmbiguousCases = $ambiguousCases | Select-Object Path, StructureType, Confidence, @{Name="Recommendations"; Expression={$_.Recommendations}}
        }

        # Output based on format
        switch ($OutputFormat) {
            'JSON' {
                $summary | ConvertTo-Json -Depth 5
            }
            'List' {
                Write-Host "🎵 Music Folder Structure Analysis Summary" -ForegroundColor Cyan
                Write-Host "========================================" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "📊 Overall Statistics:" -ForegroundColor Yellow
                Write-Host "  Total folders analyzed: $($summary.TotalFoldersAnalyzed)"
                Write-Host "  High confidence (>80%): $($summary.HighConfidenceFolders)"
                Write-Host "  Needs manual review: $($summary.NeedsReview)"
                Write-Host ""

                Write-Host "📁 Structure Breakdown:" -ForegroundColor Yellow
                foreach ($type in $summary.StructureBreakdown) {
                    $confidenceColor = switch ($type.AverageConfidence) {
                        { $_ -ge 0.8 } { "Green" }
                        { $_ -ge 0.5 } { "Yellow" }
                        default { "Red" }
                    }
                    Write-Host "  $($type.StructureType): $($type.Count) folders (avg confidence: $($type.AverageConfidence))" -ForegroundColor $confidenceColor
                    if ($type.Examples) {
                        Write-Host "    Examples: $($type.Examples)" -ForegroundColor Gray
                    }
                }

                if ($summary.AmbiguousCases.Count -gt 0) {
                    Write-Host ""
                    Write-Host "⚠️  Cases Needing Review:" -ForegroundColor Red
                    foreach ($case in $summary.AmbiguousCases | Select-Object -First 5) {
                        Write-Host "  $(Split-Path $case.Path -Leaf) - $($case.StructureType) ($($case.Confidence))" -ForegroundColor Red
                    }
                    if ($summary.AmbiguousCases.Count -gt 5) {
                        Write-Host "  ... and $($summary.AmbiguousCases.Count - 5) more" -ForegroundColor Red
                    }
                }
            }
            default {
                # Table format - return the summary object
                $summary
            }
        }
    }
}