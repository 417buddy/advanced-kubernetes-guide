#!/bin/bash
set -e

######################################################################
# AWS EKS Cluster Setup Script
# Account ID: 564268554451
# Region: us-east-1
######################################################################

# Configuration
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

warn() {
    echo_colored $YELLOW "⚠️  $1"
}

error_exit() {
    echo_colored $RED "❌ ERROR: $1"
    exit 1
}

success() {
    echo_colored $GREEN "✅ $1"
}

# Check prerequisites
section "PREREQUISITES CHECK"

command -v aws >/dev/null 2>&1 || error_exit "AWS CLI is not installed"
command -v eksctl >/dev/null 2>&1 || error_exit "eksctl is not installed"
command -v kubectl >/dev/null 2>&1 || error_exit "kubectl is not installed"
command -v jq >/dev/null 2>&1 || error_exit "jq is not installed"

step "Verifying AWS credentials..."
aws sts get-caller-identity --query Account --output text | grep -q "$AWS_ACCOUNT_ID" || \
  error_exit "AWS Account ID does not match. Expected: $AWS_ACCOUNT_ID"

step "AWS Account verified: $AWS_ACCOUNT_ID"
step "Region: $AWS_REGION"

# Parse command line arguments
ACTION="${1:-create}"

case "$ACTION" in
    create)
        section "CREATING EKS CLUSTER"
        
        # Step 1: Create ECR repositories
        step "Creating ECR repositories..."
        aws ecr create-repository --repository-name ecommerce/frontend --region $AWS_REGION || true
        aws ecr create-repository --repository-name ecommerce/product-service --region $AWS_REGION || true
        aws ecr create-repository --repository-name ecommerce/order-service --region $AWS_REGION || true
        aws ecr create-repository --repository-name ecommerce/auth-service --region $AWS_REGION || true
        success "ECR repositories created"
        
        # Step 2: Create KMS key for secrets encryption
        step "Creating KMS key for secrets encryption..."
        KMS_KEY_ID=$(aws kms create-key \
          --description "EKS secrets encryption for $CLUSTER_NAME" \
          --tags TagKey=Project,TagValue=E-Commerce \
          --query 'KeyMetadata.KeyId' \
          --output text \
          --region $AWS_REGION 2>/dev/null || \
          aws kms list-keys --query 'Keys[0].KeyId' --output text --region $AWS_REGION)
        
        step "KMS Key ID: $KMS_KEY_ID"
        
        # Create alias for the key
        aws kms create-alias \
          --alias-name "alias/ecommerce-eks-secrets" \
          --target-key-id "$KMS_KEY_ID" \
          --region $AWS_REGION 2>/dev/null || true
        
        success "KMS key created/verified"
        
        # Step 3: Create IAM policies
        step "Creating IAM policies..."
        
        # EBS CSI Driver Policy
        cat > /tmp/eks-ebs-csi-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSnapshot",
        "ec2:AttachVolume",
        "ec2:DetachVolume",
        "ec2:ModifyVolume",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeInstances",
        "ec2:DescribeVolumes",
        "ec2:DescribeVolumeStatus",
        "ec2:DescribeSnapshots",
        "ec2:CopySnapshot",
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:CreateVolume"
      ],
      "Resource": "*"
    }
  ]
}
EOF
        
        aws iam create-policy \
          --policy-name AmazonEKS_EBS_CSI_Driver_Policy \
          --policy-document file:///tmp/eks-ebs-csi-policy.json \
          --region $AWS_REGION 2>/dev/null || true
        
        # EFS CSI Driver Policy
        cat > /tmp/eks-efs-csi-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "elasticfilesystem:DescribeAccessPoints",
        "elasticfilesystem:DescribeFileSystems",
        "elasticfilesystem:DescribeMountTargets",
        "ec2:DescribeAvailabilityZones"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "elasticfilesystem:CreateAccessPoint"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:RequestTag/efs.csi.aws.com/cluster": "true"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": "elasticfilesystem:DeleteAccessPoint",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/efs.csi.aws.com/cluster": "true"
        }
      }
    }
  ]
}
EOF
        
        aws iam create-policy \
          --policy-name AmazonEKS_EFS_CSI_Driver_Policy \
          --policy-document file:///tmp/eks-efs-csi-policy.json \
          --region $AWS_REGION 2>/dev/null || true
        
        # Custom EKS Node IAM Policy
        cat > /tmp/eks-node-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": "arn:aws:logs:*:*:log-group:/aws/containerinsights/*"
    }
  ]
}
EOF
        
        aws iam create-policy \
          --policy-name EKSNodeAdditionalPolicy \
          --policy-document file:///tmp/eks-node-policy.json \
          --region $AWS_REGION 2>/dev/null || true
        
        success "IAM policies created"
        
        # Step 4: Create VPC (if not exists)
        step "Setting up VPC..."
        
        VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$CLUSTER_NAME-vpc" --query 'Vpcs[0].VpcId' --output text --region $AWS_REGION)
        
        if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
          step "Creating new VPC..."
          VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value='"$CLUSTER_NAME-vpc"'}]' --query 'Vpc.VpcId' --output text --region $AWS_REGION)
          aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support '{"Value": true}' --region $AWS_REGION
          aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames '{"Value": true}' --region $AWS_REGION
        fi
        
        step "VPC ID: $VPC_ID"
        success "VPC configured"
        
        # Step 5: Create EKS Cluster
        step "Creating EKS cluster (this may take 15-20 minutes)..."
        
        eksctl create cluster -f eks/eksctl-config.yaml || {
          warn "Cluster creation failed or cluster already exists"
          step "Attempting to update existing cluster..."
          eksctl update cluster --name $CLUSTER_NAME --region $AWS_REGION
        }
        
        success "EKS cluster created/updated"
        
        # Step 6: Configure kubectl
        step "Configuring kubectl..."
        aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION
        
        # Verify cluster access
        kubectl cluster-info | head -n 1
        success "kubectl configured"
        
        # Step 7: Install add-ons
        section "INSTALLING EKS ADD-ONS"
        
        step "Installing AWS Load Balancer Controller..."
        helm repo add eks https://aws.github.io/eks-charts
        helm repo update
        helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
          -n kube-system \
          --set clusterName=$CLUSTER_NAME \
          --set serviceAccount.create=false \
          --set serviceAccount.name=aws-load-balancer-controller \
          --set region=$AWS_REGION \
          --set vpcId=$VPC_ID || warn "Load Balancer Controller installation failed"
        
        step "Installing External DNS..."
        helm install external-dns bitnami/external-dns \
          -n kube-system \
          --set provider=aws \
          --set policy=sync \
          --set source[0]=service \
          --set source[1]=ingress \
          --set domainFilters[0]=ecommerce.example.com \
          --set serviceAccount.create=true \
          --set serviceAccount.name=external-dns || warn "External DNS installation failed"
        
        step "Installing Cluster Autoscaler..."
        helm install cluster-autoscaler autoscaler/cluster-autoscaler \
          -n kube-system \
          --set autoDiscovery.clusterName=$CLUSTER_NAME \
          --set awsRegion=$AWS_REGION \
          --set rbac.serviceAccount.create=true \
          --set rbac.serviceAccount.name=cluster-autoscaler || warn "Cluster Autoscaler installation failed"
        
        success "EKS add-ons installed"
        
        # Step 8: Verify installation
        section "VERIFICATION"
        
        step "Checking cluster status..."
        kubectl get nodes
        kubectl get pods -n kube-system | grep -E 'aws-load-balancer|external-dns|cluster-autoscaler' || true
        
        echo ""
        success "EKS cluster setup completed!"
        echo ""
        echo_colored $BLUE "📋 Next Steps:"
        echo "1. Update your DNS records for ecommerce.example.com"
        echo "2. Configure IAM OIDC provider for service accounts"
        echo "3. Deploy your applications using: ./scripts/deploy.sh deploy"
        echo "4. Monitor cluster: kubectl get all -A"
        echo ""
        echo_colored $BLUE "🔐 AWS Console Access:"
        echo "View your cluster: https://$AWS_REGION.console.aws.amazon.com/eks/home?region=$AWS_REGION#/clusters/$CLUSTER_NAME"
        echo "View ECR repositories: https://$AWS_REGION.console.aws.amazon.com/ecr/private?region=$AWS_REGION"
        echo "View CloudWatch logs: https://$AWS_REGION.console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION"
        ;;
        
    update)
        section "UPDATING EKS CLUSTER"
        
        step "Updating cluster configuration..."
        eksctl update cluster --name $CLUSTER_NAME --region $AWS_REGION
        
        step "Updating node group..."
        eksctl update nodegroup --name standard-workers --cluster $CLUSTER_NAME --region $AWS_REGION
        
        step "Updating kubeconfig..."
        aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION
        
        success "Cluster updated successfully!"
        ;;
        
    delete)
        section "DELETING EKS CLUSTER"
        
        warn "This will delete the entire EKS cluster and all resources!"
        read -p "Are you sure? Type 'yes' to confirm: " confirm
        
        if [ "$confirm" = "yes" ]; then
          step "Deleting EKS cluster..."
          eksctl delete cluster --name $CLUSTER_NAME --region $AWS_REGION
          
          step "Cleaning up ECR repositories..."
          aws ecr delete-repository --repository-name ecommerce/frontend --force --region $AWS_REGION || true
          aws ecr delete-repository --repository-name ecommerce/product-service --force --region $AWS_REGION || true
          aws ecr delete-repository --repository-name ecommerce/order-service --force --region $AWS_REGION || true
          aws ecr delete-repository --repository-name ecommerce/auth-service --force --region $AWS_REGION || true
          
          success "Cluster and resources deleted!"
        else
          echo "Deletion cancelled"
        fi
        ;;
        
    status)
        section "EKS CLUSTER STATUS"
        
        echo ""
        echo_colored $BLUE "📊 Cluster Information:"
        aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query 'cluster.{name:name,status:status,version:version,endpoint:endpoint}' --output table
        
        echo ""
        echo_colored $BLUE "🖥️  Node Groups:"
        eksctl get nodegroup --cluster $CLUSTER_NAME --region $AWS_REGION
        
        echo ""
        echo_colored $BLUE "📦 Kubernetes Nodes:"
        kubectl get nodes -o wide
        
        echo ""
        echo_colored $BLUE "🔌 Services:"
        kubectl get svc -A
        
        echo ""
        echo_colored $BLUE "📝 Recent Events:"
        kubectl get events -A --sort-by='.lastTimestamp' | tail -20
        ;;
        
    *)
        echo "Usage: $0 {create|update|delete|status}"
        echo ""
        echo "Commands:"
        echo "  create   - Create EKS cluster and all resources"
        echo "  update   - Update existing cluster configuration"
        echo "  delete   - Delete cluster and all resources"
        echo "  status   - Show cluster status and information"
        exit 1
        ;;
esac