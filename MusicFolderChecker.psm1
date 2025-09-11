## Enforce pwsh (PowerShell 7+) runtime and load TagLibSharp
$requiredMajor = 7
if ($PSVersionTable.PSVersion.Major -lt $requiredMajor) {
    throw "MusicFolderChecker requires PowerShell $requiredMajor or later. Current version: $($PSVersionTable.PSVersion). Please use 'pwsh' (PowerShell 7+)."
}

$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
# Prefer the canonical filename you provided
$preferredDll = Join-Path $moduleRoot 'lib\taglib-sharp.dll'
$taglibPath = $null
if (Test-Path -LiteralPath $preferredDll) {
    $taglibPath = $preferredDll
} else {
    # Fallback: probe common names
    $possibleNames = @('TagLibSharp.dll','taglib-sharp.dll','TagLib.dll')
    foreach ($n in $possibleNames) {
        $p = Join-Path -Path $moduleRoot -ChildPath ("lib\{0}" -f $n)
        if (Test-Path -LiteralPath $p) { $taglibPath = $p; break }
    }
}

if (-not $taglibPath) {
    Throw "TagLib dependency not found. Expected a TagLibSharp DLL in: $moduleRoot\lib\ (e.g. taglib-sharp.dll). Install it or run 'scripts\Install-TagLibSharp.ps1'."
}

try {
    $already = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -match 'TagLib' }
    if (-not $already) {
        Add-Type -Path $taglibPath -ErrorAction Stop
    }
}
catch {
    Throw "Failed to load TagLib from '$taglibPath': $_. Ensure the DLL is a .NET Standard / .NET Core compatible build for pwsh 7+."
}

Get-ChildItem -Path "$PSScriptRoot/src/Private/*.ps1" | ForEach-Object {
    . $_.FullName
}
# Import Helpers
if (Test-Path -LiteralPath "$PSScriptRoot/Helpers") {
    Get-ChildItem -Path "$PSScriptRoot/Helpers/*.ps1" -ErrorAction SilentlyContinue | ForEach-Object {
        . $_.FullName
    }
}

# Import public functions
Get-ChildItem -Path "$PSScriptRoot/src/Public/*.ps1" | ForEach-Object {
    . $_.FullName
    Export-ModuleMember -Function $_.BaseName
}