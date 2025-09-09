function Measure-MusicStructure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]$Path,

        [switch]$Compliant,

        [string]$LogTo
    )

    begin {
        $audioExtensions = @(".mp3", ".wav", ".flac", ".aac", ".ogg", ".wma")
        $patternMain = '(?i)\\([^\\]+)\\\d{4} - [^\\]+\\\d{2} - .+\.[a-z0-9]+$'
        $patternDisc = '(?i)\\([^\\]+)\\\d{4} - [^\\]+\\Disc \d+\\\d{2} - .+\.[a-z0-9]+$'
        $results = @()
    }

    process {
        $folders = Get-ChildItem -LiteralPath $Path -Recurse -Directory | Sort-Object -Unique | ForEach-Object { $_.FullName }

        foreach ($folder in $folders) {
            Write-Host "🔍 Checking folder: $folder"

            $firstAudioFile = $null
            foreach ($extension in $audioExtensions) {
                $firstAudioFile = Get-ChildItem -LiteralPath $folder -File -Filter "*$extension" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($firstAudioFile) { break }
            }
            if (-not $firstAudioFile) { continue }

            $fullPath = $firstAudioFile.FullName
            if ($fullPath -match $patternMain -or $fullPath -match $patternDisc) {
                $artistFolderName = $matches[1]
                $artistFolderPath = ($fullPath -split '\\')[0..(($fullPath -split '\\').IndexOf($artistFolderName))] -join '\'
                $results += [PSCustomObject]@{ Status = 'Compliant'; Path = $artistFolderPath }
            }
            else {
                $badFolder = $firstAudioFile.DirectoryName
                $results += [PSCustomObject]@{ Status = 'Noncompliant'; Path = $badFolder }
                if ($LogTo) {
                    Add-Content -Path $LogTo -Value ("BadFolderStructur " + ($badFolder))
                }
            }
        }
    }

    end {
        $uniqueResults = $results | Group-Object -Property Path | ForEach-Object {
            [PSCustomObject]@{ Status = $_.Group[0].Status; Path = $_.Name }
        }

        if ($Compliant) {
            $uniqueResults | Where-Object { $_.Status -eq 'Compliant' } | Select-Object Path
        }
        else {
            $uniqueResults | Where-Object { $_.Status -eq 'Noncompliant' } | Select-Object Path
        }
        if ($LogTo) {
            Write-Host "✅ Measurement complete. Logs Saved at $LogTo"
        }
    }
}

