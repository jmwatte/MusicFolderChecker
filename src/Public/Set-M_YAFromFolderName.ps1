<#
.SYNOPSIS
    Sets album and year metadata on audio files based on the parent folder name in "Year - Album" format.

.DESCRIPTION
    Set-M-YAFromFolderName parses the parent folder name assuming the format "1234 - Album Name"
    and applies the extracted year (1234) and album name ("Album Name") to all audio files in that folder.
    It only updates the Album and Year tags, leaving other metadata (like Album Artist) unchanged.
    This is a helper function for cleaning up metadata in folders that follow the "Year - Album" naming convention.

.PARAMETER FolderPath
    Path to the folder containing audio files. The folder name must follow the "Year - Album" format (e.g., "2023 - My Album").

.INPUTS
    System.String
    You can pipe folder paths to Set-M-YAFromFolderName.

.OUTPUTS
    PSCustomObject
    Returns an object with ProcessedFiles and FailedFiles properties.

.EXAMPLE
    Set-M-YAFromFolderName -FolderPath "C:\Music\2023 - My Album"
    Parses "2023 - My Album" and sets Year=2023, Album="My Album" on all audio files in the folder.

.EXAMPLE
    "C:\Music\2023 - My Album", "C:\Music\2024 - Another Album" | Set-M-YAFromFolderName
    Processes multiple folders from the pipeline.

.EXAMPLE
    Set-M-YAFromFolderName -FolderPath "C:\Music\2023 - My Album" -WhatIf
    Previews the changes without applying them.

.NOTES
    Author: MusicFolderChecker Module
    Requires TagLib-Sharp.dll for audio file processing
    Only updates Album and Year tags; preserves all other metadata
    Supports WhatIf for safe preview of operations
    Skips non-audio files and logs failures
#>

function Set-M_YAFromFolderName {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$FolderPath
    )

    begin {
        $musicExtensions = @('.mp3', '.flac', '.m4a', '.ogg', '.wav', '.aac')
        $processedFiles = @()
        $failedFiles = @()
    }

    process {
        if (-not (Test-Path -LiteralPath $FolderPath)) {
            Write-Warning "Folder not found: $FolderPath"
            return
        }

        # Parse folder name: expect format "1234 - Album Name"
        $folderName = Split-Path $FolderPath -Leaf
        if ($folderName -notmatch '^(\d{4})\s*-\s*(.+)$') {
            Write-Warning "Folder name does not match 'Year - Album' format: $folderName"
            return
        }

        $year = [int]$matches[1]
        $album = $matches[2].Trim()

        Write-Verbose "Parsed folder '$folderName': Year=$year, Album='$album'"

        # Get audio files
        $audioFiles = Get-ChildItem -LiteralPath $FolderPath -Recurse -File -ErrorAction SilentlyContinue |
                      Where-Object { $musicExtensions -contains $_.Extension.ToLower() }

        if ($audioFiles.Count -eq 0) {
            Write-Warning "No audio files found in: $FolderPath"
            return
        }

        foreach ($file in $audioFiles) {
            try {
                $tagFile = [TagLib.File]::Create($file.FullName)

                if ($PSCmdlet.ShouldProcess($file.FullName, "Set Album='$album', Year=$year")) {
                    $tagFile.Tag.Album = $album
                    $tagFile.Tag.Year = [uint]$year
                    $tagFile.Save()
                    Write-Verbose "Updated: $($file.FullName)"
                    $processedFiles += $file.FullName
                }
            }
            catch {
                Write-Warning "Failed to update metadata for: $($file.FullName) - $_"
                $failedFiles += [PSCustomObject]@{
                    FilePath = $file.FullName
                    Error = $_.Exception.Message
                }
            }
        }
    }

    end {
        [PSCustomObject]@{
            ProcessedFiles = $processedFiles
            FailedFiles = $failedFiles
        }
    }
}