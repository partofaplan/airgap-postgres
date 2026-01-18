# Air-gapped PostgreSQL Helm Chart

A Helm chart for deploying PostgreSQL 18 in high-availability mode for air-gapped Kubernetes environments. All images are sourced from a single registry (`docker.io/partofaplan`).

## Features

- **PostgreSQL 18** with streaming replication
- **High Availability** with HAProxy load balancing
- **Automatic hourly backups** via Kubernetes CronJob
- **Database recovery** automation scripts
- **Single registry** - all images from `docker.io/partofaplan`

## Architecture

```
                    ┌─────────────────────────────────────┐
                    │           HAProxy (x2)              │
                    │  Port 5432: Primary (read-write)    │
                    │  Port 5433: Read-only (all nodes)   │
                    └─────────────────────────────────────┘
                                     │
            ┌────────────────────────┼────────────────────────┐
            │                        │                        │
            ▼                        ▼                        ▼
    ┌───────────────┐      ┌───────────────┐      ┌───────────────┐
    │  PostgreSQL   │      │  PostgreSQL   │      │  PostgreSQL   │
    │   Primary     │─────▶│   Replica 1   │      │   Replica 2   │
    │   (pod-0)     │      │   (pod-1)     │      │   (pod-2)     │
    └───────────────┘      └───────────────┘      └───────────────┘
            │
            ▼
    ┌───────────────┐
    │  Backup       │
    │  CronJob      │
    └───────────────┘
```

## Prerequisites

- Kubernetes 1.24+
- Helm 3.x
- `kubectl` configured with cluster access
- Storage class that supports `ReadWriteOnce` PVCs

## Quick Start

### 1. Build and Push Images (if not already in registry)

```bash
# Login to Docker Hub
docker login

# Build and push images
./scripts/build-and-push-images.sh --push
```

### 2. Install the Helm Chart

```bash
# Create namespace
kubectl create namespace postgres

# Install with generated passwords
helm install airgap-postgres ./helm/postgres \
  --namespace postgres \
  --set postgresql.password="your-app-password" \
  --set postgresql.postgresPassword="your-admin-password" \
  --set postgresql.replication.password="your-replication-password"
```

### 3. Verify Installation

```bash
# Run the test suite
./scripts/test-deployment.sh -n postgres -r airgap-postgres

# Or manually check
kubectl get pods -n postgres
kubectl get svc -n postgres
```

## Configuration

### Key Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `global.imageRegistry` | Docker registry for all images | `docker.io/partofaplan` |
| `postgresql.replicaCount` | Number of PostgreSQL replicas | `3` |
| `postgresql.database` | Default database name | `appdb` |
| `postgresql.username` | Application username | `appuser` |
| `postgresql.password` | Application user password | `""` (required) |
| `postgresql.postgresPassword` | Superuser password | `""` (required) |
| `postgresql.persistence.size` | Storage size per replica | `10Gi` |
| `haproxy.enabled` | Enable HAProxy load balancer | `true` |
| `haproxy.replicaCount` | HAProxy replicas | `2` |
| `backup.enabled` | Enable automated backups | `true` |
| `backup.schedule` | Backup cron schedule | `0 * * * *` (hourly) |
| `backup.retentionDays` | Days to keep backups | `7` |

### Example values.yaml Override

```yaml
global:
  imageRegistry: "docker.io/partofaplan"

postgresql:
  replicaCount: 3
  database: myapp
  username: myuser
  password: "secure-password"
  postgresPassword: "admin-password"
  replication:
    password: "replication-password"
  persistence:
    size: 50Gi
    storageClass: "fast-ssd"

haproxy:
  replicaCount: 2

backup:
  schedule: "0 */6 * * *"  # Every 6 hours
  retentionDays: 30
  persistence:
    size: 100Gi
```

## Connecting to the Database

### Via HAProxy (Recommended)

```bash
# Read-write connection (primary only)
psql -h airgap-postgres-haproxy -p 5432 -U appuser -d appdb

# Read-only connection (load-balanced across all replicas)
psql -h airgap-postgres-haproxy -p 5433 -U appuser -d appdb
```

### Direct Connection

```bash
# Connect to primary
psql -h airgap-postgres-primary -p 5432 -U appuser -d appdb
```

### Port Forwarding

```bash
# Forward HAProxy port
kubectl port-forward svc/airgap-postgres-haproxy 5432:5432 -n postgres

# Connect locally
psql -h localhost -p 5432 -U appuser -d appdb
```

## Backup & Recovery

### View Backup Status

```bash
# Check CronJob status
kubectl get cronjob -n postgres

# View recent backup jobs
kubectl get jobs -n postgres -l app.kubernetes.io/component=backup

# View backup logs
kubectl logs job/airgap-postgres-backup-<timestamp> -n postgres
```

### List Available Backups

```bash
./scripts/recover-database.sh -n postgres -r airgap-postgres --list
```

### Manual Backup

```bash
# Trigger an immediate backup
kubectl create job --from=cronjob/airgap-postgres-backup manual-backup-$(date +%s) -n postgres
```

### Database Recovery

```bash
# Recover from latest backup
./scripts/recover-database.sh -n postgres -r airgap-postgres

# Recover from specific backup
./scripts/recover-database.sh -n postgres -r airgap-postgres -b backup_20240115_120000.sql.gz
```

## Monitoring

### HAProxy Stats

```bash
# Port forward to stats endpoint
kubectl port-forward svc/airgap-postgres-haproxy 8404:8404 -n postgres

# Open in browser: http://localhost:8404/stats
```

### PostgreSQL Replication Status

```bash
# Check replication status on primary
kubectl exec airgap-postgres-0 -n postgres -c postgresql -- \
  psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Check replica lag
kubectl exec airgap-postgres-1 -n postgres -c postgresql -- \
  psql -U postgres -c "SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;"
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl describe pod airgap-postgres-0 -n postgres

# Check events
kubectl get events -n postgres --sort-by='.lastTimestamp'

# Check logs
kubectl logs airgap-postgres-0 -n postgres -c postgresql
```

### Replication Issues

```bash
# Check if primary is accepting connections
kubectl exec airgap-postgres-0 -n postgres -c postgresql -- pg_isready

# Check replication slots
kubectl exec airgap-postgres-0 -n postgres -c postgresql -- \
  psql -U postgres -c "SELECT * FROM pg_replication_slots;"
```

### HAProxy Not Routing

```bash
# Check HAProxy logs
kubectl logs -l app.kubernetes.io/component=haproxy -n postgres

# Verify health check endpoints
kubectl exec airgap-postgres-0 -n postgres -c postgresql -- \
  curl -s http://localhost:8008/primary
```

## Uninstallation

```bash
# Uninstall the release
helm uninstall airgap-postgres -n postgres

# Delete PVCs (WARNING: deletes all data!)
kubectl delete pvc -l app.kubernetes.io/instance=airgap-postgres -n postgres

# Delete namespace
kubectl delete namespace postgres
```

## Images

All images are pulled from `docker.io/partofaplan`:

| Image | Tag | Description |
|-------|-----|-------------|
| `partofaplan/postgres` | `18` | PostgreSQL 18 with backup tools |
| `partofaplan/haproxy` | `2.9` | HAProxy for load balancing |

To build and push your own images:

```bash
./scripts/build-and-push-images.sh --push -r partofaplan
```
