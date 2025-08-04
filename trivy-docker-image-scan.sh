#!/bin/bash
#
# Trivy Docker Image Scanner with Environment-based Logic
# - Fails if environment is 'stage' (to catch vulnerabilities in staging)
# - Passes if environment is 'prod' (allows deployment to production)
#

# Configuration
TRIVY_VERSION="0.58.1"
SEVERITY_LEVELS="HIGH,CRITICAL"
CACHE_DIR="${WORKSPACE:-/tmp/.trivy-cache}"
VALUES_YAML_PATH="${VALUES_YAML_PATH:-values.yaml}"

# Function to get environment from values.yaml
get_environment() {
    local values_file="$1"
    
    if [[ ! -f "$values_file" ]]; then
        echo "Error: values.yaml file not found at: $values_file" >&2
        return 1
    fi
    
    # Check if yq is available
    if ! command -v yq &> /dev/null; then
        echo "Error: yq is not installed. Please install yq to parse YAML files." >&2
        echo "Install with: pip install yq  or  brew install yq  or  apt-get install yq" >&2
        return 1
    fi
    
    local environment=$(yq e '.environment.name' "$values_file" 2>/dev/null)
    
    if [[ -z "$environment" || "$environment" == "null" ]]; then
        echo "Error: Could not extract environment.name from $values_file" >&2
        echo "Please ensure the YAML structure contains: environment.name" >&2
        return 1
    fi
    
    echo "$environment"
    return 0
}

# Function to get built image name
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
    
    echo "Scanning image: $docker_image_name"
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
    
    # Get environment from values.yaml
    echo "Reading environment from: $VALUES_YAML_PATH"
    local environment
    environment=$(get_environment "$VALUES_YAML_PATH")
    local env_exit_code=$?
    
    if [[ $env_exit_code -ne 0 ]]; then
        echo "Failed to get environment from values.yaml"
        exit 1
    fi
    
    echo "Environment detected: $environment"
    
    # Get Docker image name
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
    
    echo "Scanning Docker image: $docker_image_name"
    
    # Run the scan
    local scan_exit_code=0
    scan_docker_image "$docker_image_name" || scan_exit_code=$?
    
    echo "Scan exit code: $scan_exit_code"
    
    # Environment-based logic
    case "$environment" in
        "stage")
            echo "=== STAGE ENVIRONMENT ==="
            if [[ "$scan_exit_code" == 1 ]]; then
                echo "❌ FAIL: Vulnerabilities found in STAGE environment!"
                echo "HIGH/CRITICAL vulnerabilities detected. Blocking deployment to prevent issues."
                echo "Please fix vulnerabilities before proceeding."
                exit 1
            else
                echo "✅ PASS: No HIGH/CRITICAL vulnerabilities found in STAGE."
                echo "Image is clean for stage deployment."
                exit 0
            fi
            ;;
        "prod")
            echo "=== PRODUCTION ENVIRONMENT ==="
            if [[ "$scan_exit_code" == 1 ]]; then
                echo "⚠️  WARNING: Vulnerabilities found in PROD environment, but allowing deployment."
                echo "HIGH/CRITICAL vulnerabilities detected, but production deployment is proceeding."
                echo "Consider scheduling vulnerability remediation."
            else
                echo "✅ PASS: No HIGH/CRITICAL vulnerabilities found in PROD."
            fi
            echo "Production deployment allowed."
            exit 0
            ;;
        *)
            echo "=== UNKNOWN ENVIRONMENT: $environment ==="
            echo "Environment '$environment' is not recognized (expected 'stage' or 'prod')"
            if [[ "$scan_exit_code" == 1 ]]; then
                echo "❌ FAIL: Vulnerabilities found and environment is unknown."
                echo "Defaulting to strict mode - blocking deployment."
                exit 1
            else
                echo "✅ PASS: No vulnerabilities found."
                exit 0
            fi
            ;;
    esac
}

# Handle script arguments
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

#!/bin/bash
#dockerImageName=$(awk 'NR==1 {print $2}' Dockerfile)
#echo $dockerImageName

#docker run --rm -v $WORKSPACE:/root/.cache/ aquasec/trivy:0.58.1 -q image --exit-code 1 --severity CRITICAL --light $dockerImageName

## Trivy scan result processing
#exit_code=$?
#echo "Exit Code : $exit_code"

# Check scan results
#if [[ "${exit_code}" == 1 ]]; then
#    echo "Image scanning failed. Vulnerabilities found, not failing build"
#    echo "---------------------------------------------------------------"
 #   echo "Please fix the vulnerabilities"
  #  exit 0;
#else
 #   echo "Image scanning passed. No CRITICAL vulnerabilities found"
#fi;
