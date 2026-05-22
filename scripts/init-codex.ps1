[CmdletBinding()]
param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }),
    [int]$DefaultProxyPort = 7890,
    [string]$DefaultProxyHost = "127.0.0.1"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DesiredConfig = [ordered]@{
    sandbox_mode                  = '"danger-full-access"'
    model_context_window          = '512000'
    model_auto_compact_token_limit = '400000'
}

function New-Timestamp {
    return Get-Date -Format "yyyyMMddHHmmss"
}

function New-BackupFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $backupPath = "{0}.bak.{1}" -f $Path, (New-Timestamp)
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    return $backupPath
}

function ConvertTo-ProxyEndpoint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RawValue
    )

    $candidate = $RawValue.Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        return $null
    }

    if ($candidate -notmatch '^[a-zA-Z][a-zA-Z0-9+\-.]*://') {
        $candidate = "http://$candidate"
    }

    try {
        $uri = [Uri]$candidate
    } catch {
        return $null
    }

    if (-not $uri.Host -or $uri.Port -lt 1) {
        return $null
    }

    return [pscustomobject]@{
        Host = $uri.Host
        Port = $uri.Port
        Url  = "http://{0}:{1}" -f $uri.Host, $uri.Port
    }
}

function Resolve-ProxyServerValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProxyServer
    )

    $rawValue = $ProxyServer.Trim()
    if ([string]::IsNullOrWhiteSpace($rawValue)) {
        return $null
    }

    if ($rawValue.Contains("=")) {
        $map = @{}
        foreach ($entry in ($rawValue -split ';')) {
            $trimmedEntry = $entry.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmedEntry) -or -not $trimmedEntry.Contains("=")) {
                continue
            }

            $parts = $trimmedEntry -split '=', 2
            $scheme = $parts[0].Trim().ToLowerInvariant()
            $value = $parts[1].Trim()
            if (-not [string]::IsNullOrWhiteSpace($scheme) -and -not [string]::IsNullOrWhiteSpace($value)) {
                $map[$scheme] = $value
            }
        }

        foreach ($preferredScheme in @("http", "https", "socks", "socks5")) {
            if ($map.ContainsKey($preferredScheme)) {
                return ConvertTo-ProxyEndpoint -RawValue $map[$preferredScheme]
            }
        }

        foreach ($value in $map.Values) {
            $resolved = ConvertTo-ProxyEndpoint -RawValue $value
            if ($null -ne $resolved) {
                return $resolved
            }
        }

        return $null
    }

    return ConvertTo-ProxyEndpoint -RawValue $rawValue
}

function Get-InternetSettingsProxy {
    $settingsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"

    try {
        $settings = Get-ItemProperty -LiteralPath $settingsPath
    } catch {
        return $null
    }

    if ($settings.ProxyEnable -ne 1) {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($settings.ProxyServer)) {
        return $null
    }

    return Resolve-ProxyServerValue -ProxyServer $settings.ProxyServer
}

function Get-EnvFileProxy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $rawLines = Get-Content -LiteralPath $Path -ErrorAction Stop
    foreach ($key in @("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY")) {
        foreach ($line in $rawLines) {
            if ($line -match "^\s*$key\s*=\s*(.+?)\s*$") {
                $resolved = ConvertTo-ProxyEndpoint -RawValue $Matches[1]
                if ($null -ne $resolved) {
                    return $resolved
                }
            }
        }
    }

    return $null
}

function Get-DefaultProxy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProxyHost,
        [Parameter(Mandatory = $true)]
        [int]$Port
    )

    return [pscustomobject]@{
        Host = $ProxyHost
        Port = $Port
        Url  = "http://{0}:{1}" -f $ProxyHost, $Port
    }
}

function Format-ProxyEnvContent {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Proxy
    )

    return @(
        'HTTP_PROXY="{0}"' -f $Proxy.Url
        'HTTPS_PROXY="{0}"' -f $Proxy.Url
        'NO_PROXY="localhost,127.0.0.1"'
        'ALL_PROXY="{0}"' -f $Proxy.Url
    ) -join [Environment]::NewLine
}

