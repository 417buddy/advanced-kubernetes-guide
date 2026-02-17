# Advanced Kubernetes Deployment Guide

## Deploying and Managing a Microservices E-Commerce Platform on Kubernetes

### Complete Guide to Pods, Services, and Scaling Strategies

---

## Quick Start

### Prerequisites

- Kubernetes cluster (v1.25+)
- kubectl configured
- helm (optional, for monitoring stack)

### Setup Cluster (Choose One)

**Minikube (Local Development):**
```bash
minikube start --cpus=4 --memory=8192 --disk-size=40gb
minikube addons enable ingress
minikube addons enable metrics-server
```

**Kind (Local Development):**
```bash
kind create cluster --name ecommerce-dev
```

**☁️ AWS EKS (Production) - RECOMMENDED:**
```bash
# Navigate to project directory
cd advanced-kubernetes-guide

# Make scripts executable
chmod +x aws/scripts/*.sh scripts/*.sh

# Step 1: Create EKS cluster (15-20 minutes)
./aws/scripts/setup-eks.sh create

# Step 2: Build and push images to ECR
./aws/scripts/ecr-build-push.sh all

# Step 3: Complete AWS integration
./aws/scripts/aws-integration-setup.sh

# Step 4: Deploy applications
./scripts/deploy.sh deploy
```

**Full AWS Integration Guide:** See [aws/AWS-INTEGRATION-README.md](aws/AWS-INTEGRATION-README.md)

**Cloud (Production):**
```bash
# AWS EKS
eksctl create cluster --name ecommerce-prod --region us-east-1 --nodegroup-name standard-workers --node-type m5.xlarge --nodes 3

# GCP GKE
gcloud container clusters create ecommerce-prod --num-nodes=3 --machine-type=e2-standard-4

# Azure AKS
az aks create --resource-group ecommerce-rg --name ecommerce-prod --node-count 3 --node-vm-size Standard_DS3_v2
```

### Deploy the Application

```bash
# Navigate to the project directory
cd advanced-kubernetes-guide

# Make the deployment script executable
chmod +x scripts/deploy.sh

# Deploy everything
./scripts/deploy.sh deploy
```

### Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n ecommerce-production

# Check services
kubectl get svc -n ecommerce-production

# View detailed status
./scripts/deploy.sh status
```

### Access the Application

```bash
# Get frontend service URL
kubectl get svc frontend-service -n ecommerce-production

# For Minikube
minikube service frontend-service -n ecommerce-production --url

# For Kind
kubectl port-forward svc/frontend-service 8080:80 -n ecommerce-production
# Then access: http://localhost:8080
```

### Scale Applications

```bash
# Manual scaling
./scripts/deploy.sh scale 5 product-service

# Or using kubectl directly
kubectl scale deployment product-service --replicas=5 -n ecommerce-production

# Automatic scaling (HPA is already configured)
kubectl get hpa -n ecommerce-production
```

### Monitor the Application

```bash
# View pod metrics
kubectl top pods -n ecommerce-production

# View node metrics
kubectl top nodes

# Watch pods in real-time
kubectl get pods -n ecommerce-production -w

# View logs
./scripts/deploy.sh logs

