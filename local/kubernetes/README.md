# Local Kubernetes backend

Docker Desktop Kubernetes에서 backend 애플리케이션 세 개만 실행하고, PostgreSQL, Redis, Kafka, OpenSearch는 기존 Docker Compose에 유지한다.

```text
Docker Desktop
├─ Kubernetes namespace: log-analyzer-local
│  ├─ gateway-service
│  ├─ log-service
│  └─ event-consumer
└─ Docker Compose
   ├─ PostgreSQL
   ├─ Redis
   ├─ Kafka
   └─ OpenSearch
```

Pod는 Compose service name을 직접 사용할 수 없으므로 `host.docker.internal`과 host published port를 사용한다. Kafka는 broker metadata도 Pod가 해석할 수 있어야 하므로 listener를 분리한다.

| Kafka listener | Address returned to client | Client |
| --- | --- | --- |
| `INTERNAL` | `kafka:9092` | Compose containers |
| `EXTERNAL` | `localhost:19092` | Host IDE processes |
| `KUBERNETES` | `host.docker.internal:29092` | Kubernetes Pods |

## Prerequisites

- Docker Desktop Kubernetes context가 `docker-desktop`이어야 한다.
- Docker Desktop Kubernetes가 현재 구성처럼 단일 node여야 한다.
- `local/.env`가 존재하고 PostgreSQL의 `POSTGRES_USER`, `POSTGRES_PASSWORD`가 설정되어 있어야 한다.
- Compose 인프라와 Kafka/OpenSearch 초기 리소스가 준비되어 있어야 한다.

현재 Compose 포트는 `127.0.0.1` 바인딩을 유지한다. Docker Desktop의 `host.docker.internal` forwarding을 사용하므로 로컬 네트워크 전체에 인프라 포트를 노출할 필요가 없다.

## 1. Recreate Kafka with the Kubernetes listener

`log-analyzer-infra/local`에서 실행한다.

```powershell
docker compose --env-file .env -f docker-compose.yml up -d kafka
docker compose --env-file .env -f docker-compose.yml ps
```

기존 Kafka volume과 topic은 유지되며 container 설정만 갱신된다. 필요한 경우 기존 스크립트로 topic과 OpenSearch 리소스를 다시 확인한다.

```bash
bash scripts/create-kafka-topics.sh
bash scripts/create-opensearch-index.sh
```

## 2. Build backend images

`log-analyzer-backend`에서 실행한다.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\kubernetes\build-images.ps1
```

생성되는 local image는 다음과 같다.

- `log-analyzer/gateway-service:local`
- `log-analyzer/log-service:local`
- `log-analyzer/event-consumer:local`

모든 컨테이너는 UID/GID `10001`의 non-root 사용자로 실행된다.

## 3. Deploy

`log-analyzer-infra/local`에서 실행한다.

```powershell
powershell -ExecutionPolicy Bypass -File .\kubernetes\deploy.ps1
```

배포 스크립트는 다음 작업을 수행한다.

1. `docker-desktop` context와 local image를 확인한다.
2. `log-analyzer-local` namespace를 만든다.
3. 임시 privileged loader Pod를 사용해 local image를 단일 kind node의 containerd에 가져온 뒤 loader를 삭제한다.
4. 추적되지 않는 `local/.env`에서 DB 계정을 읽어 `backend-database` Secret을 생성한다.
5. ConfigMap, Deployment, ClusterIP Service를 적용한다.
6. 세 Deployment의 rollout 완료를 기다린다.

Docker Desktop의 kind node는 Docker CLI image store와 별도일 수 있다. loader는 이 local 단일-node 차이를 해결하기 위해 node root를 잠시 mount하며, `docker-desktop`이 아닌 context에서는 기본적으로 실행을 거부하고 작업 후 항상 제거된다.

DB 비밀번호는 Kubernetes manifest나 Git 추적 파일에 저장하지 않는다. 이 Secret은 local 실험용이며, 운영 환경에서는 외부 secret manager를 사용해야 한다.

## 4. End-to-end smoke test

```powershell
powershell -ExecutionPolicy Bypass -File .\kubernetes\smoke-test.ps1
```

스크립트는 임시 port-forward를 열고 아래 흐름을 검증한 뒤 종료한다.

```text
POST /api/logs
  -> gateway-service
  -> log-service
  -> Kafka
  -> event-consumer
  -> OpenSearch
  -> GET /api/logs?requestId=...
```

수동 접근이 필요하면 다음 명령을 유지한 별도 터미널에서 실행한다.

```powershell
kubectl -n log-analyzer-local port-forward service/gateway-service 17010:7010
```

## Operations

```powershell
kubectl -n log-analyzer-local get deployments,pods,services
kubectl -n log-analyzer-local logs deployment/log-service
kubectl -n log-analyzer-local logs deployment/event-consumer
kubectl -n log-analyzer-local logs deployment/gateway-service
```

`event-consumer`의 status API는 Pod 메모리 기반 값이므로 기본 replica는 `1`이다. Kafka topic의 세 partition을 병렬 처리할 때는 status 응답이 Pod별 값이라는 점을 감안해 다음처럼 확장한다.

```powershell
kubectl -n log-analyzer-local scale deployment/event-consumer --replicas=3
```

local Kubernetes 리소스를 모두 제거하려면 다음을 실행한다. Compose 인프라와 volume은 삭제되지 않는다.

```powershell
kubectl delete namespace log-analyzer-local
```
