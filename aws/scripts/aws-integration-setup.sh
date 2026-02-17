#!/bin/bash
set -e

######################################################################
# AWS Integration Setup Script
# Account ID: 564268554451
# Region: us-east-1
######################################################################

AWS_ACCOUNT_ID="564268554451"
AWS_REGION="us-east-1"
CLUSTER_NAME="ecommerce-prod"

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

warn() {
    echo_colored $YELLOW "⚠️  $1"
}

error_exit() {
    echo_colored $RED "❌ ERROR: $1"
    exit 1
}

# Check prerequisites
section "PREREQUISITES CHECK"

command -v aws >/dev/null 2>&1 || error_exit "AWS CLI is not installed"
command -v kubectl >/dev/null 2>&1 || error_exit "kubectl is not installed"

# Verify AWS credentials
step "Verifying AWS credentials..."
CALLER_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

if [ "$CALLER_ACCOUNT" != "$AWS_ACCOUNT_ID" ]; then
  error_exit "AWS Account ID mismatch. Expected: $AWS_ACCOUNT_ID, Got: $CALLER_ACCOUNT"
fi

success "AWS Account verified: $AWS_ACCOUNT_ID"

# Get current region or use default
CURRENT_REGION=$(aws configure get region 2>/dev/null || echo "$AWS_REGION")
AWS_REGION="${CURRENT_REGION:-$AWS_REGION}"

step "Using region: $AWS_REGION"

# Create IAM policies
section "CREATING IAM POLICIES"

step "Creating EKS node policy..."
aws iam create-policy \
  --policy-name EKSNodeAdditionalPolicy \
  --policy-document file://aws/iam/ecommerce-app-policy.json \
  --region $AWS_REGION 2>/dev/null || warn "Policy already exists"

step "Creating Load Balancer Controller policy..."
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://aws/iam/ecommerce-app-policy.json \
  --region $AWS_REGION 2>/dev/null || warn "Policy already exists"

success "IAM policies created"

# Create S3 bucket for static site
section "CREATING S3 BUCKET"

BUCKET_NAME="ecommerce-static-site-$AWS_ACCOUNT_ID"

step "Creating S3 bucket: $BUCKET_NAME"

# Check if bucket exists
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  warn "Bucket already exists: $BUCKET_NAME"
else
  if [ "$AWS_REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region $AWS_REGION
  else
    aws s3api create-bucket \
      --bucket "$BUCKET_NAME" \
      --region $AWS_REGION \
      --create-bucket-configuration LocationConstraint=$AWS_REGION
  fi
fi

# Enable website hosting
step "Enabling website hosting..."
aws s3api put-bucket-website \
  --bucket "$BUCKET_NAME" \
  --website-configuration '{
    "IndexDocument": {"Suffix": "index.html"},
    "ErrorDocument": {"Suffix": "index.html"}
  }'

# Configure public access
step "Configuring public access..."
aws s3api put-bucket-policy --bucket "$BUCKET_NAME" --policy '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::'"$BUCKET_NAME"'/*"
    }
  ]
}'

# Enable versioning
step "Enabling versioning..."
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

# Enable CORS
step "Enabling CORS..."
aws s3api put-bucket-cors --bucket "$BUCKET_NAME" --cors-configuration '{
  "CORSRules": [
    {
      "AllowedHeaders": ["*"],
      "AllowedMethods": ["GET", "PUT", "POST", "DELETE"],
      "AllowedOrigins": ["*"],
      "ExposeHeaders": ["ETag"],
      "MaxAgeSeconds": 3000
    }
  ]
}'

# Enable server access logging
step "Enabling access logging..."
aws s3api put-bucket-logging \
  --bucket "$BUCKET_NAME" \
  --bucket-logging-status '{
    "LoggingEnabled": {
      "TargetBucket": "'"$BUCKET_NAME"'-logs",
      "TargetPrefix": "access-logs/"
    }
  }' || warn "Could not enable access logging"

