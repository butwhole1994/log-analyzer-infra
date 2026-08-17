[CmdletBinding()]
param(
    [string[]]$Images = @(
        "log-analyzer/gateway-service:local",
        "log-analyzer/log-service:local",
        "log-analyzer/event-consumer:local"
    ),
    [switch]$AllowNonDockerDesktopContext
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$namespace = "default"
$loaderName = "log-analyzer-image-loader"
$nodeArchivePath = "/tmp/backend-images.tar"
$temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$temporaryDirectory = [System.IO.Path]::GetFullPath(
    (Join-Path $temporaryRoot "log-analyzer-image-loader-$([Guid]::NewGuid().ToString('N'))")
)

if (-not $temporaryDirectory.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to use a temporary directory outside the system temp path: ${temporaryDirectory}"
}

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    throw "kubectl was not found."
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "docker was not found."
}

$currentContext = ([string](& kubectl config current-context)).Trim()
if ($LASTEXITCODE -ne 0) {
    throw "Unable to read the current kubectl context."
}

if (-not $AllowNonDockerDesktopContext -and $currentContext -ne "docker-desktop") {
    throw "Refusing to load images into context '${currentContext}'. Select docker-desktop or pass -AllowNonDockerDesktopContext."
}

$nodeResources = @(& kubectl get nodes -o name)
if ($LASTEXITCODE -ne 0) {
    throw "Unable to list Kubernetes nodes."
}
if ($nodeResources.Count -ne 1) {
    throw "The local image loader currently requires exactly one node; found $($nodeResources.Count)."
}
$nodeName = $nodeResources[0] -replace "^node/", ""

foreach ($image in $Images) {
    & docker image inspect $image *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Local image is missing: ${image}"
    }
}

$loaderPod = @{
    apiVersion = "v1"
    kind = "Pod"
    metadata = @{
        name = $loaderName
        namespace = $namespace
        labels = @{
            "app.kubernetes.io/name" = "log-analyzer-image-loader"
            "app.kubernetes.io/part-of" = "log-analyzer"
        }
    }
    spec = @{
        nodeName = $nodeName
        restartPolicy = "Never"
        automountServiceAccountToken = $false
        terminationGracePeriodSeconds = 0
        containers = @(
            @{
                name = "loader"
                image = "apache/kafka:3.7.0"
                imagePullPolicy = "IfNotPresent"
                command = @(
                    "/bin/sh",
                    "-c",
                    "trap 'exit 0' TERM INT; while true; do sleep 3600; done"
                )
                securityContext = @{
                    privileged = $true
                    runAsUser = 0
                }
                resources = @{
                    requests = @{
                        cpu = "10m"
                        memory = "32Mi"
                    }
                    limits = @{
                        cpu = "500m"
                        memory = "1Gi"
                    }
                }
                volumeMounts = @(
                    @{
                        name = "host-root"
                        mountPath = "/host"
                    }
                )
            }
        )
        volumes = @(
            @{
                name = "host-root"
                hostPath = @{
                    path = "/"
                    type = "Directory"
                }
            }
        )
    }
}

$archiveName = "backend-images.tar"
$archivePath = Join-Path $temporaryDirectory $archiveName
$loaderCreated = $false

New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null

try {
    Write-Host "Exporting local images to a shared archive"
    & docker image save --output $archivePath @Images
    if ($LASTEXITCODE -ne 0) {
        throw "docker image save failed."
    }

    & kubectl -n $namespace delete pod $loaderName --ignore-not-found --wait=true | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to remove a stale image loader Pod."
    }

    $loaderPod | ConvertTo-Json -Depth 12 | & kubectl create -f -
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to create the image loader Pod."
    }
    $loaderCreated = $true

    $loaderReady = $false
    for ($attempt = 1; $attempt -le 60; $attempt++) {
        $readyStatus = & kubectl -n $namespace get pod $loaderName `
            -o "jsonpath={.status.conditions[?(@.type=='Ready')].status}" 2>$null
        if ($LASTEXITCODE -eq 0 -and $readyStatus -eq "True") {
            $loaderReady = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $loaderReady) {
        throw "The image loader Pod did not become ready."
    }

    Push-Location $temporaryDirectory
    try {
        & kubectl -n $namespace cp ".\${archiveName}" "${loaderName}:/host/tmp" -c loader
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to copy the image archive to the Kubernetes node."
        }
    }
    finally {
        Pop-Location
    }

    & kubectl -n $namespace exec $loaderName -c loader -- test -f "/host${nodeArchivePath}"
    if ($LASTEXITCODE -ne 0) {
        throw "The image archive was not found in the Kubernetes node after copy."
    }

    $ctrPath = $null
    foreach ($candidate in @("/usr/local/bin/ctr", "/usr/bin/ctr", "/bin/ctr")) {
        & kubectl -n $namespace exec $loaderName -c loader -- test -x "/host${candidate}"
        if ($LASTEXITCODE -eq 0) {
            $ctrPath = $candidate
            break
        }
    }
    if ($null -eq $ctrPath) {
        throw "Unable to locate ctr in the Kubernetes node filesystem."
    }

    Write-Host "Importing local images into node ${nodeName}"
    & kubectl -n $namespace exec $loaderName -c loader -- `
        chroot /host $ctrPath --namespace k8s.io images import $nodeArchivePath
    if ($LASTEXITCODE -ne 0) {
        throw "containerd image import failed."
    }

    $nodeImages = & kubectl -n $namespace exec $loaderName -c loader -- `
        chroot /host $ctrPath --namespace k8s.io images list
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to verify images in the Kubernetes node."
    }

    foreach ($image in $Images) {
        if (($nodeImages -join "`n") -notmatch [Regex]::Escape($image)) {
            throw "Image was not found in the Kubernetes node after import: ${image}"
        }
    }
}
finally {
    if ($loaderCreated) {
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"
        try {
            & kubectl -n $namespace exec $loaderName -c loader -- rm -f "/host${nodeArchivePath}" *> $null
            & kubectl -n $namespace delete pod $loaderName --ignore-not-found --wait=true *> $null
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
    }

    if (Test-Path -LiteralPath $temporaryDirectory) {
        $resolvedTemporaryDirectory = [System.IO.Path]::GetFullPath(
            (Resolve-Path -LiteralPath $temporaryDirectory).Path
        )
        if ($resolvedTemporaryDirectory.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTemporaryDirectory -Recurse -Force
        }
    }
}
