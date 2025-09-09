function Find-BadMusicFolderStructure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]$StartingPath,

        [switch]$Good,

        [string]$LogTo
    )

    begin {
        $audioExtensions = @(".mp3", ".wav", ".flac", ".aac", ".ogg", ".wma")
        $patternMain = '(?i)\\([^\\]+)\\\d{4} - [^\\]+\\\d{2} - .+\.[a-z0-9]+$'
        $patternDisc = '(?i)\\([^\\]+)\\\d{4} - [^\\]+\\Disc \d+\\\d{2} - .+\.[a-z0-9]+$'
        $results = @()
    }

    process {
        $folders = Get-ChildItem -LiteralPath $StartingPath -Recurse -Directory | Sort-Object -Unique | ForEach-Object { $_.FullName }

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
                $results += [PSCustomObject]@{ Status = 'Good'; StartingPath = $artistFolderPath }
            if( $LogTo -and $Good) {
                    Add-Content -Path $LogTo -Value ("GoodFolderStructure " + ($artistFolderPath))
                }
            }
            else {
                $badFolder = $firstAudioFile.DirectoryName
                $results += [PSCustomObject]@{ Status = 'Bad'; StartingPath = $badFolder }
                if ($LogTo) {
                    Add-Content -Path $LogTo -Value ("BadFolderStructure " + ($badFolder))
                }
            }
        }
    }

    end {
        $uniqueResults = $results | Group-Object -Property StartingPath | ForEach-Object {
            [PSCustomObject]@{ Status = $_.Group[0].Status; StartingPath = $_.Name }
        }

        if ($Good) {
            $uniqueResults | Where-Object { $_.Status -eq 'Good' } | Select-Object StartingPath
        }
        else {
            $uniqueResults | Where-Object { $_.Status -eq 'Bad' } | Select-Object StartingPath
        }
        if ($LogTo) {
            Write-Host "✅ Measurement complete. Logs Saved at $LogTo"
        }
    }
}

function Save-TagsFromGoodMusicFolders {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('StartingPath')]
        [string]$FolderPath,

        [string]$LogTo
    )

    begin {
        Add-Type -Path "C:\Users\resto\Documents\PowerShell\Modules\MusicPicturesDownloader\lib\taglib-sharp.dll"
        [TagLib.Id3v2.Tag]::DefaultVersion = 4
        [TagLib.Id3v2.Tag]::ForceDefaultVersion = $true

        $musicExtensions = @('.mp3', '.flac', '.m4a', '.ogg', '.wav', '.aac')

        if ($LogTo) {
            $logDir = Split-Path -Path $LogTo -Parent
            if (-not (Test-Path -Path $logDir)) {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }
            $badFolders = @{}
        }
    }

    process {
        # Safety: verify compliance before tagging
        $isGoodMusic = (Find-BadMusicFolderStructure -Path $FolderPath -Compliant | Where-Object { $_.StartingPath -eq $FolderPath })
        if (-not $isGoodMusic) {
            Write-Warning "Skipping non-compliant folder: $FolderPath"
            if ($LogTo) { $badFolders[$FolderPath] = @("NonCompliant") }
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
                $fileName = [System.IO.StartingPath]::GetFileNameWithoutExtension($file.Name)

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
                        if ($LogTo) { $badFolders[$FolderPath] += "FailedTagging" }
                    }
                }
                else {
                    Write-Warning "❌ Bad filename format: $fileName"
                    if ($LogTo) { $badFolders[$FolderPath] += "WrongTitleFormat" }
                }
            }
            else {
                Write-Warning "❌ No album folder found: $($file.FullName)"
                if ($LogTo) { $badFolders[$FolderPath] += "ShallowPath" }
            }
        }
    }

    end {
        if ($LogTo -and $badFolders.Count -gt 0) {
            foreach ($folder in $badFolders.Keys) {
                $reasons = ($badFolders[$folder] | Sort-Object -Unique) -join ", "
                [System.IO.File]::AppendAllText($LogTo, "$reasons`: $folder`r`n", [System.Text.Encoding]::UTF8)
            }
            Write-Host "📝 Bad folders logged to: $LogTo"
        }
    }
}


#Get-ChildItem -LiteralPath E:\ -Directory | 
#Select-Object -First 10 | 
#Find-BadMusicFolderStructure -Compliant -LogTo "C:\Logs\MusicStructureLog.txt" | #BadFolderStructur E:\_testb\220 Greatest Old Songs [MP3-128 & 320kbps]
#Save-TagsFromGoodMusicFolders -LogFile "C:\Logs\BadFolders.log" -WhatIf
#Find-BadMusicFolderStructure -Path (Get-ChildItem -Path E:\ -Directory |Select-Object -first 10) -Compliant -LogTo "C:\Logs\MusicStructureLog.txt" | Save-TagsFromGoodMusicFolders -LogFile "C:\Logs\BadFolders.log" -WhatIf
#Find-BadMusicFolderStructure -Path E: -Compliant |
# Save-TagsFromGoodMusicFolders -LogFile "C:\Logs\BadFolders.log" -WhatIf
