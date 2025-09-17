# Requires -Version 5.1
# Pester tests for Year fallback parsing from DATE/TDRC/etc.

# We will mock Invoke-TagLibCreate to simulate TagLib objects with various tag states

Describe 'Get-FolderTagConsensus - Year fallback parsing' {
    BeforeAll {
        # Import the module under test
        $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\MusicFolderChecker.psm1'
        Import-Module $modulePath -Force

        function New-FakeId3Frame {
            param([string]$text)
            $o = New-Object psobject -Property @{ Text = @($text) }
            # mimic property access used in code
            return $o
        }

        function New-FakeTagFile {
            param(
                [int]$Year = 0,
                [string]$TDRC = $null,
                [string]$TDOR = $null,
                [string]$TYER = $null,
                [string]$XiphDATE = $null,
                [string]$XiphYEAR = $null,
                [string]$Album = 'Album',
                [string]$Artist = 'Artist'
            )
            $fake = New-Object psobject -Property @{
                Tag = New-Object psobject -Property @{
                    Year = $Year
                    Album = $Album
                    AlbumArtists = @($Artist)
                    Performers = @($Artist)
                }
            }
            Add-Member -InputObject $fake -MemberType ScriptMethod -Name Dispose -Value { return }
            # Shim GetTag for Id3v2 and Xiph
            Add-Member -InputObject $fake -MemberType ScriptMethod -Name GetTag -Value {
                param($type, $create)
                if ($type -eq ([TagLib.TagTypes]::Id3v2)) {
                    # Return a fake Id3v2 tag with TextInformationFrame Get behavior
                    $t = New-Object psobject
                    Add-Member -InputObject $t -MemberType ScriptMethod -Name GetType -Value { return [TagLib.Id3v2.Tag] }
                    # Stuff pass-through fields onto the object for retrieval in __getFrame
                    Add-Member -InputObject $t -MemberType NoteProperty -Name TDRC -Value $TDRC
                    Add-Member -InputObject $t -MemberType NoteProperty -Name TDOR -Value $TDOR
                    Add-Member -InputObject $t -MemberType NoteProperty -Name TYER -Value $TYER
                    return $t
                }
                elseif ($type -eq ([TagLib.TagTypes]::Xiph)) {
                    $x = New-Object psobject
                    Add-Member -InputObject $x -MemberType ScriptMethod -Name GetField -Value { param($name)
                        switch -Regex ($name) {
                            '^DATE$' { if ($this.PSObject.Properties['XiphDATE'] -and $this.XiphDATE) { return @($this.XiphDATE) } }
                            '^YEAR$' { if ($this.PSObject.Properties['XiphYEAR'] -and $this.XiphYEAR) { return @($this.XiphYEAR) } }
                        }
                        return $null
                    }
                    Add-Member -InputObject $x -MemberType NoteProperty -Name XiphDATE -Value $XiphDATE
                    Add-Member -InputObject $x -MemberType NoteProperty -Name XiphYEAR -Value $XiphYEAR
                    return $x
                }
                return $null
            }
            return $fake
        }

        Mock -CommandName Invoke-TagLibCreate -ModuleName MusicFolderChecker -MockWith {
            # Pull scenario from global state (set per test)
            return $script:__scenarioQueue.Dequeue()
        }
    }

    It 'uses Tag.Year when present and numeric' {
        $script:__scenarioQueue = [System.Collections.Generic.Queue[object]]::new()
        $script:__scenarioQueue.Enqueue((New-FakeTagFile -Year 1997))
        $script:__scenarioQueue.Enqueue((New-FakeTagFile -Year 1997))
        $script:__scenarioQueue.Enqueue((New-FakeTagFile -Year 1997))

        $tmp = New-Item -ItemType Directory -Path (Join-Path $env:TEMP ([guid]::NewGuid()))
        try {
            1..3 | ForEach-Object { New-Item -ItemType File -Path (Join-Path $tmp.FullName ("track$_.mp3")) | Out-Null }
            $res = Get-FolderTagConsensus -Path $tmp.FullName -MinFiles 1
            $res.YearTopValue | Should -Be 1997
            $res.YearConsensus | Should -BeTrue
            $res.YearCoverageRatio | Should -Be 1.0
        } finally { Remove-Item -LiteralPath $tmp.FullName -Recurse -Force }
    }

    It 'derives Year from TDRC when Tag.Year is 0' {
        $script:__scenarioQueue = [System.Collections.Generic.Queue[object]]::new()
    $script:__scenarioQueue.Enqueue((New-FakeTagFile -TDRC '1995-06-01'))
    $script:__scenarioQueue.Enqueue((New-FakeTagFile -TDRC '1995'))
    $script:__scenarioQueue.Enqueue((New-FakeTagFile -TDRC '1995-01-01'))

        $tmp = New-Item -ItemType Directory -Path (Join-Path $env:TEMP ([guid]::NewGuid()))
        try {
            1..3 | ForEach-Object { New-Item -ItemType File -Path (Join-Path $tmp.FullName ("track$_.flac")) | Out-Null }
            $res = Get-FolderTagConsensus -Path $tmp.FullName -MinFiles 1
            $res.YearTopValue | Should -Be 1995
            $res.YearConsensus | Should -BeTrue
            $res.YearCoverageRatio | Should -Be 0.0
            ($res.Details -join ' ') | Should -Match 'Derived Year from'
        } finally { Remove-Item -LiteralPath $tmp.FullName -Recurse -Force }
    }

    It 'falls back to Xiph DATE when ID3 frames are absent' {
        $script:__scenarioQueue = [System.Collections.Generic.Queue[object]]::new()
        $script:__scenarioQueue.Enqueue((New-FakeTagFile -XiphDATE '2000-10-10'))
        $script:__scenarioQueue.Enqueue((New-FakeTagFile -XiphDATE '2000'))
        $script:__scenarioQueue.Enqueue((New-FakeTagFile -XiphDATE '2000-01'))

        $tmp = New-Item -ItemType Directory -Path (Join-Path $env:TEMP ([guid]::NewGuid()))
        try {
            1..3 | ForEach-Object { New-Item -ItemType File -Path (Join-Path $tmp.FullName ("track$_.ogg")) | Out-Null }
            $res = Get-FolderTagConsensus -Path $tmp.FullName -MinFiles 1
            $res.YearTopValue | Should -Be 2000
            $res.YearConsensus | Should -BeTrue
        } finally { Remove-Item -LiteralPath $tmp.FullName -Recurse -Force }
    }
}
