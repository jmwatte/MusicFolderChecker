function Get-DerivedYearFromTag {
    <#
    .SYNOPSIS
    Derives a 4-digit Year from common date-like tags when Tag.Year is missing.

    .DESCRIPTION
    Attempts to parse a year from ID3v2 frames (TDRC, TDOR, TYER) and Xiph/Vorbis comments (DATE, YEAR).
    Returns a hashtable with keys Year (int) and Source (string) indicating which tag field provided the value.

    .PARAMETER TagFile
    A TagLib.File instance (or a mock exposing GetTag and Tag property) to inspect.

    .OUTPUTS
    Hashtable with keys: Year (int or $null), Source (string or $null)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$TagFile
    )

    function ConvertTo-YearFromString {
        param([string]$Text)
        if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
        try {
            $m = [regex]::Match($Text, '(?<!\d)(?:19|20)\d{2}')
            if ($m.Success) { return [int]$m.Value } else { return $null }
        } catch { return $null }
    }

    $source = $null; $val = $null
    try {
        # ID3v2 frames
        try {
            $id3v2 = $TagFile.GetTag([TagLib.TagTypes]::Id3v2, $false)
            if ($id3v2) {
                if ($id3v2 -is [TagLib.Id3v2.Tag]) {
                    try {
                        $tdrc = [TagLib.Id3v2.TextInformationFrame]::Get([TagLib.Id3v2.Tag]$id3v2, 'TDRC', $false)
                        if ($tdrc -and $tdrc.Text -and $tdrc.Text.Length -gt 0) {
                            $val = ConvertTo-YearFromString -Text $tdrc.Text[0]
                            if ($val) { $source = 'Id3v2:TDRC' }
                        }
                        if (-not $val) {
                            $tdor = [TagLib.Id3v2.TextInformationFrame]::Get([TagLib.Id3v2.Tag]$id3v2, 'TDOR', $false)
                            if ($tdor -and $tdor.Text -and $tdor.Text.Length -gt 0) {
                                $val = ConvertTo-YearFromString -Text $tdor.Text[0]
                                if ($val) { $source = 'Id3v2:TDOR' }
                            }
                        }
                        if (-not $val) {
                            $tyer = [TagLib.Id3v2.TextInformationFrame]::Get([TagLib.Id3v2.Tag]$id3v2, 'TYER', $false)
                            if ($tyer -and $tyer.Text -and $tyer.Text.Length -gt 0) {
                                $val = ConvertTo-YearFromString -Text $tyer.Text[0]
                                if ($val) { $source = 'Id3v2:TYER' }
                            }
                        }
                    } catch {
                        # In tests, read direct properties when static Get is not available
                        if (-not $val -and ($id3v2.PSObject.Properties['TDRC'])) {
                            $val = ConvertTo-YearFromString -Text $id3v2.PSObject.Properties['TDRC'].Value
                            if ($val) { $source = 'Id3v2:TDRC' }
                        }
                        if (-not $val -and ($id3v2.PSObject.Properties['TDOR'])) {
                            $val = ConvertTo-YearFromString -Text $id3v2.PSObject.Properties['TDOR'].Value
                            if ($val) { $source = 'Id3v2:TDOR' }
                        }
                        if (-not $val -and ($id3v2.PSObject.Properties['TYER'])) {
                            $val = ConvertTo-YearFromString -Text $id3v2.PSObject.Properties['TYER'].Value
                            if ($val) { $source = 'Id3v2:TYER' }
                        }
                    }
                } else {
                    # Test shim path: accept direct properties TDRC/TDOR/TYER on the object
                    if (-not $val -and ($id3v2.PSObject.Properties['TDRC'])) {
                        $val = ConvertTo-YearFromString -Text $id3v2.PSObject.Properties['TDRC'].Value
                        if ($val) { $source = 'Id3v2:TDRC' }
                    }
                    if (-not $val -and ($id3v2.PSObject.Properties['TDOR'])) {
                        $val = ConvertTo-YearFromString -Text $id3v2.PSObject.Properties['TDOR'].Value
                        if ($val) { $source = 'Id3v2:TDOR' }
                    }
                    if (-not $val -and ($id3v2.PSObject.Properties['TYER'])) {
                        $val = ConvertTo-YearFromString -Text $id3v2.PSObject.Properties['TYER'].Value
                        if ($val) { $source = 'Id3v2:TYER' }
                    }
                }
            }
        } catch { }

        # Xiph/Vorbis/FLAC comments
        if (-not $val) {
            try {
                $xiph = $TagFile.GetTag([TagLib.TagTypes]::Xiph, $false)
                if ($xiph) {
                    $hasGetField = $xiph.PSObject.Methods.Name -contains 'GetField'
                    if ($hasGetField) {
                        $vals = $xiph.GetField('DATE')
                    if ($vals -and $vals.Length -gt 0) {
                        $val = ConvertTo-YearFromString -Text $vals[0]
                        if ($val) { $source = 'Xiph:DATE' }
                    }
                    if (-not $val) {
                        $vals = $xiph.GetField('YEAR')
                        if ($vals -and $vals.Length -gt 0) {
                                $val = ConvertTo-YearFromString -Text $vals[0]
                            if ($val) { $source = 'Xiph:YEAR' }
                        }
                    }
                    }
                }
            } catch { }
        }
    } catch { $val = $null; $source = $null }

    return @{ Year = $val; Source = $source }
}