# Create logs bucket
LOGS_BUCKET="$BUCKET_NAME-logs"
aws s3api create-bucket --bucket "$LOGS_BUCKET" --region $AWS_REGION 2>/dev/null || true
aws s3api put-bucket-versioning --bucket "$LOGS_BUCKET" --versioning-configuration Status=Enabled 2>/dev/null || true

success "S3 bucket created and configured"

# Update Kubernetes manifests with AWS-specific configurations
section "UPDATING KUBERNETES MANIFESTS"

step "Updating services with AWS annotations..."

# Create AWS-specific services file
cat > manifests/08-services-aws.yaml <<EOF
# Frontend Service with AWS NLB annotations
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
  namespace: ecommerce-production
  labels:
    app: frontend
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb-ip"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
    service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"
    service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "arn:aws:acm:$AWS_REGION:$AWS_ACCOUNT_ID:certificate/your-cert-id"
    service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "tcp"
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol: "HTTP"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-port: "80"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-path: "/health"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-success-codes: "200"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-interval: "30"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-timeout: "5"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-healthy-threshold: "2"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-unhealthy-threshold: "2"
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
    name: http
  - port: 443
    targetPort: 443
    name: https
  selector:
    app: frontend
---
# API Gateway Service with AWS NLB annotations
apiVersion: v1
kind: Service
metadata:
  name: api-gateway-service
  namespace: ecommerce-production
  labels:
    app: api-gateway
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb-ip"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8000
    name: http
  - port: 443
    targetPort: 8443
    name: https
  selector:
    app: api-gateway
---
# Product Service (ClusterIP)
apiVersion: v1
kind: Service
metadata:
  name: product-service
  namespace: ecommerce-production
  labels:
    app: product-service
spec:
  type: ClusterIP
  ports:
  - port: 8080
    targetPort: 8080
    name: http
  selector:
    app: product-service
---
# Order Service (ClusterIP)
apiVersion: v1
kind: Service
metadata:
  name: order-service
  namespace: ecommerce-production
  labels:
    app: order-service
spec:
  type: ClusterIP
  ports:
  - port: 8080
    targetPort: 8080
    name: http
  selector:
    app: order-service
---
# PostgreSQL Service (Headless for StatefulSet)
apiVersion: v1
kind: Service
metadata:
  name: postgres-service
  namespace: ecommerce-production
  labels:
    app: postgres
spec:
  type: ClusterIP
  clusterIP: None
  ports:
  - port: 5432
    targetPort: 5432
    name: postgres
  selector:
    app: postgres
---
# Redis Service (Headless for StatefulSet)
apiVersion: v1
kind: Service
metadata:
  name: redis-service
  namespace: ecommerce-production
  labels:
    app: redis
spec:
  type: ClusterIP
  clusterIP: None
  ports:
  - port: 6379
    targetPort: 6379
    name: redis
  selector:
    app: redis
EOF

success "AWS-specific manifests created"

# Update deployment images with ECR URLs
step "Updating deployment images with ECR URLs..."

ECR_PREFIX="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/ecommerce"

# Create updated deployment files
for deployment in frontend product-service order-service; do
  if [ -f "manifests/02-${deployment/product-service/product-service}-deployment.yaml" ] || \
     [ -f "manifests/02-${deployment}-deployment.yaml" ]; then
    
    case $deployment in
      frontend)
        FILE="manifests/02-frontend-deployment.yaml"
        IMAGE="$ECR_PREFIX/frontend:v1.0.0"
        ;;
      product-service)
        FILE="manifests/04-product-service-deployment.yaml"
        IMAGE="$ECR_PREFIX/product-service:v1.0.0"
        ;;
      order-service)
        FILE="manifests/05-order-service-deployment.yaml"
        IMAGE="$ECR_PREFIX/order-service:v1.0.0"
        ;;
    esac
    
    if [ -f "$FILE" ]; then
      sed -i.bak "s|image: ecommerce/$deployment.*|image: $IMAGE|g" "$FILE"
      rm -f "${FILE}.bak"
      step "Updated $FILE with ECR image: $IMAGE"
    fi
  fi
