#!/bin/bash
#
# Build and Push Docker Images to DockerHub
# This script builds the PostgreSQL and HAProxy images and pushes them to the specified registry
#
# Usage:
#   ./build-and-push-images.sh [OPTIONS]
#
# Options:
#   -r, --registry    Docker registry (default: partofaplan)
#   -t, --tag         Image tag (default: latest)
#   -p, --push        Push images after building
#   -h, --help        Show this help message
#

set -e

# Default values
REGISTRY="partofaplan"
TAG="latest"
PUSH=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    cat << EOF
Build and Push Docker Images

Usage: $0 [OPTIONS]

Options:
    -r, --registry    Docker registry (default: partofaplan)
    -t, --tag         Image tag (default: latest)
    -p, --push        Push images after building
    -h, --help        Show this help message

Examples:
    # Build images only
    $0

    # Build and push with default settings
    $0 --push

    # Build and push with custom tag
    $0 --push -t v1.0.0
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--registry)
            REGISTRY="$2"
            shift 2
            ;;
        -t|--tag)
            TAG="$2"
            shift 2
            ;;
        -p|--push)
            PUSH=true
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

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Building Docker Images${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo "Registry: ${REGISTRY}"
echo "Tag: ${TAG}"
echo "Push: ${PUSH}"
echo ""

# Check if docker is available
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: docker is not installed${NC}"
    exit 1
fi

# Build PostgreSQL image
echo -e "${YELLOW}Building PostgreSQL image...${NC}"
POSTGRES_IMAGE="${REGISTRY}/postgres:${TAG}"

docker build \
    -t "${POSTGRES_IMAGE}" \
    -t "${REGISTRY}/postgres:18" \
    -f "${PROJECT_DIR}/docker/postgres/Dockerfile" \
    "${PROJECT_DIR}/docker/postgres"

echo -e "${GREEN}PostgreSQL image built: ${POSTGRES_IMAGE}${NC}"
echo ""

# Build HAProxy image
echo -e "${YELLOW}Building HAProxy image...${NC}"
HAPROXY_IMAGE="${REGISTRY}/haproxy:${TAG}"

docker build \
    -t "${HAPROXY_IMAGE}" \
    -t "${REGISTRY}/haproxy:2.9" \
    -f "${PROJECT_DIR}/docker/haproxy/Dockerfile" \
    "${PROJECT_DIR}/docker/haproxy"

echo -e "${GREEN}HAProxy image built: ${HAPROXY_IMAGE}${NC}"
echo ""

# Push images if requested
if [ "$PUSH" = true ]; then
    echo -e "${YELLOW}Pushing images to registry...${NC}"
    echo ""

    # Check if logged in to Docker Hub
    if ! docker info 2>/dev/null | grep -q "Username"; then
        echo -e "${YELLOW}You may need to login to Docker Hub first:${NC}"
        echo "  docker login"
        echo ""
    fi

    # Push PostgreSQL images
    echo "Pushing PostgreSQL image..."
    docker push "${POSTGRES_IMAGE}"
    docker push "${REGISTRY}/postgres:18"

    # Push HAProxy images
    echo "Pushing HAProxy image..."
    docker push "${HAPROXY_IMAGE}"
    docker push "${REGISTRY}/haproxy:2.9"

    echo ""
    echo -e "${GREEN}All images pushed successfully!${NC}"
else
    echo -e "${YELLOW}Images built but not pushed. Use --push to push images.${NC}"
fi

echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Image Summary${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo "PostgreSQL images:"
echo "  - ${REGISTRY}/postgres:${TAG}"
echo "  - ${REGISTRY}/postgres:18"
echo ""
echo "HAProxy images:"
echo "  - ${REGISTRY}/haproxy:${TAG}"
echo "  - ${REGISTRY}/haproxy:2.9"
echo ""
echo "To use in Helm chart, ensure values.yaml has:"
echo "  global:"
echo "    imageRegistry: \"docker.io/${REGISTRY}\""
