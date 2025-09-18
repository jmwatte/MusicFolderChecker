function Get-DiscogsRelease {
    <#
    .SYNOPSIS
    Retrieves a Discogs release object by ID.

    .DESCRIPTION
    Calls /releases/{id} and returns the parsed JSON object or $null on failure.

    .PARAMETER Id
    Discogs release ID.

    .OUTPUTS
    PSCustomObject (Discogs release JSON)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Id
    )

    Invoke-DiscogsRequest -Method GET -RelativePath ("/releases/{0}" -f $Id)
}