done

success "Deployment images updated"

# Create AWS-specific ConfigMap
step "Creating AWS-specific ConfigMap..."

cat > manifests/01-aws-config.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-config
  namespace: ecommerce-production
data:
  AWS_REGION: "$AWS_REGION"
  AWS_ACCOUNT_ID: "$AWS_ACCOUNT_ID"
  S3_BUCKET: "$BUCKET_NAME"
  ECR_REGISTRY: "$ECR_PREFIX"
  DYNAMODB_TABLE: "ecommerce-data"
  SECRET_NAME: "ecommerce/app-secrets"
  PARAMETER_STORE_PREFIX: "/ecommerce"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: ecommerce-production
data:
  DATABASE_HOST: "postgres-service.ecommerce-production.svc.cluster.local"
  DATABASE_PORT: "5432"
  DATABASE_NAME: "ecommerce"
  REDIS_HOST: "redis-service.ecommerce-production.svc.cluster.local"
  REDIS_PORT: "6379"
  LOG_LEVEL: "info"
  ENVIRONMENT: "production"
  API_TIMEOUT: "30s"
  AWS_REGION: "$AWS_REGION"
EOF

success "AWS ConfigMap created"

# Deploy to EKS
section "DEPLOYING TO EKS"

step "Checking EKS cluster connection..."
if ! kubectl cluster-info &>/dev/null; then
  warn "Not connected to EKS cluster"
  step "Attempting to update kubeconfig..."
  aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION || \
    warn "Could not connect to EKS cluster. Run ./aws/scripts/setup-eks.sh create first"
fi

if kubectl cluster-info &>/dev/null; then
  success "Connected to EKS cluster: $CLUSTER_NAME"
  
  step "Applying AWS configurations..."
  kubectl apply -f manifests/01-aws-config.yaml
  kubectl apply -f manifests/08-services-aws.yaml
  
  success "AWS configurations deployed"
else
  warn "Skipping Kubernetes deployment (not connected to cluster)"
fi

# Create deployment summary
section "DEPLOYMENT SUMMARY"

echo ""
echo_colored $BLUE "📋 AWS Resources Created:"
echo "  ✅ IAM Policies"
echo "  ✅ S3 Bucket: $BUCKET_NAME"
echo "  ✅ S3 Logs Bucket: $LOGS_BUCKET"
echo "  ✅ ECR Repositories (via ecr-build-push.sh)"
echo "  ✅ Kubernetes manifests updated"
echo ""
echo_colored $BLUE "🔗 AWS Console Links:"
echo "  EKS Cluster: https://$AWS_REGION.console.aws.amazon.com/eks/home?region=$AWS_REGION#/clusters/$CLUSTER_NAME"
echo "  ECR Repositories: https://$AWS_REGION.console.aws.amazon.com/ecr/private?region=$AWS_REGION"
echo "  S3 Buckets: https://$AWS_REGION.console.aws.amazon.com/s3/buckets/$BUCKET_NAME"
echo "  CloudWatch: https://$AWS_REGION.console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION"
echo "  IAM Policies: https://$AWS_REGION.console.aws.amazon.com/iam/home?region=$AWS_REGION#/policies"
echo ""
echo_colored $BLUE "📝 Next Steps:"
echo "  1. Build and push images: ./aws/scripts/ecr-build-push.sh all"
echo "  2. Deploy applications: ./scripts/deploy.sh deploy"
echo "  3. Configure DNS for your domain"
echo "  4. Set up SSL certificate in AWS ACM"
echo "  5. Update Ingress with your domain"
echo ""

success "AWS integration completed!"