# Or specify a pod
kubectl logs -f <pod-name> -n ecommerce-production
```

### Undeploy

```bash
# Remove all resources
./scripts/deploy.sh undeploy
```

---

## Project Structure

```
advanced-kubernetes-guide/
├── manifests/                    # Kubernetes manifests
│   ├── 00-namespaces.yaml
│   ├── 01-configmap-secrets.yaml
│   ├── 02-frontend-deployment.yaml
│   ├── 03-api-gateway-deployment.yaml
│   ├── 04-product-service-deployment.yaml
│   ├── 05-order-service-deployment.yaml
│   ├── 06-postgres-statefulset.yaml
│   ├── 07-redis-statefulset.yaml
│   ├── 08-services.yaml
│   ├── 09-hpa.yaml
│   ├── 10-vpa.yaml
│   └── 11-network-policies.yaml
├── scripts/                      # Deployment scripts
│   └── deploy.sh
├── aws/                          # AWS integration
│   ├── eks/                      # EKS configurations
│   ├── ecr/                      # ECR configurations
│   ├── iam/                      # IAM policies
│   ├── scripts/                  # AWS setup scripts
│   │   ├── setup-eks.sh
│   │   ├── ecr-build-push.sh
│   │   └── aws-integration-setup.sh
│   └── AWS-INTEGRATION-README.md
├── .github/workflows/            # GitHub Actions CI/CD
│   ├── validate-manifests.yaml
│   ├── deploy.yaml
│   └── security-scan.yaml
├── configs/                      # Additional configurations
├── docs/
│   └── complete-guide.md         # Comprehensive documentation
└── README.md                     # This file
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Kubernetes Cluster                      │
│  ┌───────────────────────────────────────────────────┐  │
│  │            ecommerce-production Namespace          │  │
│  │                                                    │  │
│  │  ┌──────────────┐  ┌──────────────┐              │  │
│  │  │   Frontend   │  │ API Gateway  │              │  │
│  │  │   (React)    │  │    (Kong)    │              │  │
│  │  │  Replicas: 3 │  │  Replicas: 3 │              │  │
│  │  └──────┬───────┘  └──────┬───────┘              │  │
│  │         │                 │                       │  │
│  │  ┌──────┴─────────────────┴──────────┐           │  │
│  │  │         ClusterIP Services         │           │  │
│  │  └──────┬─────────────────┬──────────┘           │  │
│  │         │                 │                       │  │
│  │  ┌──────┴──────┐   ┌──────┴──────┐              │  │
│  │  │   Product   │   │    Order    │              │  │
│  │  │  Service    │   │   Service   │              │  │
│  │  │  Replicas: 3│   │  Replicas: 3│              │  │
│  │  └──────┬──────┘   └──────┬──────┘              │  │
│  │         │                 │                       │  │
│  │  ┌──────┴─────────────────┴──────────┐           │  │
│  │  │      PostgreSQL    Redis          │           │  │
│  │  │      (StatefulSet) (StatefulSet)  │           │  │
│  │  └───────────────────────────────────┘           │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## Key Components

### 1. Namespaces
- **ecommerce-production**: Main application namespace
- **ecommerce-monitoring**: Monitoring stack namespace

### 2. ConfigMaps & Secrets
Centralized configuration management for all microservices.

### 3. Deployments
- **Frontend**: React SPA with health checks and security context
- **API Gateway**: Kong API Gateway for routing and rate limiting
- **Product Service**: Product catalog microservice
- **Order Service**: Order processing microservice

### 4. StatefulSets
- **PostgreSQL**: Primary database with persistent storage
- **Redis**: Cache and session storage

### 5. Services
- **LoadBalancer**: Frontend and API Gateway (external access)
- **ClusterIP**: Internal microservices communication
- **Headless**: StatefulSets (direct pod access)

### 6. Scaling
- **HPA**: Automatic scaling based on CPU/memory (70-80% utilization)
- **VPA**: Right-sizing recommendations
- **Manual**: On-demand scaling via kubectl

### 7. Network Policies
- Default deny all ingress
- Explicit allow rules for each tier
- Database access restricted to backend only

---

## Scaling Strategies

### Horizontal Pod Autoscaler (HPA)

Automatically scales pods based on metrics:

```bash
# View HPA status
kubectl get hpa -n ecommerce-production

# View HPA details
kubectl describe hpa product-service-hpa -n ecommerce-production
```

**Configuration:**
- Min replicas: 3
- Max replicas: 20 (product), 50 (order)
- Target CPU: 70%
- Target Memory: 80%
- Scale up: Immediate (no stabilization)
- Scale down: 300s stabilization window

### Vertical Pod Autoscaler (VPA)

Provides right-sizing recommendations:

```bash
# Install VPA (if not installed)
kubectl apply -f https://github.com/kubernetes/autoscaler/releases/download/vertical-pod-autoscaler-0.14.0/vpa-v0.14.0.yaml

# View VPA recommendations
kubectl get vpa -n ecommerce-production
kubectl describe vpa product-service-vpa -n ecommerce-production
```

### Cluster Autoscaler

Automatically adds/removes nodes based on pod scheduling needs.

