# Test script for Update-MusicFolderMetadata on artist folder with multiple albums

Import-Module "C:\Users\resto\Documents\PowerShell\Modules\MusicFolderChecker\MusicFolderChecker.psm1" -Force

# Mock Invoke-TagLibCreate to simulate different albums
$mockTag1 = {
    $tag = New-Object PSObject
    $tag | Add-Member -MemberType NoteProperty -Name AlbumArtists -Value @('Test Artist')
    $tag | Add-Member -MemberType NoteProperty -Name Performers -Value @('Test Artist')
    $tag | Add-Member -MemberType NoteProperty -Name Album -Value 'Album One'
    $tag | Add-Member -MemberType NoteProperty -Name Year -Value 2002
    $tag | Add-Member -MemberType NoteProperty -Name Disc -Value 1
    $tag | Add-Member -MemberType NoteProperty -Name Track -Value 1
    $tag | Add-Member -MemberType NoteProperty -Name Title -Value 'Track1'

    $mockObj = New-Object PSObject
    $mockObj | Add-Member -MemberType NoteProperty -Name Tag -Value $tag
    $mockObj | Add-Member -MemberType ScriptMethod -Name Save -Value { }
    return $mockObj
}

$mockTag2 = {
    $tag = New-Object PSObject
    $tag | Add-Member -MemberType NoteProperty -Name AlbumArtists -Value @('Test Artist')
    $tag | Add-Member -MemberType NoteProperty -Name Performers -Value @('Test Artist')
    $tag | Add-Member -MemberType NoteProperty -Name Album -Value 'Album Two'
    $tag | Add-Member -MemberType NoteProperty -Name Year -Value 2010
    $tag | Add-Member -MemberType NoteProperty -Name Disc -Value 1
    $tag | Add-Member -MemberType NoteProperty -Name Track -Value 1
    $tag | Add-Member -MemberType NoteProperty -Name Title -Value 'Track1'

    $mockObj = New-Object PSObject
    $mockObj | Add-Member -MemberType NoteProperty -Name Tag -Value $tag
    $mockObj | Add-Member -MemberType ScriptMethod -Name Save -Value { }
    return $mockObj
}

# Mock based on file path
function MockInvokeTagLibCreate {
    param($Path)
    if ($Path -like '*2002*') {
        & $mockTag1
    } else {
        & $mockTag2
    }
}

# Use Mock cmdlet
Mock Invoke-TagLibCreate { MockInvokeTagLibCreate -Path $args[0] }

Write-Host "Testing Update-MusicFolderMetadata on artist folder with multiple albums..."

# Test: Run on the artist folder (which has multiple albums)
Update-MusicFolderMetadata -FolderPath "C:\Users\resto\Documents\PowerShell\Modules\MusicFolderChecker\tests\TestArtist" -Move -DestinationFolder "C:\Users\resto\Documents\PowerShell\Modules\MusicFolderChecker\tests\TestDestination" -WhatIf

Write-Host "`nTest completed. This demonstrates the issue: all files get moved under the first album's metadata."