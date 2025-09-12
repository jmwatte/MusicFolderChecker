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
    ## Copilot instructions — MusicFolderChecker (PowerShell)

    Short, focused guidance to help an AI contributor be immediately productive in this repository.

    ### Big picture
    - This is a PowerShell module that inspects and optionally updates album-level metadata and can move music files into a structured destination. Key directories:
      - `src/Public/` — public function files (one function per file). These files only define the function and are exported via the module loader.
      - `src/Private/` — private helper functions (one PS1 per function). Private files must not execute top-level code or declare param blocks.
      - `lib/` — binary dependencies (TagLib-Sharp DLL expected here).
      - `tests/` — Pester tests.

    ### Key files & patterns
    - `MusicFolderChecker.psm1` — module loader: loads TagLibSharp from `lib\TagLibSharp.dll`, dot-sources `src/Private/*.ps1` and `src/Public/*.ps1`, then calls `Export-ModuleMember` for public functions.
    - `MusicFolderChecker.psd1` — module manifest; exported function names and PowerShellVersion live here.
    - `src/Public/Update-MusicFolderMetadata.ps1` — main example: interactive prompts (`Read-Host`), tag writes using TagLib, `ShouldProcess`/`-WhatIf`, JSONL structured logging via `Write-StructuredLog`, and move logic.

    ### Project conventions (follow exactly)
    - PowerShell is the default language. On macOS/Linux assume `pwsh` (PowerShell 7.x); on Windows support PowerShell 5.1 compatibility where needed.
    - Do NOT use `Write-Host`. Use `Write-Output` for pipeline results and `Write-Verbose` for debug. User-facing notices may be `Write-Output` as well.
    - Always use full cmdlet names (no aliases). Example: `Get-ChildItem -Path` not `gci`.
    - Public functions: use `[CmdletBinding()]`, provide comment-based help (`<# ... #>`), and accept pipeline input where appropriate.
    - Private functions: one function per file, filename == function name, no top-level execution.
    - Use approved verbs from `Get-Verb` for function names.

    ### Dependency & integration notes
    - TagLib-Sharp is required for tag edits. The loader probes common DLL names in `lib\TagLibSharp.dll` (or `TagLib.dll`). If missing, scripts reference `scripts/Install-TagLibSharp.ps1` as the intended installer.
    - Structured logs: the module uses JSONL via `Write-StructuredLog` and provides `Get-MfcLogSummary` to summarize logs.

    ### Developer workflows & commands
    - Import the module for local development:
    ```powershell
    Import-Module .\MusicFolderChecker.psm1 -Force
    ```
    - Test a single folder interactively (WhatIf for safe preview):
    ```powershell
    Update-MusicFolderMetadata -FolderPath 'D:\Album' -DestinationFolder D:\_test\ -Move -WhatIf
    ```
    - Create/inspect logs (JSONL): pass `-LogPath .\mfc.log` to functions and summarize with `Get-MfcLogSummary -Path .\mfc.log`.
    - Run Pester tests:
    ```powershell
    # from repo root
    Invoke-Pester -Script .\tests -OutputFormat NUnitXml -OutputFile .\test-results.xml
    ```
    Notes: tests mock `Read-Host` and TagLib interactions where needed; follow existing tests for the mocking pattern.

    ### Testing & mocking guidance
    - When writing tests for interactive functions, mock `Read-Host` and TagLib helper (`Invoke-TagLibCreate`) to avoid disk I/O.
    - Prefer unit tests for private helpers in `src/Private` and integration tests for public commands in `src/Public`.

    ### Safety & UX patterns to follow
    - All destructive filesystem operations must use `ShouldProcess` so `-WhatIf` previews work.
    - Interactive prompts should validate input (e.g., Year) and re-prompt; if cancelled, log `InteractiveCanceled` to the structured log.
    - Move behavior: `-Move` is authoritative — moving occurs after prompts finish. If the user left prompts blank and did not ask `-Move`, the code logs `SkippedNoChanges`.

    ### When you modify code
    - Update `MusicFolderChecker.psd1` to export any new public functions.
    - Keep the loader pattern: do not introduce public files that execute code at import.
    - Add or update Pester tests and run them locally before opening PRs.

    ### PowerShell error-handling style note
    - Avoid using single-line inline `try { ... } catch { ... }` expressions inside larger parenthetical or ternary-like expressions. PowerShell's parser can misinterpret these in complex expressions and attempt to call `Try` as a command, causing runtime errors like "'Try' is not recognized". Prefer multi-line `try { ... } catch { ... }` blocks for robust, unambiguous error handling.

    If anything here is unclear or you want the guide expanded with concrete examples (test mocks, log schema, or the psm1 loader), tell me which area to expand and I will iterate.