function Save-TagsFromFolderStructure {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Path')]
        [string]$FolderPath,

        [string]$LogFile
    )

    begin {
        Add-Type -Path "C:\Users\resto\Documents\PowerShell\Modules\MusicPicturesDownloader\lib\taglib-sharp.dll"
        [TagLib.Id3v2.Tag]::DefaultVersion = 4
        [TagLib.Id3v2.Tag]::ForceDefaultVersion = $true

        $musicExtensions = @('.mp3', '.flac', '.m4a', '.ogg', '.wav', '.aac')

        if ($LogFile) {
            $logDir = Split-Path -Path $LogFile -Parent
            if (-not (Test-Path -Path $logDir)) {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }
            $badFolders = @{}
        }
    }

    process {
        # Safety: verify compliance before tagging
        $isCompliant = (Measure-MusicStructure -Path $FolderPath -Compliant | Where-Object { $_.Path -eq $FolderPath })
        if (-not $isCompliant) {
            Write-Warning "Skipping non-compliant folder: $FolderPath"
            if ($LogFile) { $badFolders[$FolderPath] = @("NonCompliant") }
            return
        }

        $musicFiles = Get-ChildItem -LiteralPath $FolderPath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $musicExtensions -contains $_.Extension.ToLower() }

        foreach ($file in $musicFiles) {
            $parts = $file.FullName -split '\\'

            # Extract album info
            $albumIndex = -1
            for ($i = $parts.Count - 2; $i -ge 0; $i--) {
                if ($parts[$i] -match '^(\d{4}) - (.+)$') {
                    $albumIndex = $i
                    $year = $matches[1]
                    $album = $matches[2]
                    break
                }
            }

            if ($albumIndex -ge 1) {
                $albumArtist = $parts[$albumIndex - 1]
                $fileName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)

                if ($fileName -match '^([\d-]+)\s*-\s*(.+)$') {
                    $trackNumber = $matches[1]
                    $title = $matches[2].Trim()

                    if ($trackNumber -match '^(?:CD)?(\d+)[.-](\d+)$') {
                        $discNumber = [uint]$matches[1]
                        $trackNumber = [uint]$matches[2]
                    }
                    else {
                        $discNumber = 1
                        $trackNumber = [uint]$trackNumber
                    }

                    try {
                        $tagFile = [TagLib.File]::Create($file.FullName)
                        $existingGenres = $tagFile.Tag.Genres

                        if ($WhatIfPreference) {
                            Write-Host "🔍 [WhatIf] Would tag: $($file.FullName)"
                            Write-Host ("    👥 Album Artist : {0}" -f $albumArtist)
                            Write-Host ("    🎤 Track Artist : {0}" -f $albumArtist)
                            Write-Host ("    💿 Album        : {0}" -f $album)
                            Write-Host ("    📅 Year         : {0}" -f $year)
                            Write-Host ("    💽 Disc         : {0}" -f $discNumber)
                            Write-Host ("    🔢 Track        : {0}" -f $trackNumber)
                            Write-Host ("    🎵 Title        : {0}" -f $title)
                            Write-Host ("    🎼 Genres       : {0}" -f (($existingGenres -join ', ') -replace '^\s*$', '<none>'))
                        }


                        
                        elseif ($PSCmdlet.ShouldProcess($file.FullName, "Update tags")) {
                            
                            
                            # Actual tagging
                            $tagFile.Tag.Title = ""
                            $tagFile.Tag.Performers = @()
                            $tagFile.Tag.AlbumArtists = @()
                            $tagFile.Tag.Album = ""
                            $tagFile.Tag.Comment = ""
                            $tagFile.Tag.Year = 0
                            $tagFile.Tag.Track = 0
                            $tagFile.Tag.Disc = 0
                            $tagFile.Tag.Composers = @()

                            if ($existingGenres) { $tagFile.Tag.Genres = $existingGenres }

                            $tagFile.Tag.Performers = @($albumArtist)
                            $tagFile.Tag.AlbumArtists = @($albumArtist)
                            $tagFile.Tag.Album = $album
                            $tagFile.Tag.Year = [uint]$year
                            $tagFile.Tag.Track = [uint]$trackNumber
                            $tagFile.Tag.Disc = [uint]$discNumber
                            $tagFile.Tag.Title = $title

                            $tagFile.Save()
                            Write-Host "✅ Retagged: $($file.Name)"
                            
                        }
                    }
                    catch {
                        Write-Warning "⚠️ Failed to tag: $($file.FullName) — $_"
                        if ($LogFile) { $badFolders[$FolderPath] += "FailedTagging" }
                    }
                }
                else {
                    Write-Warning "❌ Bad filename format: $fileName"
                    if ($LogFile) { $badFolders[$FolderPath] += "WrongTitleFormat" }
                }
            }
            else {
                Write-Warning "❌ No album folder found: $($file.FullName)"
                if ($LogFile) { $badFolders[$FolderPath] += "ShallowPath" }
            }
        }
    }

    end {
        if ($LogFile -and $badFolders.Count -gt 0) {
            foreach ($folder in $badFolders.Keys) {
                $reasons = ($badFolders[$folder] | Sort-Object -Unique) -join ", "
                [System.IO.File]::AppendAllText($LogFile, "$reasons`: $folder`r`n", [System.Text.Encoding]::UTF8)
            }
            Write-Host "📝 Bad folders logged to: $LogFile"
        }
    }
}


#Get-ChildItem -LiteralPath E:\ -Directory | 
#Select-Object -First 10 | 
#Measure-MusicStructure -Compliant -LogTo "C:\Logs\MusicStructureLog.txt" | #BadFolderStructur E:\_testb\220 Greatest Old Songs [MP3-128 & 320kbps]
#Save-TagsFromFolderStructure -LogFile "C:\Logs\BadFolders.log" -WhatIf
#Measure-MusicStructure -Path (Get-ChildItem -Path E:\ -Directory |Select-Object -first 10) -Compliant -LogTo "C:\Logs\MusicStructureLog.txt" | Save-TagsFromFolderStructure -LogFile "C:\Logs\BadFolders.log" -WhatIf
#Measure-MusicStructure -Path E: -Compliant |
# Save-TagsFromFolderStructure -LogFile "C:\Logs\BadFolders.log" -WhatIf
