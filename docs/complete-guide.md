# Advanced Kubernetes Deployment Guide

## Deploying and Managing a Microservices E-Commerce Platform on Kubernetes

### Complete Guide to Pods, Services, and Scaling Strategies

---

## Table of Contents

1. [Introduction](#introduction)
2. [Architecture Overview](#architecture-overview)
3. [Prerequisites](#prerequisites)
4. [Workload Description](#workload-description)
5. [Kubernetes Manifests](#kubernetes-manifests)
   - [Namespaces](#namespaces)
   - [ConfigMaps & Secrets](#configmaps--secrets)
   - [Deployments](#deployments)
   - [Services](#services)
   - [Ingress](#ingress)
6. [Scaling Strategies](#scaling-strategies)
   - [Horizontal Pod Autoscaler (HPA)](#horizontal-pod-autoscaler-hpa)
   - [Vertical Pod Autoscaler (VPA)](#vertical-pod-autoscaler-vpa)
   - [Cluster Autoscaler](#cluster-autoscaler)
   - [KEDA Event-Driven Scaling](#keda-event-driven-scaling)
7. [Deployment Process](#deployment-process)
8. [Management & Operations](#management--operations)
9. [Monitoring & Observability](#monitoring--observability)
10. [Best Practices](#best-practices)
11. [Troubleshooting](#troubleshooting)

---

## Introduction

This guide walks you through deploying and managing a **microservices e-commerce platform** on advanced Kubernetes clusters. We'll cover everything from basic pod deployment to advanced scaling strategies used in production environments.

### What You'll Learn

- Deploying containerized applications using Deployments and StatefulSets
- Configuring Services for internal and external communication
- Implementing multiple scaling strategies
- Managing configurations with ConfigMaps and Secrets
- Setting up monitoring and observability
- Production best practices

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Kubernetes Cluster                        │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    Production Namespace                    │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │  │
│  │  │   Frontend  │  │  API Gateway │  │   Auth      │        │  │
│  │  │   (React)   │  │   (Kong)    │  │   Service   │        │  │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘        │  │
│  │         │                │                │                │  │
│  │  ┌──────┴────────────────┴────────────────┴────────┐      │  │
│  │  │              ClusterIP Services                  │      │  │
│  │  └──────┬────────────────┬────────────────┬────────┘      │  │
│  │         │                │                │                │  │
│  │  ┌──────┴──────┐  ┌──────┴──────┐  ┌──────┴──────┐        │  │
│  │  │   Product   │  │    Cart     │  │    Order    │        │  │
│  │  │   Service   │  │   Service   │  │   Service   │        │  │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘        │  │
│  │         │                │                │                │  │
│  │  ┌──────┴────────────────┴────────────────┴────────┐      │  │
│  │  │              PostgreSQL (StatefulSet)            │      │  │
│  │  │              Redis Cache                         │      │  │
│  │  └──────────────────────────────────────────────────┘      │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              Monitoring Namespace                          │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │  │
│  │  │  Prometheus │  │   Grafana   │  │    Jaeger   │        │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘        │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │   Load Balancer │
                    │   (Ingress)     │
                    └─────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │     Users       │
                    └─────────────────┘
```

---

## Prerequisites

### Required Tools

```bash
# Kubernetes cluster (v1.25+)
kubectl version --client
# kubectl version: v1.28.0+

# Cluster options:
# - Minikube (local development)
# - Kind (Kubernetes in Docker)
# - EKS/GKE/AKS (cloud production)
# - Rancher (on-premises)

# Additional tools
helm version        # v3.10.0+
kubectx             # Context switching
kubens              # Namespace switching
stern               # Log tailing
```

### Cluster Setup (Choose One)

**Minikube (for local development):**
```bash
minikube start --cpus=4 --memory=8192 --disk-size=40gb
minikube addons enable ingress
minikube addons enable metrics-server
```

**Kind (for local development):**
```bash
kind create cluster --name ecommerce-dev --config kind-config.yaml
```

**EKS (for production):**
```bash
eksctl create cluster \
  --name ecommerce-prod \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type m5.xlarge \
  --nodes 3 \
  --nodes-min 3 \
  --nodes-max 10
```

---

## Workload Description

### E-Commerce Platform Microservices

| Service | Description | Replicas | Resources |
|---------|-------------|----------|-----------|
| **Frontend** | React SPA | 3 | 100m-500m CPU, 128Mi-512Mi |
| **API Gateway** | Kong/APISIX | 3 | 200m-1000m CPU, 256Mi-1Gi |
| **Auth Service** | JWT authentication | 3 | 100m-500m CPU, 128Mi-512Mi |
| **Product Service** | Product catalog | 3 | 100m-500m CPU, 128Mi-512Mi |
| **Cart Service** | Shopping cart | 3 | 100m-500m CPU, 128Mi-512Mi |
| **Order Service** | Order processing | 3 | 200m-1000m CPU, 256Mi-1Gi |
| **PostgreSQL** | Primary database | 3 (StatefulSet) | 500m-2000m CPU, 1Gi-4Gi |
| **Redis** | Cache & sessions | 3 | 100m-500m CPU, 256Mi-1Gi |

---

## Kubernetes Manifests

### Namespaces

Create namespace configuration:

```yaml
# manifests/00-namespaces.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ecommerce-production
  labels:
    name: production
    environment: production
    monitoring: enabled
---
apiVersion: v1
kind: Namespace
metadata:
  name: ecommerce-monitoring
  labels:
    name: monitoring
    environment: production
```

Apply namespaces:
```bash
kubectl apply -f manifests/00-namespaces.yaml
```

### ConfigMaps & Secrets

```yaml
# manifests/01-configmap-secrets.yaml
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
---
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: ecommerce-production
type: Opaque
stringData:
  DATABASE_USER: "ecommerce_admin"
  DATABASE_PASSWORD: "secure-password-change-me"
  JWT_SECRET: "your-jwt-secret-key-change-me"
  API_KEY: "your-api-key-change-me"
---
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
  namespace: ecommerce-production
type: Opaque
stringData:
  POSTGRES_USER: "ecommerce_admin"
  POSTGRES_PASSWORD: "secure-postgres-password-change-me"
  POSTGRES_DB: "ecommerce"
```

Apply configurations:
```bash
kubectl apply -f manifests/01-configmap-secrets.yaml
```

### Deployments

#### Frontend Deployment

```yaml
# manifests/02-frontend-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: ecommerce-production
  labels:
    app: frontend
    tier: frontend
    version: v1.0.0
spec:
  replicas: 3
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
        tier: frontend
        version: v1.0.0
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
    spec:
      containers:
      - name: frontend
        image: ecommerce/frontend:v1.0.0
        ports:
        - containerPort: 80
          name: http
        envFrom:
        - configMapRef:
            name: app-config
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        livenessProbe:
          httpGet:
            path: /health
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /ready
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  app: frontend
              topologyKey: kubernetes.io/hostname
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app: frontend
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: frontend-pdb
  namespace: ecommerce-production
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: frontend
```

#### API Gateway Deployment

```yaml
# manifests/03-api-gateway-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  namespace: ecommerce-production
  labels:
    app: api-gateway
    tier: gateway
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api-gateway
  template:
    metadata:
      labels:
        app: api-gateway
        tier: gateway
    spec:
      containers:
      - name: kong
        image: kong:3.4
        ports:
        - containerPort: 8000
          name: proxy
        - containerPort: 8443
          name: proxy-ssl
        - containerPort: 8001
          name: admin
        env:
        - name: KONG_DATABASE
          value: "off"
        - name: KONG_DECLARATIVE_CONFIG
          value: "/kong/declarative/kong.yml"
        - name: KONG_PROXY_ACCESS_LOG
          value: "/dev/stdout"
        - name: KONG_ADMIN_ACCESS_LOG
          value: "/dev/stdout"
        - name: KONG_PROXY_ERROR_LOG
          value: "/dev/stderr"
        - name: KONG_ADMIN_ERROR_LOG
          value: "/dev/stderr"
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 1000m
            memory: 1Gi
        livenessProbe:
          httpGet:
            path: /status
            port: 8001
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /status
            port: 8001
          initialDelaySeconds: 5
          periodSeconds: 5
```

#### Product Service Deployment

```yaml
# manifests/04-product-service-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: product-service
  namespace: ecommerce-production
  labels:
    app: product-service
    tier: backend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: product-service
  template:
    metadata:
      labels:
        app: product-service
        tier: backend
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
    spec:
      containers:
      - name: product-service
        image: ecommerce/product-service:v1.0.0
        ports:
        - containerPort: 8080
          name: http
        envFrom:
        - configMapRef:
            name: app-config
        - secretRef:
            name: app-secrets
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        livenessProbe:
          httpGet:
            path: /health/live
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
```

#### Order Service Deployment

```yaml
# manifests/05-order-service-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
  namespace: ecommerce-production
  labels:
    app: order-service
    tier: backend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: order-service
  template:
    metadata:
      labels:
        app: order-service
        tier: backend
    spec:
      containers:
      - name: order-service
        image: ecommerce/order-service:v1.0.0
        ports:
        - containerPort: 8080
        envFrom:
        - configMapRef:
            name: app-config
        - secretRef:
            name: app-secrets
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 1000m
            memory: 1Gi
        livenessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - "pgrep -f order-service"
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
```

### StatefulSets

#### PostgreSQL StatefulSet

```yaml
# manifests/06-postgres-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: ecommerce-production
spec:
  serviceName: postgres-service
  replicas: 3
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:15-alpine
        ports:
        - containerPort: 5432
          name: postgres
        envFrom:
        - secretRef:
            name: postgres-secret
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 2000m
            memory: 4Gi
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
        livenessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - $(POSTGRES_USER)
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - $(POSTGRES_USER)
          initialDelaySeconds: 5
          periodSeconds: 5
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: gp2
      resources:
        requests:
          storage: 50Gi
```

#### Redis StatefulSet

```yaml
# manifests/07-redis-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  namespace: ecommerce-production
spec:
  serviceName: redis-service
  replicas: 3
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
          name: redis
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 1Gi
        volumeMounts:
        - name: redis-data
          mountPath: /data
        livenessProbe:
          exec:
            command:
            - redis-cli
            - ping
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - redis-cli
            - ping
          initialDelaySeconds: 5
          periodSeconds: 5
  volumeClaimTemplates:
  - metadata:
      name: redis-data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: gp2
      resources:
        requests:
          storage: 10Gi
```

### Services

```yaml
# manifests/08-services.yaml
# Frontend Service (LoadBalancer)
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
  namespace: ecommerce-production
  labels:
    app: frontend
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-internal: "false"
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
# API Gateway Service (LoadBalancer)
apiVersion: v1
kind: Service
metadata:
  name: api-gateway-service
  namespace: ecommerce-production
  labels:
    app: api-gateway
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
```

### Ingress

```yaml
# manifests/09-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ecommerce-ingress
  namespace: ecommerce-production
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/rate-limit: "100"
    nginx.ingress.kubernetes.io/rate-limit-window: "1m"
spec:
  tls:
  - hosts:
    - ecommerce.example.com
    - api.ecommerce.example.com
    secretName: ecommerce-tls
  rules:
  - host: ecommerce.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-service
            port:
              number: 80
  - host: api.ecommerce.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-gateway-service
            port:
              number: 80
```

---

## Scaling Strategies

### Horizontal Pod Autoscaler (HPA)

```yaml
# manifests/10-hpa.yaml
# Product Service HPA
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: product-service-hpa
  namespace: ecommerce-production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: product-service
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  - type: Pods
    pods:
      metric:
        name: requests_per_second
      target:
        type: AverageValue
        averageValue: "1000"
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
        periodSeconds: 15
      - type: Pods
        value: 10
        periodSeconds: 15
      selectPolicy: Max
---
# Order Service HPA (more aggressive scaling)
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: order-service-hpa
  namespace: ecommerce-production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: order-service
  minReplicas: 3
  maxReplicas: 50
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
  - type: Pods
    pods:
      metric:
        name: queue_depth
      target:
        type: AverageValue
        averageValue: "100"
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 200
        periodSeconds: 30
    scaleDown:
      stabilizationWindowSeconds: 600
      policies:
      - type: Percent
        value: 20
        periodSeconds: 120
```

Apply HPA:
```bash
kubectl apply -f manifests/10-hpa.yaml
```

### Vertical Pod Autoscaler (VPA)

```yaml
# manifests/11-vpa.yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: product-service-vpa
  namespace: ecommerce-production
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: product-service
  updatePolicy:
    updateMode: "Auto"  # Options: Off, Initial, Recreate, Auto
  resourcePolicy:
    containerPolicies:
    - containerName: '*'
      minAllowed:
        cpu: 50m
        memory: 64Mi
      maxAllowed:
        cpu: 2000m
        memory: 4Gi
      controlledResources: ["cpu", "memory"]
      controlledValues: RequestsAndLimits
```

Install VPA (if not already installed):
```bash
kubectl apply -f https://github.com/kubernetes/autoscaler/releases/download/vertical-pod-autoscaler-0.14.0/vpa-v0.14.0.yaml
```

### Cluster Autoscaler

Configure cluster autoscaler for your cloud provider:

**AWS EKS:**
```yaml
# manifests/12-cluster-autoscaler.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
  name: cluster-autoscaler
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/eks-cluster-autoscaler-role
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-autoscaler
rules:
- apiGroups: [""]
  resources: ["events", "endpoints"]
  verbs: ["create", "patch"]
- apiGroups: [""]
  resources: ["pods/eviction"]
  verbs: ["create"]
- apiGroups: [""]
  resources: ["pods/status"]
  verbs: ["update"]
- apiGroups: [""]
  resources: ["endpoints"]
  resourceNames: ["cluster-autoscaler"]
  verbs: ["get", "update"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["watch", "list", "get", "update"]
- apiGroups: [""]
  resources: ["namespaces", "pods", "services", "replicationcontrollers", "persistentvolumeclaims", "persistentvolumes"]
  verbs: ["watch", "list", "get"]
- apiGroups: ["extensions"]
  resources: ["replicasets", "daemonsets"]
  verbs: ["watch", "list", "get"]
- apiGroups: ["policy"]
  resources: ["poddisruptionbudgets"]
  verbs: ["watch", "list"]
- apiGroups: ["apps"]
  resources: ["statefulsets", "replicasets", "daemonsets"]
  verbs: ["watch", "list", "get"]
- apiGroups: ["storage.k8s.io"]
  resources: ["storageclasses", "csinodes", "csidrivers", "csistoragecapacities"]
  verbs: ["watch", "list", "get"]
- apiGroups: ["batch", "extensions"]
  resources: ["jobs"]
  verbs: ["get", "list", "watch", "patch"]
- apiGroups: ["coordination.k8s.io"]
  resources: ["leases"]
  verbs: ["create"]
- apiGroups: ["coordination.k8s.io"]
  resourceNames: ["cluster-autoscaler"]
  resources: ["leases"]
  verbs: ["get", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: cluster-autoscaler
  namespace: kube-system
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["create","list","watch"]
- apiGroups: [""]
  resources: ["configmaps"]
  resourceNames: ["cluster-autoscaler-status","cluster-autoscaler-priority-expander"]
  verbs: ["delete","get","update","watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-autoscaler
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-autoscaler
subjects:
- kind: ServiceAccount
  name: cluster-autoscaler
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: cluster-autoscaler
  namespace: kube-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: cluster-autoscaler
subjects:
- kind: ServiceAccount
  name: cluster-autoscaler
  namespace: kube-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  labels:
    app: cluster-autoscaler
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cluster-autoscaler
  template:
    metadata:
      labels:
        app: cluster-autoscaler
    spec:
      serviceAccountName: cluster-autoscaler
      containers:
      - image: registry.k8s.io/autoscaling/cluster-autoscaler:v1.28.0
        name: cluster-autoscaler
        resources:
          limits:
            cpu: 100m
            memory: 500Mi
          requests:
            cpu: 100m
            memory: 500Mi
        command:
        - ./cluster-autoscaler
        - --v=4
        - --stderrthreshold=info
        - --cloud-provider=aws
        - --skip-nodes-with-local-storage=false
        - --expander=least-waste
        - --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/ecommerce-prod
        - --balance-similar-node-groups
        - --skip-nodes-with-system-pods=false
        - --scale-down-utilization-threshold=0.5
        - --scale-down-unneeded-time=10m
        - --scale-down-delay-after-add=10m
        env:
        - name: AWS_REGION
          value: us-east-1
        volumeMounts:
        - name: ssl-certs
          mountPath: /etc/ssl/certs/ca-certificates.crt
          readOnly: true
        imagePullPolicy: "Always"
      volumes:
      - name: ssl-certs
        hostPath:
          path: /etc/ssl/certs/ca-bundle.crt
```

### KEDA Event-Driven Scaling

Install KEDA:
```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm install keda kedacore/keda --namespace keda --create-namespace
```

KEDA scaling configuration:
```yaml
# manifests/13-keda-scaledobject.yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: order-service-scaledobject
  namespace: ecommerce-production
spec:
  scaleTargetRef:
    name: order-service
  minReplicaCount: 3
  maxReplicaCount: 100
  pollingInterval: 15
  cooldownPeriod: 300
  advanced:
    horizontalPodAutoscalerConfig:
      behavior:
        scaleDown:
          stabilizationWindowSeconds: 600
    restoreToOriginalReplicaCount: false
  triggers:
  - type: aws-sqs
    metadata:
      queueURL: https://sqs.us-east-1.amazonaws.com/ACCOUNT_ID/order-queue
      queueLength: "50"
      awsRegion: us-east-1
    authenticationRef:
      name: aws-auth
  - type: prometheus
    metadata:
      serverAddress: http://prometheus.ecommerce-monitoring.svc:9090
      metricName: http_requests_total
      query: sum(rate(http_requests_total{service="order-service"}[2m]))
      threshold: '1000'
```

---

## Deployment Process

### Step-by-Step Deployment

```bash
#!/bin/bash
# scripts/deploy.sh

set -e

NAMESPACE="ecommerce-production"
MONITORING_NAMESPACE="ecommerce-monitoring"

echo "🚀 Starting deployment..."

# 1. Create namespaces
echo "📦 Creating namespaces..."
kubectl apply -f manifests/00-namespaces.yaml

# 2. Apply ConfigMaps and Secrets
echo "🔐 Applying ConfigMaps and Secrets..."
kubectl apply -f manifests/01-configmap-secrets.yaml

# 3. Deploy databases (StatefulSets)
echo "🗄️  Deploying databases..."
kubectl apply -f manifests/06-postgres-statefulset.yaml
kubectl apply -f manifests/07-redis-statefulset.yaml

# Wait for databases to be ready
echo "⏳ Waiting for databases to be ready..."
kubectl wait --for=condition=ready pod -l app=postgres -n $NAMESPACE --timeout=300s
kubectl wait --for=condition=ready pod -l app=redis -n $NAMESPACE --timeout=300s

# 4. Deploy backend services
echo "🔧 Deploying backend services..."
kubectl apply -f manifests/04-product-service-deployment.yaml
kubectl apply -f manifests/05-order-service-deployment.yaml

# 5. Deploy API Gateway
echo "🌐 Deploying API Gateway..."
kubectl apply -f manifests/03-api-gateway-deployment.yaml

# 6. Deploy frontend
echo "🎨 Deploying frontend..."
kubectl apply -f manifests/02-frontend-deployment.yaml

# 7. Create Services
echo "🔌 Creating Services..."
kubectl apply -f manifests/08-services.yaml

# 8. Configure Ingress
echo "🚪 Configuring Ingress..."
kubectl apply -f manifests/09-ingress.yaml

# 9. Apply scaling configurations
echo "⚖️  Applying scaling configurations..."
kubectl apply -f manifests/10-hpa.yaml
kubectl apply -f manifests/11-vpa.yaml

echo "✅ Deployment completed!"

# Verify deployment
echo ""
echo "📊 Deployment Status:"
kubectl get all -n $NAMESPACE

echo ""
echo "🔍 Service Endpoints:"
kubectl get svc -n $NAMESPACE
```

### Rolling Updates

```bash
# Update deployment with new image
kubectl set image deployment/product-service product-service=ecommerce/product-service:v1.1.0 -n ecommerce-production

# Watch rollout status
kubectl rollout status deployment/product-service -n ecommerce-production

# View rollout history
kubectl rollout history deployment/product-service -n ecommerce-production

# Rollback if needed
kubectl rollout undo deployment/product-service -n ecommerce-production

# Rollback to specific revision
kubectl rollout undo deployment/product-service --to-revision=2 -n ecommerce-production
```

### Blue-Green Deployment

```yaml
# manifests/blue-green/product-service-blue.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: product-service-blue
  namespace: ecommerce-production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: product-service
      version: blue
  template:
    metadata:
      labels:
        app: product-service
        version: blue
    spec:
      containers:
      - name: product-service
        image: ecommerce/product-service:v1.0.0
---
# manifests/blue-green/product-service-green.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: product-service-green
  namespace: ecommerce-production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: product-service
      version: green
  template:
    metadata:
      labels:
        app: product-service
        version: green
    spec:
      containers:
      - name: product-service
        image: ecommerce/product-service:v1.1.0
```

Switch traffic:
```bash
# Switch service to green
kubectl patch service product-service -p '{"spec":{"selector":{"version":"green"}}}' -n ecommerce-production
```

### Canary Deployment

```yaml
# Using Istio for canary deployment
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: product-service-vs
  namespace: ecommerce-production
spec:
  hosts:
  - product-service
  http:
  - route:
    - destination:
        host: product-service
        subset: stable
      weight: 90
    - destination:
        host: product-service
        subset: canary
      weight: 10
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: product-service-dr
  namespace: ecommerce-production
spec:
  host: product-service
  subsets:
  - name: stable
    labels:
      version: stable
  - name: canary
    labels:
      version: canary
```

---

## Management & Operations

### Resource Management

```bash
# View resource usage
kubectl top nodes
kubectl top pods -n ecommerce-production

# View resource quotas
kubectl get quota -n ecommerce-production

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
    services: "20"
    secrets: "50"
    configmaps: "50"
EOF
```

### Network Policies

```yaml
# manifests/14-network-policies.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: ecommerce-production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-ingress
  namespace: ecommerce-production
spec:
  podSelector:
    matchLabels:
      app: frontend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 80
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-backend-ingress
  namespace: ecommerce-production
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: api-gateway
    ports:
    - protocol: TCP
      port: 8080
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-database-ingress
  namespace: ecommerce-production
spec:
  podSelector:
    matchLabels:
      app: postgres
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: backend
    ports:
    - protocol: TCP
      port: 5432
```

### Pod Security Standards

```yaml
# manifests/15-pod-security.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ecommerce-production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

---

## Monitoring & Observability

### Prometheus Stack Installation

```bash
# Install Prometheus Operator
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace ecommerce-monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
```

### Service Monitors

```yaml
# manifests/16-service-monitors.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: product-service-monitor
  namespace: ecommerce-production
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: product-service
  namespaceSelector:
    matchNames:
    - ecommerce-production
  endpoints:
  - port: http
    interval: 15s
    path: /metrics
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: order-service-monitor
  namespace: ecommerce-production
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: order-service
  namespaceSelector:
    matchNames:
    - ecommerce-production
  endpoints:
  - port: http
    interval: 15s
    path: /metrics
```

### Grafana Dashboards

```yaml
# manifests/17-grafana-dashboard.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-ecommerce
  namespace: ecommerce-monitoring
  labels:
    grafana_dashboard: "1"
data:
  ecommerce-overview.json: |
    {
      "dashboard": {
        "title": "E-Commerce Platform Overview",
        "panels": [
          {
            "title": "Request Rate",
            "type": "graph",
            "targets": [
              {
                "expr": "sum(rate(http_requests_total{namespace=\"ecommerce-production\"}[5m])) by (service)"
              }
            ]
          },
          {
            "title": "Error Rate",
            "type": "graph",
            "targets": [
              {
                "expr": "sum(rate(http_requests_total{namespace=\"ecommerce-production\",status=~\"5..\"}[5m])) by (service)"
              }
            ]
          },
          {
            "title": "Pod CPU Usage",
            "type": "graph",
            "targets": [
              {
                "expr": "sum(rate(container_cpu_usage_seconds_total{namespace=\"ecommerce-production\"}[5m])) by (pod)"
              }
            ]
          },
          {
            "title": "Pod Memory Usage",
            "type": "graph",
            "targets": [
              {
                "expr": "sum(container_memory_usage_bytes{namespace=\"ecommerce-production\"}) by (pod)"
              }
            ]
          }
        ]
      }
    }
```

### Alerting Rules

```yaml
# manifests/18-prometheus-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: ecommerce-alerts
  namespace: ecommerce-monitoring
  labels:
    release: prometheus
spec:
  groups:
  - name: ecommerce.rules
    rules:
    - alert: HighErrorRate
      expr: |
        sum(rate(http_requests_total{namespace="ecommerce-production",status=~"5.."}[5m])) 
        / sum(rate(http_requests_total{namespace="ecommerce-production"}[5m])) > 0.05
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "High error rate detected"
        description: "Error rate is {{ $value | humanizePercentage }} in the last 5 minutes"
    - alert: PodNotReady
      expr: |
        kube_pod_status_ready{namespace="ecommerce-production",condition="true"} == 0
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Pod {{ $labels.pod }} is not ready"
    - alert: HighMemoryUsage
      expr: |
        sum(container_memory_usage_bytes{namespace="ecommerce-production"}) by (pod) 
        / sum(container_spec_memory_limit_bytes{namespace="ecommerce-production"}) by (pod) > 0.9
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "High memory usage on {{ $labels.pod }}"
    - alert: HighCPUUsage
      expr: |
        sum(rate(container_cpu_usage_seconds_total{namespace="ecommerce-production"}[5m])) by (pod) 
        / sum(container_spec_cpu_quota{namespace="ecommerce-production"}/container_spec_cpu_period{namespace="ecommerce-production"}) by (pod) > 0.9
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "High CPU usage on {{ $labels.pod }}"
```

---

## Best Practices

### 1. Resource Management
- Always set resource requests and limits
- Use LimitRanges to set default resources
- Implement ResourceQuotas per namespace
- Regularly review and adjust resource allocations

### 2. High Availability
- Run minimum 3 replicas for critical services
- Use PodDisruptionBudgets
- Spread pods across nodes and zones
- Implement proper health checks

### 3. Security
- Use Pod Security Standards
- Implement NetworkPolicies
- Rotate secrets regularly
- Scan images for vulnerabilities
- Use read-only root filesystems

### 4. Scaling
- Start with HPA based on CPU/memory
- Add custom metrics for business-specific scaling
- Use VPA for right-sizing recommendations
- Implement cluster autoscaling

### 5. Observability
- Implement structured logging
- Expose metrics endpoints
- Use distributed tracing
- Set up meaningful alerts
- Create operational dashboards

### 6. GitOps
- Store all manifests in version control
- Use tools like ArgoCD or Flux
- Implement CI/CD pipelines
- Automate testing of manifests

---

## Troubleshooting

### Common Commands

```bash
# Check pod status
kubectl get pods -n ecommerce-production
kubectl get pods -n ecommerce-production -o wide

# Describe pod for events
kubectl describe pod <pod-name> -n ecommerce-production

# View pod logs
kubectl logs <pod-name> -n ecommerce-production
kubectl logs <pod-name> -c <container-name> -n ecommerce-production
kubectl logs -f <pod-name> -n ecommerce-production

# Execute into pod
kubectl exec -it <pod-name> -n ecommerce-production -- /bin/sh

# Check service endpoints
kubectl get endpoints <service-name> -n ecommerce-production

# Test service connectivity
kubectl run test --rm -it --image=busybox --restart=Never -- nc <service-name> <port>

# Check HPA status
kubectl get hpa -n ecommerce-production
kubectl describe hpa <hpa-name> -n ecommerce-production

# Check events
kubectl get events -n ecommerce-production --sort-by='.lastTimestamp'
```

### Debugging Tools

```bash
# Install kubectl plugins
kubectl krew install ctx
kubectl krew install ns
kubectl krew install debug-shell
kubectl krew install popeye

# Run debugging pod
kubectl debug -it <pod-name> -n ecommerce-production --image=busybox

# Check network policies
kubectl get networkpolicy -n ecommerce-production

# Analyze cluster health
popeye -n ecommerce-production
```

---

## Conclusion

This guide covered the complete lifecycle of deploying and managing a microservices e-commerce platform on Kubernetes, including:

✅ **Core Concepts**: Pods, Deployments, StatefulSets, Services
✅ **Scaling**: HPA, VPA, Cluster Autoscaler, KEDA
✅ **Security**: NetworkPolicies, Pod Security Standards, Secrets management
✅ **Observability**: Prometheus, Grafana, alerting, dashboards
✅ **Best Practices**: HA, resource management, GitOps

For production deployments, consider adding:
- Service mesh (Istio/Linkerd)
- Advanced CI/CD pipelines
- Disaster recovery procedures
- Cost optimization strategies
- Compliance and audit logging

---

**Repository**: https://github.com/417buddy/advanced-kubernetes-guide
**Author**: DevOps Engineer
**License**: MIT