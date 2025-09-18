<#
.SYNOPSIS
Merges numbered duplicate folders into the base folder.

.DESCRIPTION
Finds folders with names like "Album (2)", "Album (3)" and moves their contents into the base
folder, creating any missing subdirectories, then removes the duplicates. Honors -WhatIf.

.PARAMETER BasePath
Root path containing the folders.

.PARAMETER BaseName
Base folder name to consolidate into.

.EXAMPLE
Merge-MusicFolders -BasePath 'E:\\Music\\Artist' -BaseName '1997 - OK Computer'
#>
function Merge-MusicFolders {
    <#
    .SYNOPSIS
        Merges numbered music folders into a single base folder.

    .DESCRIPTION
        This function finds folders with a common base name and numbered suffixes (e.g., "Album (2)", "Album (3)")
        and moves all files from the numbered folders into the base folder. It then removes the empty numbered folders.

    .PARAMETER BasePath
        The root directory containing the music folders to merge.

    .PARAMETER BaseName
        The base name of the folders to merge (e.g., "0 - Bach - Complete Works for Organ").

    .PARAMETER WhatIf
        Shows what would happen without actually making changes.

    .EXAMPLE
        Merge-MusicFolders -BasePath "E:\_CorrectedMusic\Alain" -BaseName "0 - Bach - Complete Works for Organ"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BasePath,

        [Parameter(Mandatory=$true)]
        [string]$BaseName
    )

    $baseFolder = Join-Path $BasePath $BaseName

    # Find all folders that match the pattern: BaseName followed by optional space and (number)
    $pattern = "^" + [regex]::Escape($BaseName) + "\s*\(\d+\)$"
    $foldersToMerge = Get-ChildItem -Path $BasePath -Directory | Where-Object {
        $_.Name -match $pattern -or $_.Name -eq $BaseName
    }

    if ($foldersToMerge.Count -le 1) {
        Write-Output "No folders to merge found."
        return
    }

    # Ensure the base folder exists
    if (-not (Test-Path $baseFolder)) {
        if ($PSCmdlet.ShouldProcess($BaseName, "Create base folder")) {
            New-Item -ItemType Directory -Path $baseFolder -Force | Out-Null
        }
    }

    # Move files from numbered folders to base folder
    foreach ($folder in $foldersToMerge) {
        if ($folder.Name -eq $BaseName) { continue }

        $files = Get-ChildItem -Path $folder.FullName -File -Recurse
        foreach ($file in $files) {
            $relativePath = $file.FullName.Substring($folder.FullName.Length).TrimStart('\')
            $destination = Join-Path $baseFolder $relativePath

            $destinationDir = Split-Path $destination -Parent
            if (-not (Test-Path $destinationDir)) {
                if ($PSCmdlet.ShouldProcess($destinationDir, "Create directory")) {
                    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
                }
            }

            if ($PSCmdlet.ShouldProcess($file.FullName, "Move to $destination")) {
                Move-Item -Path $file.FullName -Destination $destination -Force
            }
        }

        # Remove empty folder
        if ((Get-ChildItem -Path $folder.FullName -Recurse -File).Count -eq 0) {
            if ($PSCmdlet.ShouldProcess($folder.FullName, "Remove empty folder")) {
                Remove-Item -Path $folder.FullName -Recurse -Force
            }
        }
    }

    Write-Output "Merge complete. Files moved to: $baseFolder"
}