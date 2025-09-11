function Invoke-TagLibCreate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    return [TagLib.File]::Create($Path)
}
