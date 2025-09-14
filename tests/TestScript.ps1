# Test script for Update-MusicFolderMetadata with mocked TagLib

Import-Module "C:\Users\resto\Documents\PowerShell\Modules\MusicFolderChecker\MusicFolderChecker.psm1" -Force

# Mock Invoke-TagLibCreate
$mockTag = {
    $tag = New-Object PSObject
    $tag | Add-Member -MemberType NoteProperty -Name AlbumArtists -Value @('Test Artist')
    $tag | Add-Member -MemberType NoteProperty -Name Performers -Value @('Test Artist')
    $tag | Add-Member -MemberType NoteProperty -Name Album -Value 'Test Album'
    $tag | Add-Member -MemberType NoteProperty -Name Year -Value 2023
    $tag | Add-Member -MemberType NoteProperty -Name Disc -Value 1
    $tag | Add-Member -MemberType NoteProperty -Name Track -Value 1
    $tag | Add-Member -MemberType NoteProperty -Name Title -Value 'Test Track'

    $mockObj = New-Object PSObject
    $mockObj | Add-Member -MemberType NoteProperty -Name Tag -Value $tag
    $mockObj | Add-Member -MemberType ScriptMethod -Name Save -Value { }
    return $mockObj
}

# For disc 02, set Disc to 2
$mockTag2 = {
    $tag = New-Object PSObject
    $tag | Add-Member -MemberType NoteProperty -Name AlbumArtists -Value @('Test Artist')
    $tag | Add-Member -MemberType NoteProperty -Name Performers -Value @('Test Artist')
    $tag | Add-Member -MemberType NoteProperty -Name Album -Value 'Test Album'
    $tag | Add-Member -MemberType NoteProperty -Name Year -Value 2023
    $tag | Add-Member -MemberType NoteProperty -Name Disc -Value 2
    $tag | Add-Member -MemberType NoteProperty -Name Track -Value 1
    $tag | Add-Member -MemberType NoteProperty -Name Title -Value 'Test Track 2'

    $mockObj = New-Object PSObject
    $mockObj | Add-Member -MemberType NoteProperty -Name Tag -Value $tag
    $mockObj | Add-Member -MemberType ScriptMethod -Name Save -Value { }
    return $mockObj
}

# Mock based on file path
function MockInvokeTagLibCreate {
    param($Path)
    if ($Path -like '*disc 02*') {
        & $mockTag2
    } else {
        & $mockTag
    }
}

# Use Mock cmdlet
Mock Invoke-TagLibCreate { MockInvokeTagLibCreate -Path $args[0] }

Write-Host "Testing Update-MusicFolderMetadata with mocked TagLib..."

# Test 1: Set disc tags first
Write-Host "`n--- Test 1: Set Disc Tags ---"
Set-DiscFromFolderName -FolderPath "C:\Users\resto\Documents\PowerShell\Modules\MusicFolderChecker\tests\TestAlbum" -Verbose

# Test 2: Update metadata with move
Write-Host "`n--- Test 2: Update Metadata and Move ---"
Update-MusicFolderMetadata -FolderPath "C:\Users\resto\Documents\PowerShell\Modules\MusicFolderChecker\tests\TestAlbum" -AlbumArtist 'Test Artist' -Album 'Test Album' -Year 2023 -Move -DestinationFolder "C:\Users\resto\Documents\PowerShell\Modules\MusicFolderChecker\tests\TestDestination" -WhatIf

Write-Host "`nTest completed."