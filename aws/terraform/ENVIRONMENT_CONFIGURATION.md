# ECS runtime configuration

## Single environment-variable contract

Applications use the following keys in **local, dev, and prod**.  The value source changes by environment; the key must not.

| Key | Classification | AWS path |
|---|---|---|
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USERNAME` | SSM String parameter | `/{project}/{env}/db/{host,port,name,username}` |
| `DB_PASSWORD` | Secrets Manager | `/{project}/{env}/db/password` |
| `KAFKA_BOOTSTRAP_SERVERS`, `KAFKA_TOPIC_LOG_EVENTS`, `KAFKA_TOPIC_LOG_EVENTS_DLQ` | SSM String parameter | `/{project}/{env}/kafka/*` |
| `OPENSEARCH_URL`, `OPENSEARCH_READ_TARGET`, `OPENSEARCH_INDEX_NAME`, `OPENSEARCH_PIPELINE_NAME` | SSM String parameter | `/{project}/{env}/opensearch/*` |
| service-only sensitive setting | Secrets Manager | `/{project}/{env}/services/{service}/{name}` |
| service-only non-sensitive setting | SSM String parameter | `/{project}/{env}/services/{service}/{name}` |

`DB_PASSWORD`, API keys, OAuth client secrets, signing keys, and private certificates belong in Secrets Manager. Endpoints, ports, topic/index names, feature flags, and log levels belong in Parameter Store. Do not place secrets in `environment` in an ECS task definition or in Terraform variables.

## Terraform apply order

```powershell
cd aws/terraform/envs/dev
Copy-Item terraform.tfvars.example terraform.tfvars
# Edit only infrastructure identifiers and non-sensitive endpoint values.
terraform init
terraform apply
```

Before applying, the supplied execution role must have the AWS managed policy `service-role/AmazonECSTaskExecutionRolePolicy` attached. It provides the standard ECR image-pull and CloudWatch Logs permissions; this configuration adds only the SSM and Secrets Manager read policy.

After the first apply, set the password without recording it in Terraform state or Git:

```powershell
aws secretsmanager put-secret-value --secret-id /log-analyzer/dev/db/password --secret-string '<password>'
```

The ECS execution role receives the minimum `ssm:GetParameter(s)` and `secretsmanager:GetSecretValue` permissions necessary for the `/log-analyzer/dev/*` configuration paths. ECS injects both SSM parameter ARNs and Secrets Manager ARNs through the container definition `secrets.valueFrom` field.

For `prod`, copy `envs/dev` to `envs/prod`, change only `local.environment` to `prod`, and supply prod infrastructure values. Keep the same keys and relative SSM/Secrets paths. Use a distinct remote Terraform state for each environment.
