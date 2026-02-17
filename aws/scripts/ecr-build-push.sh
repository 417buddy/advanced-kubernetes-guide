#!/bin/bash
set -e

######################################################################
# ECR Image Build and Push Script
# Account ID: 564268554451
# Region: us-east-1
######################################################################

AWS_ACCOUNT_ID="564268554451"
AWS_REGION="us-east-1"
ECR_REGISTRY="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_colored() {
    color=$1
    shift
    echo -e "${color}$@${NC}"
}

section() {
    echo_colored $BLUE "========================================"
    echo_colored $BLUE "  $1"
    echo_colored $BLUE "========================================"
}

step() {
    echo_colored $GREEN ">>> $1"
}

success() {
    echo_colored $GREEN "✅ $1"
}

error_exit() {
    echo_colored $RED "❌ ERROR: $1"
    exit 1
}

# Check prerequisites
section "PREREQUISITES CHECK"

command -v aws >/dev/null 2>&1 || error_exit "AWS CLI is not installed"
command -v docker >/dev/null 2>&1 || error_exit "Docker is not installed"

# Verify AWS credentials
aws sts get-caller-identity --query Account --output text | grep -q "$AWS_ACCOUNT_ID" || \
  error_exit "AWS Account ID does not match. Expected: $AWS_ACCOUNT_ID"

step "AWS Account verified: $AWS_ACCOUNT_ID"
step "ECR Registry: $ECR_REGISTRY"

# Login to ECR
step "Logging in to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

success "ECR login successful"

# Create ECR repositories
section "CREATING ECR REPOSITORIES"

REPOS=(
  "ecommerce/frontend"
  "ecommerce/product-service"
  "ecommerce/order-service"
  "ecommerce/auth-service"
  "ecommerce/api-gateway"
)

for repo in "${REPOS[@]}"; do
  step "Creating repository: $repo"
  aws ecr create-repository \
    --repository-name "$repo" \
    --region $AWS_REGION \
    --image-scanning-configuration scanOnPush=true \
    --image-tag-mutability MUTABLE \
    2>/dev/null || echo "Repository $repo already exists"
done

success "ECR repositories created"

# Build and push images
section "BUILDING AND PUSHING IMAGES"

# Function to build and push image
build_and_push() {
  local service_name=$1
  local context_path=$2
  local dockerfile_path=$3
  local version=${4:-latest}
  
  step "Building $service_name..."
  
  IMAGE_TAG="$ECR_REGISTRY/$service_name:$version"
  LATEST_TAG="$ECR_REGISTRY/$service_name:latest"
  
  # Build image
  docker build -t $IMAGE_TAG -t $LATEST_TAG -f "$dockerfile_path" "$context_path"
  
  # Push to ECR
  step "Pushing $service_name to ECR..."
  docker push $IMAGE_TAG
  docker push $LATEST_TAG
  
  # Scan image
  step "Scanning image for vulnerabilities..."
  aws ecr start-image-scan \
    --repository-name "$service_name" \
    --image-id imageTag=$version \
    --region $AWS_REGION || true
  
  success "$service_name built and pushed: $IMAGE_TAG"
}

# Parse command line arguments
ACTION="${1:-all}"
SERVICE="${2:-}"

case "$ACTION" in
  all)
    # Build all services
    step "Building all services..."
    
    # Frontend
    if [ -d "frontend" ]; then
      build_and_push "ecommerce/frontend" "frontend" "frontend/Dockerfile" "v1.0.0"
    else
      echo_colored $YELLOW "⚠️  Frontend directory not found, skipping..."
    fi
    
    # Product Service
    if [ -d "backend/product-service" ]; then
      build_and_push "ecommerce/product-service" "backend/product-service" "backend/product-service/Dockerfile" "v1.0.0"
    else
      echo_colored $YELLOW "⚠️  Product service directory not found, skipping..."
    fi
    
    # Order Service
    if [ -d "backend/order-service" ]; then
      build_and_push "ecommerce/order-service" "backend/order-service" "backend/order-service/Dockerfile" "v1.0.0"
    else
      echo_colored $YELLOW "⚠️  Order service directory not found, skipping..."
    fi
    
    success "All services built and pushed!"
    ;;
    
  frontend)
    build_and_push "ecommerce/frontend" "frontend" "frontend/Dockerfile" "${SERVICE:-v1.0.0}"
    ;;
    
  product-service)
    build_and_push "ecommerce/product-service" "backend/product-service" "backend/product-service/Dockerfile" "${SERVICE:-v1.0.0}"
    ;;
    
  order-service)
    build_and_push "ecommerce/order-service" "backend/order-service" "backend/order-service/Dockerfile" "${SERVICE:-v1.0.0}"
    ;;
    
  list)
    section "ECR REPOSITORIES"
    aws ecr describe-repositories \
      --repository-prefix ecommerce/ \
      --region $AWS_REGION \
      --query 'repositories[*].[repositoryName,repositoryUri]' \
      --output table
    ;;
    
  scan)
    section "SCANNING IMAGES"
    for repo in "${REPOS[@]}"; do
      step "Scanning $repo..."
      aws ecr start-image-scan \
        --repository-name "$repo" \
        --image-id imageTag=latest \
        --region $AWS_REGION || true
    done
    success "Image scans initiated"
    ;;
    
  scan-results)
    section "SCAN RESULTS"
    for repo in "${REPOS[@]}"; do
      echo ""
      echo_colored $BLUE "Repository: $repo"
      aws ecr describe-image-scan-findings \
        --repository-name "$repo" \
        --image-id imageTag=latest \
        --region $AWS_REGION \
        --query 'imageScanFindings.{findingSeverityCounts:findingSeverityCounts,enhancedFindingsCount:enhancedFindingsCount}' \
        --output table || echo "No scan results available"
    done
    ;;
    
  *)
    echo "Usage: $0 {all|frontend|product-service|order-service|list|scan|scan-results} [version]"
    echo ""
    echo "Examples:"
    echo "  $0 all                    # Build and push all services"
    echo "  $0 frontend v1.0.0        # Build and push frontend with version"
    echo "  $0 list                   # List all ECR repositories"
    echo "  $0 scan                   # Scan all images for vulnerabilities"
    echo "  $0 scan-results           # View scan results"
    exit 1
    ;;
esac

echo ""
success "ECR operations completed!"
echo ""
echo_colored $BLUE "🔗 ECR Console: https://$AWS_REGION.console.aws.amazon.com/ecr/private?region=$AWS_REGION"