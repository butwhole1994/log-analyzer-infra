# Redis

Local Redis setup for the Log Analyzer project.

## Role

Redis is used for temporary and fast-access data.

Possible usages:

- cache
- ingestion status
- realtime counters
- rate limiting
- dashboard summary cache

Redis is not used as the primary persistent database.

## Local access

| Usage | Address |
|---|---|
| Host machine | `localhost:16379` |
| Docker network | `redis:6379` |
| Redis Commander | `http://localhost:18081` |

## Notes

- Redis runs through `local/docker-compose.yml`.
- Local data is stored in the `redis_data` Docker volume.
- Temporary/cache keys should use TTL where possible.
- Raw log documents should not be stored in Redis.