#!/bin/bash
#
# PostgreSQL Deployment Test Script
# Tests the Helm deployment and validates all components are working correctly
#
# Usage:
#   ./test-deployment.sh [OPTIONS]
#
# Options:
#   -n, --namespace    Kubernetes namespace (default: default)
#   -r, --release      Helm release name (default: airgap-postgres)
#   -h, --help         Show this help message
#

set -e

# Default values
NAMESPACE="default"
RELEASE_NAME="airgap-postgres"
TESTS_PASSED=0
TESTS_FAILED=0

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    cat << EOF
PostgreSQL Deployment Test Script

Usage: $0 [OPTIONS]

Options:
    -n, --namespace     Kubernetes namespace (default: default)
    -r, --release       Helm release name (default: airgap-postgres)
    -h, --help          Show this help message

Examples:
    $0 -n postgres-ns -r my-postgres
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

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}PostgreSQL Deployment Test Suite${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""
echo "Namespace: ${NAMESPACE}"
echo "Release:   ${RELEASE_NAME}"
echo ""

# Test function
run_test() {
    local test_name="$1"
    local test_cmd="$2"

    echo -n "Testing: ${test_name}... "

    if eval "${test_cmd}" > /dev/null 2>&1; then
        echo -e "${GREEN}PASSED${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAILED${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"
echo ""

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi

# Test 1: Check if namespace exists
echo -e "${YELLOW}Running tests...${NC}"
echo ""

run_test "Namespace exists" "kubectl get namespace ${NAMESPACE}"

# Test 2: Check StatefulSet
run_test "StatefulSet exists" "kubectl get statefulset ${RELEASE_NAME} -n ${NAMESPACE}"

# Test 3: Check StatefulSet replicas are ready
run_test "StatefulSet replicas ready" "
    READY=\$(kubectl get statefulset ${RELEASE_NAME} -n ${NAMESPACE} -o jsonpath='{.status.readyReplicas}')
    DESIRED=\$(kubectl get statefulset ${RELEASE_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.replicas}')
    [ \"\$READY\" = \"\$DESIRED\" ] && [ -n \"\$READY\" ]
"

# Test 4: Check all pods are running
run_test "All PostgreSQL pods running" "
    RUNNING=\$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=airgap-postgres,app.kubernetes.io/component=postgresql --no-headers | grep -c Running || true)
    DESIRED=\$(kubectl get statefulset ${RELEASE_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.replicas}')
    [ \"\$RUNNING\" = \"\$DESIRED\" ]
"

# Test 5: Check headless service exists
run_test "Headless service exists" "kubectl get service ${RELEASE_NAME}-headless -n ${NAMESPACE}"

# Test 6: Check primary service exists
run_test "Primary service exists" "kubectl get service ${RELEASE_NAME}-primary -n ${NAMESPACE}"

# Test 7: Check read service exists
run_test "Read service exists" "kubectl get service ${RELEASE_NAME}-read -n ${NAMESPACE}"

# Test 8: Check HAProxy deployment
run_test "HAProxy deployment exists" "kubectl get deployment ${RELEASE_NAME}-haproxy -n ${NAMESPACE}"

# Test 9: Check HAProxy replicas ready
run_test "HAProxy replicas ready" "
    READY=\$(kubectl get deployment ${RELEASE_NAME}-haproxy -n ${NAMESPACE} -o jsonpath='{.status.readyReplicas}')
    DESIRED=\$(kubectl get deployment ${RELEASE_NAME}-haproxy -n ${NAMESPACE} -o jsonpath='{.spec.replicas}')
    [ \"\$READY\" = \"\$DESIRED\" ] && [ -n \"\$READY\" ]
"

# Test 10: Check HAProxy service exists
run_test "HAProxy service exists" "kubectl get service ${RELEASE_NAME}-haproxy -n ${NAMESPACE}"

# Test 11: Check backup CronJob exists
run_test "Backup CronJob exists" "kubectl get cronjob ${RELEASE_NAME}-backup -n ${NAMESPACE}"

# Test 12: Check secrets exist
run_test "Credentials secret exists" "kubectl get secret ${RELEASE_NAME}-credentials -n ${NAMESPACE}"

# Test 13: Check ConfigMaps exist
run_test "PostgreSQL ConfigMap exists" "kubectl get configmap ${RELEASE_NAME}-config -n ${NAMESPACE}"
run_test "HAProxy ConfigMap exists" "kubectl get configmap ${RELEASE_NAME}-haproxy -n ${NAMESPACE}"

# Test 14: Check PVCs exist
run_test "PostgreSQL data PVC exists" "kubectl get pvc data-${RELEASE_NAME}-0 -n ${NAMESPACE}"
run_test "Backup PVC exists" "kubectl get pvc ${RELEASE_NAME}-backup -n ${NAMESPACE}"

# Test 15: Database connectivity test
echo ""
echo -e "${YELLOW}Running database connectivity tests...${NC}"
echo ""

run_test "Primary pod can connect to PostgreSQL" "
    kubectl exec ${RELEASE_NAME}-0 -n ${NAMESPACE} -c postgresql -- \
        pg_isready -U postgres -d postgres
"

# Test 16: Check replication status (if more than 1 replica)
REPLICA_COUNT=$(kubectl get statefulset ${RELEASE_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
if [ "$REPLICA_COUNT" -gt 1 ]; then
    run_test "Replication is working" "
        REPLICATING=\$(kubectl exec ${RELEASE_NAME}-0 -n ${NAMESPACE} -c postgresql -- \
            psql -U postgres -t -c \"SELECT count(*) FROM pg_stat_replication;\" 2>/dev/null | tr -d ' ')
        [ \"\$REPLICATING\" -ge 1 ]
    "
fi

# Test 17: Check if primary can be determined
run_test "Primary node is identifiable" "
    IS_PRIMARY=\$(kubectl exec ${RELEASE_NAME}-0 -n ${NAMESPACE} -c postgresql -- \
        psql -U postgres -t -c \"SELECT NOT pg_is_in_recovery();\" 2>/dev/null | tr -d ' ')
    [ \"\$IS_PRIMARY\" = \"t\" ]
"

# Test 18: Check health check sidecar
run_test "Health check sidecar responds" "
    kubectl exec ${RELEASE_NAME}-0 -n ${NAMESPACE} -c postgresql -- \
        bash -c 'echo | nc -w 2 localhost 8008' 2>/dev/null | grep -q 'HTTP'
" || true

# Test 19: Check HAProxy stats endpoint
run_test "HAProxy stats endpoint accessible" "
    POD=\$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/component=haproxy -o jsonpath='{.items[0].metadata.name}')
    kubectl exec \$POD -n ${NAMESPACE} -- wget -q -O - http://localhost:8404/stats > /dev/null
"

# Test 20: Verify all images are from the correct registry
echo ""
echo -e "${YELLOW}Checking image sources...${NC}"
echo ""

IMAGES=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/instance=${RELEASE_NAME} -o jsonpath='{.items[*].spec.containers[*].image}' 2>/dev/null)
REGISTRY="docker.io/partofaplan"

ALL_FROM_REGISTRY=true
for IMAGE in $IMAGES; do
    if [[ "$IMAGE" != ${REGISTRY}* ]]; then
        echo -e "${RED}Image not from expected registry: ${IMAGE}${NC}"
        ALL_FROM_REGISTRY=false
    fi
done

if [ "$ALL_FROM_REGISTRY" = true ] && [ -n "$IMAGES" ]; then
    echo -e "All images from ${REGISTRY}: ${GREEN}PASSED${NC}"
    ((TESTS_PASSED++))
else
    echo -e "All images from ${REGISTRY}: ${RED}FAILED${NC}"
    ((TESTS_FAILED++))
fi

# Summary
echo ""
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""
echo -e "Tests Passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Tests Failed: ${RED}${TESTS_FAILED}${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed! Deployment is healthy.${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Please investigate the issues above.${NC}"
    echo ""
    echo "Helpful commands for debugging:"
    echo "  kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/instance=${RELEASE_NAME}"
    echo "  kubectl describe pod ${RELEASE_NAME}-0 -n ${NAMESPACE}"
    echo "  kubectl logs ${RELEASE_NAME}-0 -n ${NAMESPACE} -c postgresql"
    echo "  kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp'"
    exit 1
fi
