#!/bin/bash

# Docker Image Security Scanner for CI/CD Pipeline
# Scans Docker images for vulnerabilities using Trivy

# Configuration
TRIVY_VERSION="0.58.1"  # Latest stable version as of August 2025
SEVERITY_LEVELS="CRITICAL"  # Match your current setup
CACHE_DIR="${WORKSPACE:-/tmp/.trivy-cache}"

# Function to get built image name
get_docker_image_name() {
    # Method 1: Use environment variables from your CI/CD pipeline
    if [[ -n "${REGISTRY_HOSTNAME:-}" && -n "${GCR_GKE_PROJECT:-}" && -n "${REPOSITORY:-}" && -n "${IMAGE:-}" ]]; then
        local commit_sha="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo 'latest')}"
        echo "$REGISTRY_HOSTNAME/$GCR_GKE_PROJECT/$REPOSITORY/$IMAGE:$commit_sha"
        return 0
    fi
    
    # Method 2: Use provided argument
    if [[ $# -gt 0 ]]; then
        echo "$1"
        return 0
    fi
    
    # Method 3: Try to get the last built image
    local last_image=$(docker images --format "{{.Repository}}:{{.Tag}}" | head -1)
    if [[ -n "$last_image" && "$last_image" != "<none>:<none>" ]]; then
        echo "$last_image"
        return 0
    fi
    
    # Method 4: Fallback - extract from dockerfile if it exists
    local dockerfile_path="${DOCKERFILE:-dockerfile}"
    if [[ -f "$dockerfile_path" ]]; then
        # Try to extract from dockerfile (your original method, but with error handling)
        local image_name=$(awk 'NR==1 {print $2}' "$dockerfile_path" 2>/dev/null || echo "")
        if [[ -n "$image_name" ]]; then
            echo "$image_name"
            return 0
        fi
    fi
    
    echo ""
    return 1
}

# Main scanning function (updated for latest Trivy version)
scan_docker_image() {
    local docker_image_name=$1
    
    echo "Scanning image: $docker_image_name"
    
    # Ensure cache directory exists and handle empty WORKSPACE
    if [[ -z "$CACHE_DIR" || "$CACHE_DIR" == "/:" ]]; then
        CACHE_DIR="/tmp/.trivy-cache"
    fi
    mkdir -p "$CACHE_DIR"
    
    # Run Trivy scan with updated command structure for latest version
    docker run --rm \
        -v "$CACHE_DIR:/root/.cache/" \
        "aquasec/trivy:$TRIVY_VERSION" \
        image \
        --exit-code 1 \
        --severity "$SEVERITY_LEVELS" \
        --quiet \
        "$docker_image_name"
}

# Main execution (simplified to match your current workflow)
main() {
    # Get the Docker image name
    local docker_image_name=""
    
    # First, try to get from command line argument
    if [[ $# -gt 0 ]]; then
        docker_image_name="$1"
    else
        # Try to determine the image name automatically
        docker_image_name=$(get_docker_image_name)
        if [[ -z "$docker_image_name" ]]; then
            echo "Error: Could not determine Docker image name"
            echo "Please provide the image name as an argument:"
            echo "Usage: $0 <image_name>"
            echo ""
            echo "Or set these environment variables in your CI/CD:"
            echo "  REGISTRY_HOSTNAME, GCR_GKE_PROJECT, REPOSITORY, IMAGE"
            exit 1
        fi
    fi
    
    echo "$docker_image_name"
    
    # Run the scan and capture exit code
    local exit_code=0
    scan_docker_image "$docker_image_name" || exit_code=$?
    
    echo "Exit Code : $exit_code"
    
    # Check scan results (matching your original logic)
    if [[ "$exit_code" == 1 ]]; then
        echo "Image scanning failed. Vulnerabilities found, not failing build"
        echo "---------------------------------------------------------------"
        echo "Please fix the vulnerabilities"
        exit 1
    else
        echo "Image scanning passed. No CRITICAL vulnerabilities found"
    fi
}

# Run the main function with all arguments
main "$@"