function Update-CodexConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$DesiredValues
    )

    $result = [ordered]@{
        Path        = $Path
        Created     = $false
        Changed     = $false
        BackupPath  = $null
        UpdatedKeys = @()
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        $content = (($DesiredValues.GetEnumerator() | ForEach-Object {
                    "{0} = {1}" -f $_.Key, $_.Value
                }) -join [Environment]::NewLine) + [Environment]::NewLine
        [System.IO.File]::WriteAllText($Path, $content, [System.Text.UTF8Encoding]::new($false))
        $result.Created = $true
        $result.Changed = $true
        $result.UpdatedKeys = @($DesiredValues.Keys)
        return [pscustomobject]$result
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in (Get-Content -LiteralPath $Path -ErrorAction Stop)) {
        [void]$lines.Add($line)
    }

    $firstSectionIndex = $lines.Count
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^\s*\[') {
            $firstSectionIndex = $index
            break
        }
    }

    $topLevelLines = [System.Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt $firstSectionIndex; $index++) {
        [void]$topLevelLines.Add($lines[$index])
    }

    foreach ($key in $DesiredValues.Keys) {
        $matchingIndexes = [System.Collections.Generic.List[int]]::new()
        for ($index = 0; $index -lt $topLevelLines.Count; $index++) {
            if ($topLevelLines[$index] -match ("^\s*{0}\s*=" -f [regex]::Escape($key))) {
                [void]$matchingIndexes.Add($index)
            }
        }

        $newLine = "{0} = {1}" -f $key, $DesiredValues[$key]
        if ($matchingIndexes.Count -gt 0) {
            $firstMatchIndex = $matchingIndexes[0]
            if ($topLevelLines[$firstMatchIndex] -ne $newLine) {
                $topLevelLines[$firstMatchIndex] = $newLine
                $result.Changed = $true
            }

            for ($dup = $matchingIndexes.Count - 1; $dup -ge 1; $dup--) {
                $topLevelLines.RemoveAt($matchingIndexes[$dup])
                $result.Changed = $true
            }
        } else {
            [void]$topLevelLines.Add($newLine)
            $result.Changed = $true
        }

        $result.UpdatedKeys += $key
    }

    if ($result.Changed) {
        $result.BackupPath = New-BackupFile -Path $Path

        $finalLines = [System.Collections.Generic.List[string]]::new()
        foreach ($line in $topLevelLines) {
            [void]$finalLines.Add($line)
        }

        if ($firstSectionIndex -lt $lines.Count -and $finalLines.Count -gt 0 -and $finalLines[$finalLines.Count - 1] -ne "") {
            [void]$finalLines.Add("")
        }

        for ($index = $firstSectionIndex; $index -lt $lines.Count; $index++) {
            [void]$finalLines.Add($lines[$index])
        }

        $content = ($finalLines -join [Environment]::NewLine) + [Environment]::NewLine
        [System.IO.File]::WriteAllText($Path, $content, [System.Text.UTF8Encoding]::new($false))
    }

    return [pscustomobject]$result
}

function Update-CodexEnvFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Proxy
    )

    $result = [ordered]@{
        Path       = $Path
        Created    = $false
        Changed    = $false
        BackupPath = $null
        ProxyUrl   = $Proxy.Url
    }

    $content = (Format-ProxyEnvContent -Proxy $Proxy) + [Environment]::NewLine

    if (Test-Path -LiteralPath $Path) {
        $existingContent = [System.IO.File]::ReadAllText($Path)
        if ($existingContent -ne $content) {
            $result.BackupPath = New-BackupFile -Path $Path
            [System.IO.File]::WriteAllText($Path, $content, [System.Text.UTF8Encoding]::new($false))
            $result.Changed = $true
        }
    } else {
        [System.IO.File]::WriteAllText($Path, $content, [System.Text.UTF8Encoding]::new($false))
        $result.Created = $true
        $result.Changed = $true
    }

    return [pscustomobject]$result
}

if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    throw "This script only supports Windows."
}

$resolvedCodexHome = [System.IO.Path]::GetFullPath($CodexHome)
[System.IO.Directory]::CreateDirectory($resolvedCodexHome) | Out-Null

$configPath = Join-Path $resolvedCodexHome "config.toml"
$envPath = Join-Path $resolvedCodexHome ".env"

$proxy = Get-InternetSettingsProxy
$proxySource = "Internet Settings"

if ($null -eq $proxy) {
    $proxy = Get-EnvFileProxy -Path $envPath
    $proxySource = "existing .env"
}

if ($null -eq $proxy) {
    $proxy = Get-DefaultProxy -ProxyHost $DefaultProxyHost -Port $DefaultProxyPort
    $proxySource = "default"
}

$configResult = Update-CodexConfig -Path $configPath -DesiredValues $DesiredConfig
$envResult = Update-CodexEnvFile -Path $envPath -Proxy $proxy

$summary = [ordered]@{
    codexHome       = $resolvedCodexHome
    configPath      = $configResult.Path
    configCreated   = $configResult.Created
    configChanged   = $configResult.Changed
    configKeys      = $configResult.UpdatedKeys
    configBackup    = $configResult.BackupPath
    envPath         = $envResult.Path
    envCreated      = $envResult.Created
    envChanged      = $envResult.Changed
    envBackup       = $envResult.BackupPath
    proxySource     = $proxySource
    proxyUrl        = $envResult.ProxyUrl
}

$summary | ConvertTo-Json -Depth 4
