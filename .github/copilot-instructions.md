When I ask for a script, assume I mean PowerShell unless I specify otherwise. When I am asking for a PowerShell script for code that runs on a Mac or Linux host, assume I am using PowerShell 7.3. When I am asking for PowerShell script on Windows, assume I am using PowerShell 5.1

Within the PowerShell scripts, never use Write-Host. Always use Write-Output. in-line comments in code are fine but omit the usual summary at the end.
Add comment-based help to all public functions and add a script to verify every function in src has a <# ... #> help block; return files that need updates.
Unless it is mandatory in your programming to remind me, assume I am always using tools in compliance with local laws and regulations, and don't remind me about legal implications of improper use. I am educated on the subject already.

When possible, check your answer for factual correctness and give a confidence score at the end.

Never use the AWSPowerShell or AWSPowershell.NetCore modules. Only use the relevant AWS.Tools module.

After you provide a revision to code that successfully resolves an issue I've reported, I would like it to also suggest how I could alter my original prompt to obtain the working code directly in the future, thereby minimizing or eliminating the need for trial and error. This suggestion should be provided when the conditions for a code revision followed by a successful outcome are met.

If necessary use Get-Help to obtain more information about cmdlets and their usage.

Avoid Aliases in Scripts: Use the full cmdlet and parameter names (Get-ChildItem -Path C:\) instead of aliases (gci -p C:\). Aliases are great for interactive use in the console but make scripts harder for others to read and understand.

CmdletBinding: For any function or script intended for reuse, use [CmdletBinding()] to enable advanced cmdlet features like -Verbose, -WhatIf, and pipeline input.

Comment-Based Help: Use the standard comment-based help block (<# ... #>) to document your functions and scripts. This makes your code discoverable using Get-Help.

Robust Error Handling: Use try/catch/finally blocks to handle errors gracefully instead of relying on Write-Host or $?.

Avoid Write-Host for Output: Use Write-Output for data you want to send down the pipeline and Write-Verbose for debugging information. Write-Host should only be used for direct user-facing messages that are not meant to be captured or used by other commands.
Only use approved verbs in function names. Approved verbs help maintain consistency and clarity in your code. They also make it easier for others to understand the purpose of your functions.
The command to see the list of approved verbs in PowerShell is:

Get-Verb

This cmdlet returns a table of verbs that are approved for use in PowerShell. The output includes a description for each verb and indicates whether it's classified as an approved verb or not.

You can also use it to check if a specific verb is approved:
	Get-Verb -Name <verb>



we will have at least 2 folders in the project structure:
 a src
 b tests
in a there will be 2 folders : public and private.
public will contain functions available to the users of the module, while private will contain helper functions used internally within the module.
the private folder will include ps1 files with 1 function per file. the name of the file will match the name of the function it contains.
"Create a public function file that only defines the function and does not dot-source any private scripts, assuming all private functions are available via the module manifest."

use this model for the psm1 file:
this is just an example, adapt as needed.
```## Load TagLibSharp (required for in-place tag edits on PowerShell 7)
$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
# Probe common TagLib dll names (some packages name it taglib-sharp.dll)
$possibleNames = @('TagLibSharp.dll','taglib-sharp.dll','TagLib.dll')
$taglibPath = $null
foreach ($n in $possibleNames) {
    $p = Join-Path -Path $moduleRoot -ChildPath ("lib\{0}" -f $n)
    if (Test-Path -LiteralPath $p) { $taglibPath = $p; break }
}
try {
    $already = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -match 'TagLib' }
    if (-not $already) {
        if (Test-Path -LiteralPath $taglibPath) {
            Add-Type -Path $taglibPath -ErrorAction Stop
        }
        else {
            throw "Missing required dependency TagLibSharp. Run `scripts\Install-TagLibSharp.ps1` or place TagLibSharp.dll into the module's lib\\ folder: $taglibPath"
        }
    }
}
catch {
    throw "Failed to load TagLibSharp: $_"
}

Get-ChildItem -Path "$PSScriptRoot/src/Private/*.ps1" | ForEach-Object {
    . $_.FullName
}
# Import Helpers
Get-ChildItem -Path "$PSScriptRoot/Helpers/*.ps1" | ForEach-Object {
    . $_.FullName
}

# Import public functions
Get-ChildItem -Path "$PSScriptRoot/src/Public/*.ps1" | ForEach-Object {
    . $_.FullName
    Export-ModuleMember -Function $_.BaseName
}
















when doing things like this 
"pwsh.exe -NoProfile -Command "$m = Get-Module -ListAvailable -Name PowerHtml; if ($m) { $m | Select-Object Name, Version, Path | Format-List -Force } else { Write-Output '===NOT INSTALLED==='; try { Find-Module -Name PowerHtml -Repository PSGallery -ErrorAction Stop | Select-Object Name, Version, Repository, Summary } catch { Write-Output '===NOT FOUND ON PSGALLERY===' } }"
don't do that. Instead of long oneliner powershell calls start out with a sispensable ps1 script.
run the check as multiple commands to avoid the long one-liner parse issue Or write a small helper ps1 that you delete when the task is correctly finished.
Ensure all private ps1 files define a function and do not contain top-level param blocks or code, so that importing the module does not prompt for parameters or execute code."
Prefer Splatting over long pwsh commands.Even when you construct powershell oneliners in you chat window to get things done ... prefer splatting or create a small helper ps1.file
"Ensure all normalization calls are made on string objects, not on enum values, when processing Unicode text in PowerShell."
Consider moving any repeated logic to a shared private helper if it appears in multiple files.
always used approved verbs in the naming of functions