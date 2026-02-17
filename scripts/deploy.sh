#!/bin/bash
set -e

######################################################################
# Advanced Kubernetes Deployment Script
# Deploys and manages a microservices e-commerce platform
######################################################################

NAMESPACE="ecommerce-production"
MONITORING_NAMESPACE="ecommerce-monitoring"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo_colored $YELLOW "⚠️  WARNING: $1"
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

command -v kubectl >/dev/null 2>&1 || error_exit "kubectl is not installed or not in PATH"
command -v helm >/dev/null 2>&1 || warn "helm is not installed (optional for monitoring)"

kubectl version --client >/dev/null 2>&1 || error_exit "kubectl is not working properly"

step "Checking cluster connectivity..."
kubectl cluster-info >/dev/null 2>&1 || error_exit "Cannot connect to Kubernetes cluster"

CLUSTER_INFO=$(kubectl cluster-info | head -n 1)
step "Connected to: $CLUSTER_INFO"

# Parse command line arguments
ACTION="${1:-deploy}"

case "$ACTION" in
    deploy)
        section "DEPLOYING E-COMMERCE PLATFORM"
        
        # Step 1: Create namespaces
        step "Creating namespaces..."
        kubectl apply -f manifests/00-namespaces.yaml
        success "Namespaces created"
        
        # Step 2: Apply ConfigMaps and Secrets
        step "Applying ConfigMaps and Secrets..."
        kubectl apply -f manifests/01-configmap-secrets.yaml
        success "ConfigMaps and Secrets applied"
        
        # Step 3: Deploy databases (StatefulSets)
        step "Deploying databases (this may take a few minutes)..."
        kubectl apply -f manifests/06-postgres-statefulset.yaml
        kubectl apply -f manifests/07-redis-statefulset.yaml
        
        step "Waiting for databases to be ready..."
        kubectl wait --for=condition=ready pod -l app=postgres -n $NAMESPACE --timeout=300s || warn "PostgreSQL not ready within timeout"
        kubectl wait --for=condition=ready pod -l app=redis -n $NAMESPACE --timeout=300s || warn "Redis not ready within timeout"
        success "Databases deployed"
        
        # Step 4: Deploy backend services
        step "Deploying backend services..."
        kubectl apply -f manifests/04-product-service-deployment.yaml
        kubectl apply -f manifests/05-order-service-deployment.yaml
        success "Backend services deployed"
        
        # Step 5: Deploy API Gateway
        step "Deploying API Gateway..."
        kubectl apply -f manifests/03-api-gateway-deployment.yaml
        success "API Gateway deployed"
        
        # Step 6: Deploy frontend
        step "Deploying frontend..."
        kubectl apply -f manifests/02-frontend-deployment.yaml
        success "Frontend deployed"
        
        # Step 7: Create Services
        step "Creating Services..."
        kubectl apply -f manifests/08-services.yaml
        success "Services created"
        
        # Step 8: Apply scaling configurations
        step "Applying scaling configurations..."
        kubectl apply -f manifests/09-hpa.yaml
        kubectl apply -f manifests/10-vpa.yaml
        success "Scaling configurations applied"
        
        # Step 9: Apply network policies
        step "Applying network policies..."
        kubectl apply -f manifests/11-network-policies.yaml
        success "Network policies applied"
        
        success "Deployment completed!"
        
        # Display status
        section "DEPLOYMENT STATUS"
        echo ""
        echo_colored $BLUE "📊 Pods Status:"
        kubectl get pods -n $NAMESPACE -o wide
        
        echo ""
        echo_colored $BLUE "🔌 Services:"
        kubectl get svc -n $NAMESPACE
        
        echo ""
        echo_colored $BLUE "⚖️  Horizontal Pod Autoscalers:"
        kubectl get hpa -n $NAMESPACE
        
        echo ""
        echo_colored $BLUE "📦 StatefulSets:"
        kubectl get statefulset -n $NAMESPACE
        ;;
        
    undeploy)
        section "UND EPLOYING E-COMMERCE PLATFORM"
        
        step "Deleting all resources in $NAMESPACE namespace..."
        kubectl delete namespace $NAMESPACE --ignore-not-found
        kubectl delete namespace $MONITORING_NAMESPACE --ignore-not-found
        
        success "Undeployment completed!"
        ;;
        
    status)
        section "DEPLOYMENT STATUS"
        
        echo ""
        echo_colored $BLUE "📊 Pods:"
        kubectl get pods -n $NAMESPACE -o wide
        
        echo ""
        echo_colored $BLUE "🔌 Services:"
        kubectl get svc -n $NAMESPACE
        
        echo ""
        echo_colored $BLUE "📦 Deployments:"
        kubectl get deployments -n $NAMESPACE
        
        echo ""
        echo_colored $BLUE "🗄️  StatefulSets:"
        kubectl get statefulset -n $NAMESPACE
        
        echo ""
        echo_colored $BLUE "⚖️  HPAs:"
        kubectl get hpa -n $NAMESPACE
        
        echo ""
        echo_colored $BLUE "🔒 Network Policies:"
        kubectl get networkpolicy -n $NAMESPACE
        ;;
        
    scale)
        REPLICAS="${2:-3}"
        DEPLOYMENT="${3:-frontend}"
        
        step "Scaling $DEPLOYMENT to $REPLICAS replicas..."
        kubectl scale deployment $DEPLOYMENT --replicas=$REPLICAS -n $NAMESPACE
        
        success "Scaled $DEPLOYMENT to $REPLICAS replicas"
        ;;
        
    logs)
        POD="${2:-}"
        if [ -z "$POD" ]; then
            POD=$(kubectl get pods -n $NAMESPACE -l app=frontend -o jsonpath='{.items[0].metadata.name}')
        fi
        step "Showing logs for pod: $POD"
        kubectl logs -f $POD -n $NAMESPACE
        ;;
        
    exec)
        POD="${2:-}"
        if [ -z "$POD" ]; then
            POD=$(kubectl get pods -n $NAMESPACE -l app=frontend -o jsonpath='{.items[0].metadata.name}')
        fi
        step "Executing into pod: $POD"
        kubectl exec -it $POD -n $NAMESPACE -- /bin/sh
        ;;
        
    *)
        echo "Usage: $0 {deploy|undeploy|status|scale <replicas> <deployment>|logs [pod]|exec [pod]}"
        echo ""
        echo "Commands:"
        echo "  deploy    - Deploy the entire e-commerce platform"
        echo "  undeploy  - Remove all resources"
        echo "  status    - Show current deployment status"
        echo "  scale     - Scale a deployment (e.g., ./deploy.sh scale 5 frontend)"
        echo "  logs      - View pod logs (optional: specify pod name)"
        echo "  exec      - Execute into a pod (optional: specify pod name)"
        exit 1
        ;;
esac

echo ""
success "Operation completed successfully!"
