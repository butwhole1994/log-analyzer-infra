# Log Analyzer 로컬 실행 가이드

이 문서는 `log-analyzer-infra`와 [log-analyzer-backend](https://github.com/butwhole1994/log-analyzer-backend)를 함께 실행하고, 다음 정상 처리 경로를 로컬에서 확인하는 절차입니다.

```text
Client
  -> Gateway
  -> Log Service
  -> Kafka
  -> Event Consumer
  -> OpenSearch
  -> Search API
```

기본 실행은 Docker Compose 인프라와 로컬 JVM 애플리케이션을 조합합니다. Kubernetes는 필수가 아니며 별도 검증이 필요할 때만 사용합니다.

## 실행 구성

| 실행 방식 | 구성요소 | 용도 |
| --- | --- | --- |
| Docker Compose | PostgreSQL, Redis, Kafka, OpenSearch, 관리 UI | backend가 연결할 로컬 인프라 |
| Gradle `bootRun` | Gateway, Log Service, Event Consumer | 가장 단순한 기능 확인 경로 |
| Docker Desktop Kubernetes | backend 애플리케이션 3개 | manifest, probe, resource/security context와 자동 E2E 확인 |

Docker Compose만 실행하면 backend API는 시작되지 않습니다. 전체 기능 확인에는 두 저장소가 모두 필요합니다.

## 1. 사전 준비

- Git
- Docker Desktop 또는 Docker Engine
- Docker Compose v2
- JDK 17
- `curl`
- Linux: Bash
- Windows: Git Bash와 Windows PowerShell

최초 실행에서는 Docker image와 Gradle dependency를 내려받으므로 인터넷 연결이 필요합니다.

Windows에서 WSL을 사용할 경우 Docker Desktop의 WSL integration이 활성화되어 있어야 합니다. 이 문서의 Windows 기본 경로는 Git Bash로 인프라를 준비하고 PowerShell로 backend를 실행하는 방식입니다.

## 2. 저장소 배치

두 저장소를 같은 상위 디렉터리에 둡니다.

```bash
mkdir log-analyzer-workspace
cd log-analyzer-workspace
git clone https://github.com/butwhole1994/log-analyzer-infra.git
git clone https://github.com/butwhole1994/log-analyzer-backend.git
```

```text
log-analyzer-workspace/
├─ log-analyzer-infra/
└─ log-analyzer-backend/
```

## 3. Docker Compose 인프라 실행

Linux Bash 또는 Windows Git Bash에서 실행합니다.

```bash
cd log-analyzer-infra/local

bash scripts/up.sh --wait --wait-timeout 180
bash scripts/create-kafka-topics.sh
bash scripts/create-opensearch-index.sh
```

각 명령의 역할은 다음과 같습니다.

1. Compose 컨테이너를 시작하고 health check 완료를 기다립니다.
2. auto-create가 비활성화된 Kafka에 main/DLQ topic을 생성합니다.
3. OpenSearch index template, mapping, ingest pipeline, initial index와 read/write alias를 구성합니다.

`local/.env`에는 backend `local` profile과 맞춘 포트 및 로컬 계정이 포함되어 있습니다. 이 파일의 기본값을 변경하면 backend 환경 변수와 Kubernetes ConfigMap도 함께 맞춰야 합니다.

Compose 상태 확인:

```bash
docker compose --env-file .env -f docker-compose.yml ps
```

정상 상태에서는 PostgreSQL, Redis, Kafka, OpenSearch가 `healthy`이고 관리 UI 컨테이너가 실행 중이어야 합니다.

주요 인프라 URL:

| 구성요소 | 주소 |
| --- | --- |
| Kafka | `localhost:19092` |
| Kafka UI | `http://localhost:18080` |
| Redis Commander | `http://localhost:18081` |
| OpenSearch | `http://localhost:19200` |
| OpenSearch Dashboards | `http://localhost:15601` |

## 4. Backend 애플리케이션 실행

새 터미널 3개를 열고 `log-analyzer-backend`에서 각각 실행합니다. Event Consumer를 먼저 실행하면 이후 발행되는 이벤트를 바로 소비할 수 있습니다.

### Linux, macOS, WSL, Git Bash

backend의 `gradlew`가 실행 권한 없이 clone된 환경에서도 동작하도록 `bash ./gradlew`를 사용합니다.

터미널 1 — Event Consumer:

```bash
cd log-analyzer-backend
bash ./gradlew :event-consumer:bootRun --args='--spring.profiles.active=local'
```

터미널 2 — Log Service:

```bash
cd log-analyzer-backend
bash ./gradlew :log-service:bootRun --args='--spring.profiles.active=local'
```

터미널 3 — Gateway:

```bash
cd log-analyzer-backend
bash ./gradlew :gateway-service:bootRun --args='--spring.profiles.active=local'
```

### Windows PowerShell

터미널 1 — Event Consumer:

```powershell
cd .\log-analyzer-backend
.\gradlew.bat :event-consumer:bootRun --args="--spring.profiles.active=local"
```

터미널 2 — Log Service:

```powershell
cd .\log-analyzer-backend
.\gradlew.bat :log-service:bootRun --args="--spring.profiles.active=local"
```

터미널 3 — Gateway:

```powershell
cd .\log-analyzer-backend
.\gradlew.bat :gateway-service:bootRun --args="--spring.profiles.active=local"
```

애플리케이션 기본 URL:

| 애플리케이션 | URL |
| --- | --- |
| Gateway | `http://localhost:7010` |
| Log Service | `http://localhost:7020` |
| Event Consumer | `http://localhost:7030` |

## 5. 준비 상태 확인

세 backend 애플리케이션이 모두 시작된 후 Linux 또는 Git Bash에서 실행합니다.

```bash
cd log-analyzer-infra/local
bash scripts/health-check.sh
```

이 스크립트는 다음 범위를 확인합니다.

- PostgreSQL, Redis, Kafka, OpenSearch와 관리 UI
- Kafka main/DLQ topic과 Consumer Group
- OpenSearch index, read/write alias와 ingest pipeline
- 세 backend 애플리케이션의 Actuator health
- Gateway에서 Log Service로 연결되는 route

Windows PowerShell에서는 backend 애플리케이션만 별도로 확인할 수 있습니다.

```powershell
cd .\log-analyzer-backend
.\scripts\local-health-check.ps1
```

PowerShell 스크립트는 애플리케이션 기동과 Kafka 설정값 주입을 확인합니다. Kafka broker 통신, consume, OpenSearch 색인까지 확인하는 E2E 검증은 아닙니다.

## 6. E2E 동작 확인

매 실행마다 고유한 `traceId`와 `requestId`를 생성한 후 Gateway로 로그를 발행하고, 같은 `requestId`가 검색될 때까지 polling합니다. OpenSearch 색인은 비동기이므로 POST 직후 첫 검색이 비어 있을 수 있습니다.

### Linux, macOS, WSL, Git Bash

```bash
test_id="local-$(date -u +%Y%m%d%H%M%S)-$$"

publish_response="$(curl -fsS -X POST http://localhost:7010/api/logs \
  -H 'Content-Type: application/json' \
  -H "X-Trace-Id: ${test_id}" \
  -H "X-Request-Id: ${test_id}" \
  -d "{
    \"serviceName\": \"local-smoke-test\",
    \"level\": \"INFO\",
    \"message\": \"local E2E smoke test ${test_id}\",
    \"timestamp\": \"2020-01-01T00:00:00Z\",
    \"traceId\": \"${test_id}\",
    \"requestId\": \"${test_id}\",
    \"metadata\": {\"runtime\": \"local-jvm\"}
  }")"

echo "${publish_response}"

if ! grep -Fq "${test_id}" <<<"${publish_response}"; then
  echo "Publish failed or the response did not preserve requestId=${test_id}." >&2
  exit 1
fi

found=false
for attempt in {1..30}; do
  search_response="$(curl -fsS \
    "http://localhost:7010/api/logs?requestId=${test_id}&size=10" 2>/dev/null || true)"

  if grep -Fq "${test_id}" <<<"${search_response}"; then
    found=true
    echo "E2E passed: ${test_id}"
    echo "${search_response}"
    break
  fi

  sleep 2
done

if [[ "${found}" != "true" ]]; then
  echo "E2E failed: ${test_id} was not indexed within 60 seconds." >&2
  exit 1
fi
```

### Windows PowerShell

```powershell
$testId = "local-$([Guid]::NewGuid().ToString('N'))"
$body = @{
    serviceName = "local-smoke-test"
    level = "INFO"
    message = "local E2E smoke test $testId"
    timestamp = [DateTimeOffset]::UtcNow.AddSeconds(-5).ToString("o")
    traceId = $testId
    requestId = $testId
    metadata = @{
        runtime = "local-jvm"
    }
} | ConvertTo-Json -Depth 5

$publishResponse = Invoke-RestMethod `
    -Method Post `
    -Uri "http://localhost:7010/api/logs" `
    -ContentType "application/json" `
    -Headers @{
        "X-Trace-Id" = $testId
        "X-Request-Id" = $testId
    } `
    -Body $body

if (-not $publishResponse.success -or $publishResponse.data.requestId -ne $testId) {
    throw "Publish validation failed."
}

$found = $false
for ($attempt = 1; $attempt -le 30; $attempt++) {
    try {
        $searchResponse = Invoke-RestMethod `
            -Method Get `
            -Uri "http://localhost:7010/api/logs?requestId=$testId&size=10"

        $matchingItem = @($searchResponse.data.items) |
            Where-Object { $_.requestId -eq $testId } |
            Select-Object -First 1

        if ($null -ne $matchingItem) {
            $found = $true
            $matchingItem
            break
        }
    }
    catch {
        # OpenSearch refresh가 완료될 때까지 재시도합니다.
    }

    Start-Sleep -Seconds 2
}

if (-not $found) {
    throw "E2E failed: $testId was not indexed within 60 seconds."
}
```

검색 결과에 동일한 `requestId`가 나타나면 다음 전체 정상 경로가 동작한 것입니다.

```text
Gateway -> Log Service -> Kafka -> Event Consumer -> OpenSearch -> Search API
```

## 7. 선택 사항: Docker Desktop Kubernetes

Kubernetes 경로는 backend 애플리케이션 3개만 Docker Desktop Kubernetes에 배포하고, 데이터 인프라는 Compose에 유지합니다.

전제 조건:

- Windows Docker Desktop Kubernetes 활성화
- `kubectl config current-context` 결과가 `docker-desktop`
- 3단계의 Compose 인프라와 Kafka/OpenSearch 리소스 준비 완료

backend image 빌드:

```powershell
cd .\log-analyzer-backend
powershell -ExecutionPolicy Bypass -File .\scripts\kubernetes\build-images.ps1
```

배포와 자동 smoke test:

```powershell
cd .\log-analyzer-infra\local
powershell -ExecutionPolicy Bypass -File .\kubernetes\deploy.ps1
powershell -ExecutionPolicy Bypass -File .\kubernetes\smoke-test.ps1
```

상세 절차와 local image loader의 권한 범위는 [Kubernetes 실행 문서](../local/kubernetes/README.md)를 참고합니다. 이 구성은 Docker Desktop single-node local cluster 전용이며 운영 Kubernetes 배포 절차가 아닙니다.

## 8. 종료

Gradle 애플리케이션은 각 터미널에서 `Ctrl+C`로 종료합니다.

Compose 인프라 종료:

```bash
cd log-analyzer-infra/local
bash scripts/down.sh
```

Windows PowerShell:

```powershell
cd .\log-analyzer-infra\local
docker compose --env-file .env -f docker-compose.yml down
```

`docker compose down`은 named volume을 유지하므로 PostgreSQL, Redis, Kafka, OpenSearch 데이터가 남습니다.

Kubernetes backend 제거 전 현재 context를 확인합니다.

```powershell
kubectl config current-context
kubectl delete namespace log-analyzer-local
```

## 9. 문제 해결

- `port is already allocated`: `7010`, `7020`, `7030`, `15432`, `16379`, `18080`, `18081`, `19092`, `29092`, `15601`, `19200`, `19600`을 사용하는 기존 프로세스나 컨테이너를 확인합니다.
- Kafka topic 오류: `bash scripts/create-kafka-topics.sh`를 다시 실행합니다. topic auto-create는 비활성화되어 있습니다.
- OpenSearch alias 또는 pipeline 오류: `bash scripts/create-opensearch-index.sh`를 다시 실행합니다.
- backend `Connection refused`: Compose 상태와 backend `local` profile의 포트가 일치하는지 확인합니다.
- Linux에서 `./gradlew: Permission denied`: `bash ./gradlew ...` 형식으로 실행합니다.
- Linux에서 OpenSearch가 즉시 종료됨: `docker compose logs opensearch`를 확인하고 host의 `vm.max_map_count`와 Docker 메모리 할당을 점검합니다.

## 관련 문서

- [Kafka 로컬 검증](kafka-local-verification.md)
- [Kafka 로컬 검증 요구사항](kafka-local-verification-requirements.md)
- [OpenSearch 로컬 초기화 요구사항](opensearch-local-initialization-requirements.md)
- [Docker Desktop Kubernetes 실행](../local/kubernetes/README.md)
