# AWS Integration Guide

## E-Commerce Platform on Amazon EKS

**AWS Account ID**: `564268554451`  
**Region**: `us-east-1` (N. Virginia)  
**Cluster Name**: `ecommerce-prod`

---

## Quick Start

### Prerequisites

Before you begin, ensure you have the following installed:

```bash
# Required tools
aws --version           # AWS CLI v2.x
eksctl version          # eksctl v0.160.0+
kubectl version         # kubectl v1.28.0+
helm version            # Helm v3.x
docker --version        # Docker Desktop
jq --version            # JSON processor

# Verify AWS credentials
aws sts get-caller-identity
```

### AWS Setup (One-Time)

```bash
# Navigate to the project directory
cd advanced-kubernetes-guide

# Make scripts executable
chmod +x aws/scripts/*.sh scripts/*.sh

# Step 1: Set up EKS cluster (15-20 minutes)
./aws/scripts/setup-eks.sh create

# Step 2: Build and push container images to ECR
./aws/scripts/ecr-build-push.sh all

# Step 3: Complete AWS integration setup
./aws/scripts/aws-integration-setup.sh

# Step 4: Deploy applications
./scripts/deploy.sh deploy
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS Cloud                                │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                      us-east-1 Region                      │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │                    VPC (10.0.0.0/16)                 │  │  │
│  │  │  ┌───────────────────────────────────────────────┐  │  │  │
│  │  │  │           EKS Cluster: ecommerce-prod         │  │  │  │
│  │  │  │                                               │  │  │  │
│  │  │  │  ┌─────────────────┐  ┌─────────────────┐    │  │  │  │
│  │  │  │  │  Public Subnets │  │ Private Subnets │    │  │  │  │
│  │  │  │  │  (3 AZs)        │  │ (3 AZs)         │    │  │  │  │
│  │  │  │  └─────────────────┘  └─────────────────┘    │  │  │  │
│  │  │  │                                               │  │  │  │
│  │  │  │  ┌───────────────────────────────────────┐   │  │  │  │
│  │  │  │  │         EKS Node Groups                │   │  │  │  │
│  │  │  │  │  - standard-workers (m5.xlarge) × 3   │   │  │  │  │
│  │  │  │  │  - database-workers (m5.2xlarge) × 3  │   │  │  │  │
│  │  │  │  └───────────────────────────────────────┘   │  │  │  │
│  │  │  │                                               │  │  │  │
│  │  │  │  ┌───────────────────────────────────────┐   │  │  │  │
│  │  │  │  │      Kubernetes Workloads              │   │  │  │  │
│  │  │  │  │  - Frontend (NLB)                      │   │  │  │  │
│  │  │  │  │  - API Gateway (NLB)                   │   │  │  │  │
│  │  │  │  │  - Microservices (ClusterIP)           │   │  │  │  │
│  │  │  │  │  - PostgreSQL (StatefulSet)            │   │  │  │  │
│  │  │  │  │  - Redis (StatefulSet)                 │   │  │  │  │
│  │  │  │  └───────────────────────────────────────┘   │  │  │  │
│  │  │  └───────────────────────────────────────────────┘  │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  │                                                             │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │  │
│  │  │  ECR         │  │  S3          │  │  RDS/Aurora  │     │  │
│  │  │  (Images)    │  │  (Static)    │  │  (Optional)  │     │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘     │  │
│  │                                                             │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │  │
│  │  │  CloudWatch  │  │  AWS WAF     │  │  ACM         │     │  │
│  │  │  (Logs)      │  │  (Security)  │  │  (SSL/TLS)   │     │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘     │  │
│  └─────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## AWS Resources Created

### 1. **EKS Cluster**
- **Name**: `ecommerce-prod`
- **Version**: Latest Kubernetes (1.28+)
- **Region**: `us-east-1`
- **VPC**: `10.0.0.0/16` with 6 subnets (3 public, 3 private)
- **Encryption**: KMS-encrypted secrets

### 2. **Node Groups**

#### Standard Workers
- **Instance Type**: `m5.xlarge`
- **Min/Max/Desired**: 3/10/3
- **Storage**: 50GB GP3
- **Use Case**: Application workloads

#### Database Workers
- **Instance Type**: `m5.2xlarge`
- **Min/Max/Desired**: 3/6/3
- **Storage**: 100GB GP3
- **Use Case**: StatefulSets (PostgreSQL, Redis)
- **Taints**: `database=true:NoSchedule`

### 3. **ECR Repositories**
- `ecommerce/frontend`
- `ecommerce/product-service`
- `ecommerce/order-service`
- `ecommerce/auth-service`
- `ecommerce/api-gateway`

### 4. **S3 Buckets**
- **Static Site**: `ecommerce-static-site-564268554451`
- **Access Logs**: `ecommerce-static-site-564268554451-logs`

### 5. **IAM Policies**
- `EKSNodeAdditionalPolicy` - ECR, CloudWatch, S3 access
- `AmazonEKS_EBS_CSI_Driver_Policy` - EBS volume management
- `AmazonEKS_EFS_CSI_Driver_Policy` - EFS volume management
- `AWSLoadBalancerControllerIAMPolicy` - ALB/NLB management

### 6. **EKS Add-ons**
- AWS EBS CSI Driver
- AWS EFS CSI Driver
- AWS Load Balancer Controller
- External DNS
- Cluster Autoscaler
- Metrics Server
- VPC CNI
- CoreDNS
- Kube Proxy

---

## Detailed Setup Instructions

### Step 1: Configure AWS Credentials

```bash
# Option 1: AWS CLI configuration
aws configure

