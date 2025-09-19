function Invoke-DiscogsRequest {
    <#
    .SYNOPSIS
    Performs a Discogs API request with authentication, headers, and basic retry/backoff.

    .DESCRIPTION
    Builds a request to https://api.discogs.com, adding a User-Agent and Authorization header
    when the environment variable DISCOGS_TOKEN is present. Retries on HTTP 429 (rate limit)
    with exponential backoff.

    .PARAMETER Method
    HTTP method (GET/POST/PUT/DELETE).

    .PARAMETER RelativePath
    API path under https://api.discogs.com, for example '/database/search'.

    .PARAMETER Query
    Hashtable of querystring parameters to append to the URI.

    .OUTPUTS
    Parsed JSON from Discogs (PSCustomObject) or $null on non-fatal failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GET','POST','PUT','DELETE')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [hashtable]$Query
    )

    try {
    $base = 'https://api.discogs.com'
    $baseUri = [System.Uri]$base
    # Build a proper absolute URI from base + relative path
    $rel = $RelativePath
    if (-not $rel) { throw 'RelativePath is required' }
    # Ensure a single leading slash for root-relative API paths
    if (-not $rel.StartsWith('/')) { $rel = '/' + $rel }
    $uriObj = [System.Uri]::new($baseUri, $rel)
        # Auth: prefer personal access token; otherwise fall back to key/secret in query if available
        $headers = @{ 'User-Agent' = 'MusicFolderChecker/1.0 (+https://github.com/jmwatte/MusicFolderChecker)'; }
        $token = $env:DISCOGS_TOKEN
        if ($token) { $headers['Authorization'] = "Discogs token=$token" }
        else {
            $key = $env:DISCOGS_KEY; $sec = $env:DISCOGS_SECRET
            if ($key -and $sec) {
                if (-not $Query) { $Query = @{} }
                $Query['key'] = $key
                $Query['secret'] = $sec
            }
        }

        if ($Query -and $Query.Count -gt 0) {
            $pairs = @()
            foreach ($k in $Query.Keys) {
                $ek = [System.Uri]::EscapeDataString([string]$k)
                $ev = [System.Uri]::EscapeDataString([string]$Query[$k])
                $pairs += ("{0}={1}" -f $ek, $ev)
            }
            $qs = [string]::Join('&', $pairs)
            $ub = [System.UriBuilder]$uriObj
            $ub.Query = $qs
            $uriObj = $ub.Uri
        }

        $maxRetries = 4
        for ($attempt = 0; $attempt -le $maxRetries; $attempt++) {
            try {
                Write-Verbose ("Discogs {0} {1}" -f $Method, $uriObj.AbsoluteUri)
                return Invoke-RestMethod -Method $Method -Uri $uriObj.AbsoluteUri -Headers $headers -TimeoutSec 60 -ErrorAction Stop
            } catch {
                $status = $null
                try { $status = $_.Exception.Response.StatusCode.Value__ } catch { }
                if ($status -eq 429 -and $attempt -lt $maxRetries) {
                    $delay = [math]::Pow(2, $attempt) * 0.5
                    Write-Verbose ("Discogs rate limit hit. Retrying in {0:n1}s..." -f $delay)
                    Start-Sleep -Seconds $delay
                    continue
                }
                if ($status -eq 401) {
                    throw "Authentication required for Discogs API. Please set your personal access token: `$env:DISCOGS_TOKEN = 'your_token_here'"
                }
                Write-Verbose ("Discogs request failed: {0}" -f $_)
                return $null
            }
        }
    } catch {
        Write-Verbose ("Discogs request setup failed: {0}" -f $_)
        if ($_.Exception.Message -like "*Authentication required*") {
            throw
        }
        return $null
    }
}
