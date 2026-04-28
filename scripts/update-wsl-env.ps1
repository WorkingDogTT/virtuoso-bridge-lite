param(
    [string]$EnvPath = (Join-Path (Get-Location) ".env"),
    [switch]$Restart
)

$ErrorActionPreference = "Stop"

function Invoke-WslText {
    param([string]$Command)

    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & wsl.exe -e sh -lc $Command 2>&1
        return ($output -join "`n")
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }
}

function Get-WslIpv4 {
    $routeOutput = Invoke-WslText "ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -n1"
    $candidate = ($routeOutput | Select-String -Pattern "\b(?:\d{1,3}\.){3}\d{1,3}\b" -AllMatches).Matches.Value | Select-Object -First 1
    if ($candidate) {
        return $candidate
    }

    $hostOutput = Invoke-WslText "hostname -I"
    $candidate = ($hostOutput | Select-String -Pattern "\b(?:\d{1,3}\.){3}\d{1,3}\b" -AllMatches).Matches.Value |
        Where-Object { $_ -ne "127.0.0.1" } |
        Select-Object -First 1
    if ($candidate) {
        return $candidate
    }

    throw "Could not determine the WSL IPv4 address. Is WSL running?"
}

$resolvedEnvPath = (Resolve-Path -LiteralPath $EnvPath -ErrorAction SilentlyContinue)
if (-not $resolvedEnvPath) {
    throw ".env file not found: $EnvPath"
}
$resolvedEnvPath = $resolvedEnvPath.Path

$wslIp = Get-WslIpv4
$content = Get-Content -LiteralPath $resolvedEnvPath -Raw

if ($content -match "(?m)^VB_REMOTE_HOST\s*=") {
    $content = $content -replace "(?m)^VB_REMOTE_HOST\s*=.*$", "VB_REMOTE_HOST=$wslIp"
} else {
    if ($content.Length -gt 0 -and -not $content.EndsWith("`n")) {
        $content += "`n"
    }
    $content += "VB_REMOTE_HOST=$wslIp`n"
}

Set-Content -LiteralPath $resolvedEnvPath -Value $content -Encoding UTF8 -NoNewline
Write-Host "Updated $resolvedEnvPath"
Write-Host "VB_REMOTE_HOST=$wslIp"

if ($Restart) {
    $bridge = Join-Path (Get-Location) ".venv\Scripts\virtuoso-bridge.exe"
    if (-not (Test-Path -LiteralPath $bridge)) {
        throw "Cannot find bridge CLI: $bridge"
    }
    & $bridge restart
}