# Option 2: Environment variables
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_DEFAULT_REGION=us-east-1

# Verify credentials
aws sts get-caller-identity
```

Expected output:
```json
{
    "UserId": "AIDAXXXXXXXXXXXXXXXXX",
    "Account": "564268554451",
    "Arn": "arn:aws:iam::564268554451:user/your-username"
}
```

### Step 2: Create EKS Cluster

```bash
cd advanced-kubernetes-guide

# Create the cluster (this takes 15-20 minutes)
./aws/scripts/setup-eks.sh create

# Verify cluster creation
aws eks describe-cluster --name ecommerce-prod --region us-east-1

# Check node groups
eksctl get nodegroup --cluster ecommerce-prod --region us-east-1
```

### Step 3: Build and Push Container Images

```bash
# Build and push all services
./aws/scripts/ecr-build-push.sh all

# Or build individual services
./aws/scripts/ecr-build-push.sh frontend v1.0.0
./aws/scripts/ecr-build-push.sh product-service v1.0.0
./aws/scripts/ecr-build-push.sh order-service v1.0.0

# List ECR repositories
./aws/scripts/ecr-build-push.sh list

# Scan images for vulnerabilities
./aws/scripts/ecr-build-push.sh scan

# View scan results
./aws/scripts/ecr-build-push.sh scan-results
```

### Step 4: Complete AWS Integration

```bash
# Set up S3, IAM, and update manifests
./aws/scripts/aws-integration-setup.sh
```

This script:
- ✅ Creates S3 bucket for static site
- ✅ Configures bucket policies and CORS
- ✅ Creates IAM policies
- ✅ Updates Kubernetes manifests with AWS-specific configurations
- ✅ Configures ECR image references

### Step 5: Deploy Applications

```bash
# Deploy all resources
./scripts/deploy.sh deploy

# Check deployment status
./scripts/deploy.sh status

# View logs
./scripts/deploy.sh logs

# Scale services
./scripts/deploy.sh scale 5 product-service
```

---

## AWS Management Console Access

### Direct Links

Replace `us-east-1` with your region if different.

**EKS Cluster:**
```
https://us-east-1.console.aws.amazon.com/eks/home?region=us-east-1#/clusters/ecommerce-prod
```

**ECR Repositories:**
```
https://us-east-1.console.aws.amazon.com/ecr/private?region=us-east-1
```

**S3 Buckets:**
```
https://us-east-1.console.aws.amazon.com/s3/buckets?region=us-east-1
```

**CloudWatch Logs:**
```
https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1
```

**Load Balancers:**
```
https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#LoadBalancers:
```

**IAM Policies:**
```
https://us-east-1.console.aws.amazon.com/iam/home?region=us-east-1#/policies
```

---

## Management Operations

### Cluster Management

```bash
# Update cluster
./aws/scripts/setup-eks.sh update

# Check cluster status
./aws/scripts/setup-eks.sh status

# Delete cluster (CAUTION: This deletes everything!)
./aws/scripts/setup-eks.sh delete
```

### ECR Management

```bash
# List all images in a repository
aws ecr list-images \
  --repository-name ecommerce/frontend \
  --region us-east-1

# Delete an image
aws ecr batch-delete-image \
  --repository-name ecommerce/frontend \
  --image-ids imageTag=v1.0.0 \
  --region us-east-1

# Get login password
aws ecr get-login-password --region us-east-1
```

### S3 Management

```bash
# Upload frontend build
aws s3 sync frontend/build s3://ecommerce-static-site-564268554451/

# Enable CloudFront distribution (optional)
aws cloudfront create-distribution \
  --origin-domain-name ecommerce-static-site-564268554451.s3.amazonaws.com

