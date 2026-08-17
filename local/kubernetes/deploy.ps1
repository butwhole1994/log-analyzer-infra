[CmdletBinding()]
param(
    [string]$InfraEnvPath = "",
    [switch]$AllowNonDockerDesktopContext,
    [switch]$SkipImageLoad,
    [switch]$SkipRolloutRestart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$namespace = "log-analyzer-local"
$deployments = @("gateway-service", "log-service", "event-consumer")
$images = $deployments | ForEach-Object { "log-analyzer/${_}:local" }

if ([string]::IsNullOrWhiteSpace($InfraEnvPath)) {
    $InfraEnvPath = Join-Path $PSScriptRoot "..\.env"
}

function Invoke-Kubectl {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$KubectlArguments
    )

    & kubectl @KubectlArguments
    if ($LASTEXITCODE -ne 0) {
        throw "kubectl failed: $($KubectlArguments -join ' ')"
    }
}

function Read-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $escapedName = [Regex]::Escape($Name)
    $line = Get-Content -LiteralPath $Path -Encoding utf8 |
        Where-Object { $_ -match "^\s*${escapedName}\s*=" } |
        Select-Object -Last 1

    if ($null -eq $line) {
        throw "Required value is missing from ${Path}: ${Name}"
    }

    $value = ($line -split "=", 2)[1].Trim()
    if ($value.Length -ge 2) {
        $isDoubleQuoted = $value.StartsWith('"') -and $value.EndsWith('"')
        $isSingleQuoted = $value.StartsWith("'") -and $value.EndsWith("'")
        if ($isDoubleQuoted -or $isSingleQuoted) {
            $value = $value.Substring(1, $value.Length - 2)
        }
    }

    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Required value is empty in ${Path}: ${Name}"
    }

    return $value
}

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    throw "kubectl was not found. Enable Docker Desktop Kubernetes first."
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "docker was not found. Start Docker Desktop first."
}

$currentContext = ([string](& kubectl config current-context)).Trim()
if ($LASTEXITCODE -ne 0) {
    throw "Unable to read the current kubectl context."
}

if (-not $AllowNonDockerDesktopContext -and $currentContext -ne "docker-desktop") {
    throw "Refusing to deploy to context '${currentContext}'. Select docker-desktop or pass -AllowNonDockerDesktopContext."
}

$resolvedEnvPath = (Resolve-Path -LiteralPath $InfraEnvPath).Path
$dbUsername = Read-DotEnvValue -Path $resolvedEnvPath -Name "POSTGRES_USER"
$dbPassword = Read-DotEnvValue -Path $resolvedEnvPath -Name "POSTGRES_PASSWORD"

foreach ($image in $images) {
    & docker image inspect $image *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Local image is missing: ${image}. Run log-analyzer-backend/scripts/kubernetes/build-images.ps1 first."
    }
}

if (-not $SkipImageLoad) {
    & (Join-Path $PSScriptRoot "load-images.ps1") `
        -Images $images `
        -AllowNonDockerDesktopContext:$AllowNonDockerDesktopContext
}

Invoke-Kubectl -KubectlArguments @(
    "apply",
    "-f",
    (Join-Path $PSScriptRoot "namespace.yaml")
)

$secretArguments = @(
    "-n", $namespace,
    "create", "secret", "generic", "backend-database",
    "--from-literal=DB_USERNAME=${dbUsername}",
    "--from-literal=DB_PASSWORD=${dbPassword}",
    "--dry-run=client",
    "-o", "yaml"
)
$secretManifest = & kubectl @secretArguments
if ($LASTEXITCODE -ne 0) {
    throw "Unable to render the backend database Secret."
}

$secretManifest | & kubectl apply -f -
if ($LASTEXITCODE -ne 0) {
    throw "Unable to apply the backend database Secret."
}

Invoke-Kubectl -KubectlArguments @("apply", "-k", $PSScriptRoot)

if (-not $SkipRolloutRestart) {
    foreach ($deployment in $deployments) {
        Invoke-Kubectl -KubectlArguments @(
            "-n", $namespace,
            "rollout", "restart", "deployment/${deployment}"
        )
    }
}

foreach ($deployment in $deployments) {
    Invoke-Kubectl -KubectlArguments @(
        "-n", $namespace,
        "rollout", "status", "deployment/${deployment}",
        "--timeout=240s"
    )
}

Invoke-Kubectl -KubectlArguments @(
    "-n", $namespace,
    "get", "deployments,pods,services",
    "-o", "wide"
)
