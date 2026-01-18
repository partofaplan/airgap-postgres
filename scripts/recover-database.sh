#!/bin/bash
#
# PostgreSQL Database Recovery Script
# This script initiates a database recovery from backup in Kubernetes
#
# Usage:
#   ./recover-database.sh [OPTIONS]
#
# Options:
#   -n, --namespace    Kubernetes namespace (default: default)
#   -r, --release      Helm release name (default: airgap-postgres)
#   -b, --backup-file  Specific backup file to restore (default: latest.sql.gz)
#   -l, --list         List available backups
#   -h, --help         Show this help message
#

set -e

# Default values
NAMESPACE="default"
RELEASE_NAME="airgap-postgres"
BACKUP_FILE="latest.sql.gz"
LIST_BACKUPS=false

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    cat << EOF
PostgreSQL Database Recovery Script

Usage: $0 [OPTIONS]

Options:
    -n, --namespace     Kubernetes namespace (default: default)
    -r, --release       Helm release name (default: airgap-postgres)
    -b, --backup-file   Specific backup file to restore (default: latest.sql.gz)
    -l, --list          List available backups
    -h, --help          Show this help message

Examples:
    # Recover from latest backup
    $0 -n postgres-ns -r my-postgres

    # List available backups
    $0 -n postgres-ns -r my-postgres --list

    # Recover from specific backup
    $0 -n postgres-ns -r my-postgres -b backup_20240115_120000.sql.gz
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -r|--release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        -b|--backup-file)
            BACKUP_FILE="$2"
            shift 2
            ;;
        -l|--list)
            LIST_BACKUPS=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
    exit 1
fi

# Check cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi

# Get the backup PVC name
BACKUP_PVC="${RELEASE_NAME}-backup"

# List backups if requested
if [ "$LIST_BACKUPS" = true ]; then
    echo -e "${GREEN}Available backups in ${NAMESPACE}/${BACKUP_PVC}:${NC}"
    echo ""

    # Create a temporary pod to list backups
    kubectl run backup-list-temp \
        --namespace="${NAMESPACE}" \
        --image="docker.io/partofaplan/postgres:18" \
        --restart=Never \
        --rm \
        -it \
        --overrides='{
            "spec": {
                "containers": [{
                    "name": "backup-list-temp",
                    "image": "docker.io/partofaplan/postgres:18",
                    "command": ["ls", "-lah", "/backups/"],
                    "volumeMounts": [{
                        "name": "backup-storage",
                        "mountPath": "/backups"
                    }]
                }],
                "volumes": [{
                    "name": "backup-storage",
                    "persistentVolumeClaim": {
                        "claimName": "'${BACKUP_PVC}'"
                    }
                }]
            }
        }' 2>/dev/null || echo -e "${YELLOW}Note: Could not list backups. Check if the backup PVC exists.${NC}"

    exit 0
fi

echo -e "${YELLOW}======================================${NC}"
echo -e "${YELLOW}PostgreSQL Database Recovery${NC}"
echo -e "${YELLOW}======================================${NC}"
echo ""
echo "Namespace:    ${NAMESPACE}"
echo "Release:      ${RELEASE_NAME}"
echo "Backup file:  ${BACKUP_FILE}"
echo ""

# Confirmation
echo -e "${RED}WARNING: This will restore the database from backup.${NC}"
echo -e "${RED}All current data will be OVERWRITTEN.${NC}"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Recovery cancelled."
    exit 0
fi

echo ""
echo -e "${GREEN}Starting recovery...${NC}"

# Check if the recovery job already exists and delete it
if kubectl get job "${RELEASE_NAME}-recovery" -n "${NAMESPACE}" &> /dev/null; then
    echo "Deleting existing recovery job..."
    kubectl delete job "${RELEASE_NAME}-recovery" -n "${NAMESPACE}" --ignore-not-found
    sleep 2
fi

# Patch the job to unsuspend and set the backup file
echo "Creating recovery job..."

# Create a modified job from the suspended template
kubectl get job "${RELEASE_NAME}-recovery" -n "${NAMESPACE}" -o yaml 2>/dev/null | \
    sed 's/suspend: true/suspend: false/' | \
    kubectl apply -f - 2>/dev/null || \
    # If the job doesn't exist as a template, create it from the helm template
    kubectl patch job "${RELEASE_NAME}-recovery" -n "${NAMESPACE}" \
        --type='json' \
        -p='[{"op": "replace", "path": "/spec/suspend", "value": false}]' 2>/dev/null || \
    {
        echo -e "${YELLOW}Creating new recovery job...${NC}"
        cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${RELEASE_NAME}-recovery-$(date +%s)
  namespace: ${NAMESPACE}
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 86400
  template:
    spec:
      restartPolicy: Never
      securityContext:
        runAsNonRoot: true
        runAsUser: 999
        fsGroup: 999
      containers:
        - name: recovery
          image: docker.io/partofaplan/postgres:18
          command:
            - /bin/bash
            - -c
            - |
              set -e
              echo "Starting database recovery..."
              BACKUP_DIR="/backups"
              DB_HOST="${RELEASE_NAME}-primary"
              DB_PORT="5432"
              RESTORE_FILE="\${BACKUP_DIR}/${BACKUP_FILE}"

              if [ ! -f "\${RESTORE_FILE}" ]; then
                echo "ERROR: Backup file not found: \${RESTORE_FILE}"
                ls -la \${BACKUP_DIR}/ || true
                exit 1
              fi

              until pg_isready -h \${DB_HOST} -p \${DB_PORT} -U postgres; do
                echo "Waiting for database..."
                sleep 5
              done

              echo "Restoring from \${RESTORE_FILE}..."
              gunzip -c \${RESTORE_FILE} | psql -h \${DB_HOST} -p \${DB_PORT} -U postgres -d postgres
              echo "Recovery completed!"
          env:
            - name: PGPASSWORD
              valueFrom:
                secretKeyRef:
                  name: ${RELEASE_NAME}-credentials
                  key: postgresql-postgres-password
          volumeMounts:
            - name: backup-storage
              mountPath: /backups
              readOnly: true
      volumes:
        - name: backup-storage
          persistentVolumeClaim:
            claimName: ${BACKUP_PVC}
EOF
    }

# Get the job name (might have timestamp suffix)
JOB_NAME=$(kubectl get jobs -n "${NAMESPACE}" -l "app.kubernetes.io/component=recovery" -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null || echo "${RELEASE_NAME}-recovery")

echo ""
echo -e "${GREEN}Recovery job created: ${JOB_NAME}${NC}"
echo ""
echo "Watching job progress..."
echo ""

# Watch the job logs
kubectl logs -f "job/${JOB_NAME}" -n "${NAMESPACE}" 2>/dev/null || \
    kubectl wait --for=condition=complete "job/${JOB_NAME}" -n "${NAMESPACE}" --timeout=600s

# Check job status
JOB_STATUS=$(kubectl get job "${JOB_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.succeeded}' 2>/dev/null)

echo ""
if [ "$JOB_STATUS" = "1" ]; then
    echo -e "${GREEN}======================================${NC}"
    echo -e "${GREEN}Recovery completed successfully!${NC}"
    echo -e "${GREEN}======================================${NC}"
else
    echo -e "${RED}======================================${NC}"
    echo -e "${RED}Recovery may have failed. Check logs:${NC}"
    echo -e "${RED}kubectl logs job/${JOB_NAME} -n ${NAMESPACE}${NC}"
    echo -e "${RED}======================================${NC}"
    exit 1
fi