# View bucket policy
aws s3api get-bucket-policy \
  --bucket ecommerce-static-site-564268554451
```

### Monitoring and Logging

```bash
# View CloudWatch logs
aws logs describe-log-groups \
  --log-group-name-prefix /aws/containerinsights/ecommerce-prod \
  --region us-east-1

# Get cluster metrics
kubectl top nodes
kubectl top pods -n ecommerce-production

# View cluster events
kubectl get events -n ecommerce-production --sort-by='.lastTimestamp'
```

---

## Cost Optimization

### Estimated Monthly Costs (us-east-1)

| Resource | Configuration | Estimated Cost/Month |
|----------|--------------|---------------------|
| **EKS Control Plane** | 1 cluster | $73.00 |
| **EC2 Nodes** | 3× m5.xlarge | ~$220.00 |
| **EC2 Nodes** | 3× m5.2xlarge | ~$440.00 |
| **EBS Volumes** | 6× 50GB GP3 | ~$48.00 |
| **NAT Gateway** | 3 AZs | ~$97.00 |
| **Data Transfer** | Variable | ~$50.00 |
| **Total** | | **~$928.00** |

### Cost Saving Tips

1. **Use Spot Instances** for non-critical workloads (up to 70% savings)
2. **Enable Cluster Autoscaler** to scale down during off-peak hours
3. **Use Savings Plans** for predictable workloads (up to 72% savings)
4. **Right-size pods** using VPA recommendations
5. **Clean up unused ECR images**
6. **Use S3 Intelligent-Tiering** for static assets

```bash
# Enable Spot Instances for standard workers
eksctl scale nodegroup \
  --cluster=ecommerce-prod \
  --name=standard-workers \
  --nodes=3 \
  --nodes-min=2 \
  --nodes-max=8 \
  --region=us-east-1
```

---

## Security Best Practices

### 1. Network Security
- ✅ Private subnets for nodes
- ✅ Security groups with least privilege
- ✅ Network policies for pod-to-pod communication
- ✅ VPC Flow Logs enabled

### 2. IAM Security
- ✅ IRSA (IAM Roles for Service Accounts)
- ✅ Least privilege policies
- ✅ Regular credential rotation
- ✅ No long-term access keys in pods

### 3. Data Security
- ✅ EBS encryption enabled
- ✅ Secrets encrypted with KMS
- ✅ S3 bucket policies configured
- ✅ TLS/SSL for all external communication

### 4. Container Security
- ✅ ECR image scanning enabled
- ✅ Regular vulnerability scans
- ✅ Image signing (recommended)
- ✅ Read-only root filesystems

---

## Troubleshooting

### Common Issues

**1. Cluster Creation Fails**
```bash
# Check AWS credentials
aws sts get-caller-identity

# Verify VPC quota
aws service-quotas get-service-quota \
  --service-code vpc \
  --quota-code L-29B6F2EB

# Check CloudFormation events
aws cloudformation describe-stack-events \
  --stack-name eksctl-ecommerce-prod-cluster
```

**2. Pods Stuck in Pending**
```bash
# Check node status
kubectl get nodes

# Check resource requests
kubectl describe pod <pod-name> -n ecommerce-production

# Check cluster autoscaler logs
kubectl logs -n kube-system -l app=cluster-autoscaler
```

**3. ECR Pull Errors**
```bash
# Verify ECR login
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  564268554451.dkr.ecr.us-east-1.amazonaws.com

# Check image exists
aws ecr describe-images \
  --repository-name ecommerce/frontend \
  --region us-east-1
```

**4. Load Balancer Not Created**
```bash
# Check AWS Load Balancer Controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

---

## Cleanup

### Delete All Resources

```bash
# WARNING: This will delete everything!

# 1. Delete applications
./scripts/deploy.sh undeploy

# 2. Delete ECR repositories
./aws/scripts/ecr-build-push.sh delete-all

# 3. Delete EKS cluster
./aws/scripts/setup-eks.sh delete

# 4. Delete S3 buckets
aws s3 rb s3://ecommerce-static-site-564268554451 --force
aws s3 rb s3://ecommerce-static-site-564268554451-logs --force

# 5. Delete IAM policies
aws iam delete-policy \
  --policy-arn arn:aws:iam::564268554451:policy/EKSNodeAdditionalPolicy

# 6. Delete KMS key (7-day waiting period)
aws kms schedule-key-deletion \
  --key-id <kms-key-id> \
  --pending-window-in-days 7
```

---

## Additional Resources

- [EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [EKS Workshop](https://www.eksworkshop.com/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

---

**Account ID**: 564268554451  
**Region**: us-east-1  
**Cluster**: ecommerce-prod  
**Created**: $(date +%Y-%m-%d)