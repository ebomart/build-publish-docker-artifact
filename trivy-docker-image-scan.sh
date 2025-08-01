#!/bin/bash

# Test version - scanning for HIGH and CRITICAL vulnerabilities
TRIVY_VERSION="0.58.1"
SEVERITY_LEVELS="HIGH,CRITICAL"  # Changed to include HIGH
CACHE_DIR="${WORKSPACE:-/tmp/.trivy-cache}"

# Function to get built image name (same as original)
get_docker_image_name() {
    if [[ -n "${REGISTRY_HOSTNAME:-}" && -n "${GCR_GKE_PROJECT:-}" && -n "${REPOSITORY:-}" && -n "${IMAGE:-}" ]]; then
        local commit_sha="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo 'latest')}"
        echo "$REGISTRY_HOSTNAME/$GCR_GKE_PROJECT/$REPOSITORY/$IMAGE:$commit_sha"
        return 0
    fi
    
    if [[ $# -gt 0 ]]; then
        echo "$1"
        return 0
    fi
    
    local last_image=$(docker images --format "{{.Repository}}:{{.Tag}}" | head -1)
    if [[ -n "$last_image" && "$last_image" != "<none>:<none>" ]]; then
        echo "$last_image"
        return 0
    fi
    
    echo ""
    return 1
}

# Scanning function
scan_docker_image() {
    local docker_image_name=$1
    
    echo "TEST SCAN - Scanning image: $docker_image_name"
    echo "Severity levels: $SEVERITY_LEVELS"
    
    if [[ -z "$CACHE_DIR" || "$CACHE_DIR" == "/:" ]]; then
        CACHE_DIR="/tmp/.trivy-cache"
    fi
    mkdir -p "$CACHE_DIR"
    
    docker run --rm \
        -v "$CACHE_DIR:/root/.cache/" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "aquasec/trivy:$TRIVY_VERSION" \
        image \
        --exit-code 1 \
        --severity "$SEVERITY_LEVELS" \
        --quiet \
        "$docker_image_name"
}

# Main execution
main() {
    local docker_image_name=""
    
    if [[ $# -gt 0 ]]; then
        docker_image_name="$1"
    else
        docker_image_name=$(get_docker_image_name)
        if [[ -z "$docker_image_name" ]]; then
            echo "Error: Could not determine Docker image name"
            echo "Usage: $0 <image_name>"
            exit 1
        fi
    fi
    
    echo "$docker_image_name"
    
    local exit_code=0
    scan_docker_image "$docker_image_name" || exit_code=$?
    
    echo "Exit Code : $exit_code"
    
    if [[ "$exit_code" == 1 ]]; then
        echo "TEST: Image scanning found HIGH/CRITICAL vulnerabilities!"
        echo "---------------------------------------------------------------"
        echo "Vulnerabilities detected (this is what we wanted for testing)"
        exit 1
    else
        echo "TEST: No HIGH/CRITICAL vulnerabilities found"
    fi
}

main "$@"
