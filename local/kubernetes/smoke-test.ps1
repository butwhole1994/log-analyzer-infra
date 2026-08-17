[CmdletBinding()]
param(
    [string]$Namespace = "log-analyzer-local",
    [ValidateRange(1024, 65535)]
    [int]$LocalPort = 17010
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    throw "kubectl was not found."
}

$kubectlPath = (Get-Command kubectl).Source
$stdoutPath = [System.IO.Path]::GetTempFileName()
$stderrPath = [System.IO.Path]::GetTempFileName()
$portForward = $null
$portProbe = [System.Net.Sockets.TcpListener]::new(
    [System.Net.IPAddress]::Loopback,
    $LocalPort
)

try {
    $portProbe.Start()
}
catch {
    throw "Local port ${LocalPort} is already in use. Choose another value with -LocalPort."
}
finally {
    $portProbe.Stop()
}

try {
    $portForward = Start-Process `
        -FilePath $kubectlPath `
        -ArgumentList @(
            "-n", $Namespace,
            "port-forward", "service/gateway-service",
            "${LocalPort}:7010"
        ) `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -WindowStyle Hidden `
        -PassThru

    $baseUrl = "http://127.0.0.1:${LocalPort}"
    $gatewayReady = $false

    for ($attempt = 1; $attempt -le 30; $attempt++) {
        if ($portForward.HasExited) {
            $details = Get-Content -Raw -LiteralPath $stderrPath -ErrorAction SilentlyContinue
            throw "kubectl port-forward exited unexpectedly. ${details}"
        }

        try {
            $health = Invoke-RestMethod `
                -Uri "${baseUrl}/actuator/health" `
                -Method Get `
                -TimeoutSec 3
            if ($health.status -eq "UP") {
                $gatewayReady = $true
                break
            }
        }
        catch {
            Start-Sleep -Seconds 1
        }
    }

    if (-not $gatewayReady) {
        throw "Gateway did not become ready through port-forward."
    }

    $testId = "k8s-$([Guid]::NewGuid().ToString('N'))"
    $requestBody = @{
        serviceName = "kubernetes-smoke-test"
        level = "INFO"
        message = "Kubernetes local smoke test ${testId}"
        timestamp = [DateTimeOffset]::UtcNow.AddSeconds(-5).ToString("o")
        traceId = $testId
        requestId = $testId
        metadata = @{
            runtime = "docker-desktop-kubernetes"
        }
    } | ConvertTo-Json -Depth 5
    $correlationHeaders = @{
        "X-Trace-Id" = $testId
        "X-Request-Id" = $testId
    }

    $publishResponse = Invoke-RestMethod `
        -Uri "${baseUrl}/api/logs" `
        -Method Post `
        -Headers $correlationHeaders `
        -ContentType "application/json" `
        -Body $requestBody `
        -TimeoutSec 10

    if (-not $publishResponse.success) {
        throw "Log publish API returned success=false."
    }

    $publishedRequestId = $publishResponse.data.requestId
    if ([string]::IsNullOrWhiteSpace($publishedRequestId)) {
        throw "Log publish API did not return a requestId."
    }

    $consumed = $false
    for ($attempt = 1; $attempt -le 45; $attempt++) {
        try {
            $consumerStatus = Invoke-RestMethod `
                -Uri "${baseUrl}/event-consumer/api/consumer/log-events/status" `
                -Method Get `
                -TimeoutSec 5
            if ($consumerStatus.success -and $consumerStatus.data.lastEvent.requestId -eq $publishedRequestId) {
                $consumed = $true
                break
            }
        }
        catch {
            # The consumer and OpenSearch path are eventually consistent during startup.
        }
        Start-Sleep -Seconds 2
    }

    if (-not $consumed) {
        throw "event-consumer did not report the test message within 90 seconds."
    }

    $indexed = $false
    $encodedRequestId = [Uri]::EscapeDataString($publishedRequestId)
    for ($attempt = 1; $attempt -le 30; $attempt++) {
        try {
            $searchResponse = Invoke-RestMethod `
                -Uri "${baseUrl}/api/logs?requestId=${encodedRequestId}" `
                -Method Get `
                -TimeoutSec 5
            $matchingItem = @($searchResponse.data.items) |
                Where-Object { $_.requestId -eq $publishedRequestId } |
                Select-Object -First 1
            if ($searchResponse.success -and $null -ne $matchingItem) {
                $indexed = $true
                break
            }
        }
        catch {
            # Retry while OpenSearch refreshes the index.
        }
        Start-Sleep -Seconds 2
    }

    if (-not $indexed) {
        throw "The test message was consumed but was not returned by OpenSearch within 60 seconds."
    }

    [PSCustomObject]@{
        Success = $true
        RequestId = $publishedRequestId
        EventId = $publishResponse.data.id
        GatewayUrl = $baseUrl
        ConsumerGroup = $consumerStatus.data.consumerGroupId
    }
}
finally {
    if ($null -ne $portForward -and -not $portForward.HasExited) {
        Stop-Process -Id $portForward.Id -Force
        $portForward.WaitForExit()
    }

    Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
}