### KEDA (Event-Driven Scaling)

Scale based on custom events (SQS, Kafka, Prometheus metrics):

```bash
# Install KEDA
helm repo add kedacore https://kedacore.github.io/charts
helm install keda kedacore/keda --namespace keda --create-namespace
```

---

## Management Operations

### Rolling Updates

```bash
# Update image
kubectl set image deployment/product-service \
  product-service=ecommerce/product-service:v1.1.0 \
  -n ecommerce-production

# Watch rollout
kubectl rollout status deployment/product-service -n ecommerce-production

# View history
kubectl rollout history deployment/product-service -n ecommerce-production

# Rollback
kubectl rollout undo deployment/product-service -n ecommerce-production
```

### Resource Management

```bash
# View resource usage
kubectl top pods -n ecommerce-production
kubectl top nodes

# Set resource quota
kubectl apply -f - <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: ecommerce-production
spec:
  hard:
    requests.cpu: "20"
    requests.memory: 40Gi
    limits.cpu: "40"
    limits.memory: 80Gi
    pods: "100"
EOF
```

### Debugging

```bash
# Describe pod (events, status)
kubectl describe pod <pod-name> -n ecommerce-production

# View logs
kubectl logs -f <pod-name> -n ecommerce-production

# Execute into pod
kubectl exec -it <pod-name> -n ecommerce-production -- /bin/sh

# Test service connectivity
kubectl run test --rm -it --image=busybox --restart=Never -- \
  nc product-service 8080
```

---

## Monitoring & Observability

### Install Prometheus Stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace ecommerce-monitoring \
  --create-namespace
```

### Access Grafana

```bash
kubectl port-forward svc/prometheus-grafana 3000:80 -n ecommerce-monitoring
# Username: admin
# Password: Check with: kubectl get secret prometheus-grafana -n ecommerce-monitoring -o jsonpath="{.data.admin-password}" | base64 -d
```

### Access Prometheus

```bash
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n ecommerce-monitoring
```

---

## Best Practices

### ✅ Security
- Use Pod Security Standards (restricted)
- Implement NetworkPolicies
- Use read-only root filesystems
- Drop all capabilities
- Run as non-root user
- Rotate secrets regularly

### ✅ High Availability
- Minimum 3 replicas for critical services
- PodDisruptionBudgets configured
- Pod anti-affinity for node distribution
- Topology spread constraints for zone distribution

### ✅ Resource Management
- Always set requests and limits
- Use LimitRanges for defaults
- Implement ResourceQuotas
- Regular right-sizing with VPA

### ✅ Observability
- Health checks (liveness, readiness, startup)
- Metrics endpoints exposed
- Structured logging
- Distributed tracing

---

## Troubleshooting

### Common Issues

**Pods not starting:**
```bash
kubectl describe pod <pod-name> -n ecommerce-production
kubectl logs <pod-name> -n ecommerce-production
```

**Services not accessible:**
```bash
kubectl get endpoints <service-name> -n ecommerce-production
kubectl get svc <service-name> -n ecommerce-production
```

**HPA not scaling:**
```bash
kubectl describe hpa <hpa-name> -n ecommerce-production
kubectl top pods -n ecommerce-production
```

**Database connection issues:**
```bash
# Test connectivity
kubectl run test --rm -it --image=postgres:15-alpine --restart=Never -- \
  psql -h postgres-service -U ecommerce_admin -d ecommerce
```

---

## Next Steps

1. **CI/CD Integration**: Set up GitHub Actions or Jenkins for automated deployments
2. **GitOps**: Implement ArgoCD or Flux for GitOps workflows
3. **Service Mesh**: Add Istio or Linkerd for advanced traffic management
4. **Security Scanning**: Integrate Trivy or Snyk for vulnerability scanning
5. **Cost Optimization**: Implement Kubecost for cost monitoring
6. **Backup Strategy**: Set up Velero for cluster backups

---

## Additional Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Kubernetes Patterns](https://kubernetes.io/patterns/)
- [CNCF Landscape](https://landscape.cncf.io/)

---

**Repository**: https://github.com/417buddy/advanced-kubernetes-guide  
**Author**: DevOps Engineer  
**License**: MIT