# Orchestrator - Kubernetes Microservices Project

A complete microservices architecture deployed on Kubernetes (K3s) using k3d and Docker Desktop.

## Architecture Overview

This project deploys a movie inventory and billing system with the following components:

### Services
- **API Gateway** (api-gateway-app): Entry point for all requests, routes to inventory service and sends billing messages to RabbitMQ queue (Port 3000)
- **Inventory Service** (inventory-app): Manages movie catalog with PostgreSQL backend (Port 8080)
- **Billing Service** (billing-app): Processes orders from RabbitMQ queue and stores in PostgreSQL (Port 5000)

### Infrastructure
- **Inventory Database** (inventory-db): PostgreSQL StatefulSet for movie data
- **Billing Database** (billing-db): PostgreSQL StatefulSet for order data
- **Message Queue** (billing-queue): RabbitMQ StatefulSet for async order processing

### Kubernetes Features
- **Horizontal Pod Autoscaling**: API Gateway and Inventory App scale 1-3 replicas based on 60% CPU usage
- **StatefulSets**: Databases, RabbitMQ, and Billing App for persistent identity and storage
- **Persistent Volumes**: Data persists across pod restarts
- **Secrets Management**: Credentials stored securely in Kubernetes secrets
- **ConfigMaps**: Application configuration externalized

## Prerequisites

1. **Docker Desktop**: Install from [docker.com](https://www.docker.com/products/docker-desktop)
2. **k3d**: Lightweight Kubernetes distribution
   ```bash
   # macOS
   brew install k3d
   
   # Linux
   curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
   
   # Windows (PowerShell)
   choco install k3d
   ```

3. **kubectl**: Kubernetes CLI
   ```bash
   # macOS
   brew install kubectl
   
   # Linux
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   chmod +x kubectl
   sudo mv kubectl /usr/local/bin/
   
   # Windows (PowerShell)
   choco install kubernetes-cli
   ```

## Project Structure

```
.
├── manifests/                    # Kubernetes YAML manifests
│   ├── 00-namespace.yaml        # Namespace definition
│   ├── 01-secrets.yaml          # Database and RabbitMQ credentials
│   ├── 02-configmap.yaml        # Application configuration
│   ├── 03-inventory-db-statefulset.yaml
│   ├── 04-billing-db-statefulset.yaml
│   ├── 05-rabbitmq-statefulset.yaml
│   ├── 06-inventory-app-deployment.yaml
│   ├── 07-billing-app-statefulset.yaml
│   └── 08-api-gateway-deployment.yaml
├── scripts/
│   └── build-and-push.sh        # Build and push Docker images
├── srcs/                         # Application source code
│   ├── api-gateway-app/
│   ├── billing-app/
│   ├── inventory-app/
│   ├── postgres-db/
│   └── rabbitmq/
├── orchestrator.sh               # Cluster management script
└── README.md

```

## Setup Instructions

### 1. Create and Start the Cluster

```bash
# Create k3d cluster with registry
./orchestrator.sh create
```

This command:
- Creates a k3d cluster named "orchestrator-cluster"
- Sets up 1 server (master) node and 1 agent node
- Creates a local Docker registry at k3d-registry.localhost:5000
- Exposes API Gateway on port 3000
- Applies all Kubernetes manifests

### 2. Build and Push Docker Images

```bash
# Build all images and push to local registry
./scripts/build-and-push.sh
```

### 3. Verify Deployment

```bash
# Check cluster nodes
kubectl get nodes

# Check all pods
kubectl get pods -n orchestrator

# Check services
kubectl get svc -n orchestrator

# Check horizontal pod autoscalers
kubectl get hpa -n orchestrator
```

## Usage

### Cluster Management

```bash
# Start the cluster
./orchestrator.sh start

# Stop the cluster
./orchestrator.sh stop

# Check cluster status
./orchestrator.sh status

# Delete the cluster
./orchestrator.sh delete
```

### API Endpoints

The API Gateway is accessible at `http://localhost:3000`

#### Inventory Service (Movies)

```bash
# Get all movies
curl http://localhost:3000/api/movies

# Get movie by ID
curl http://localhost:3000/api/movies/1

# Create a movie
curl -X POST http://localhost:3000/api/movies \
  -H "Content-Type: application/json" \
  -d '{"title": "Inception", "description": "A mind-bending thriller"}'

# Update a movie
curl -X PUT http://localhost:3000/api/movies/1 \
  -H "Content-Type: application/json" \
  -d '{"title": "Inception", "description": "Updated description"}'

# Delete a movie
curl -X DELETE http://localhost:3000/api/movies/1

# Search movies by title
curl "http://localhost:3000/api/movies?title=Inception"
```

#### Billing Service (Orders)

```bash
# Send order to billing queue
curl -X POST http://localhost:3000/api/billing/ \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": 123,
    "number_of_items": 2,
    "total_amount": 29.99
  }'
```

### Monitoring

```bash
# Watch pod status
kubectl get pods -n orchestrator -w

# View logs
kubectl logs -n orchestrator -l app=api-gateway
kubectl logs -n orchestrator -l app=inventory-app
kubectl logs -n orchestrator -l app=billing-app

# Check HPA status
kubectl get hpa -n orchestrator -w

# Describe a pod
kubectl describe pod -n orchestrator <pod-name>
```

### Accessing Databases

```bash
# Port-forward to inventory database
kubectl port-forward -n orchestrator svc/inventory-db 5432:5432

# Port-forward to billing database
kubectl port-forward -n orchestrator svc/billing-db 5433:5432

# Connect with psql
psql -h localhost -p 5432 -U user01 -d inventory_db
```

### Accessing RabbitMQ Management UI

```bash
# Port-forward to RabbitMQ management interface
kubectl port-forward -n orchestrator svc/billing-queue 15672:15672

# Open in browser: http://localhost:15672
# Username: rabbit
# Password: password
```

## Configuration

### Secrets (manifests/01-secrets.yaml)

Credentials are stored as Kubernetes secrets:
- Database usernames and passwords
- RabbitMQ credentials
- Queue name

**Note**: In production, use proper secret management tools like HashiCorp Vault or sealed-secrets.

### ConfigMap (manifests/02-configmap.yaml)

Non-sensitive configuration:
- Service ports
- Application settings

### Scaling Configuration

- **API Gateway**: 1-3 replicas, scales at 60% CPU
- **Inventory App**: 1-3 replicas, scales at 60% CPU
- **Billing App**: StatefulSet with 1 replica (queue consumer)

## Troubleshooting

### Pods not starting

```bash
# Check pod events
kubectl describe pod -n orchestrator <pod-name>

# Check logs
kubectl logs -n orchestrator <pod-name>
```

### Images not pulling

```bash
# Verify registry is running
docker ps | grep registry

# Rebuild and push images
./scripts/build-and-push.sh
```

### Database connection issues

```bash
# Check if databases are ready
kubectl get pods -n orchestrator -l app=inventory-db
kubectl get pods -n orchestrator -l app=billing-db

# Check database logs
kubectl logs -n orchestrator inventory-db-0
kubectl logs -n orchestrator billing-db-0
```

### RabbitMQ connection issues

```bash
# Check RabbitMQ status
kubectl logs -n orchestrator billing-queue-0

# Verify queue is created
kubectl port-forward -n orchestrator svc/billing-queue 15672:15672
# Visit http://localhost:15672 and check queues
```

## Architecture Decisions

### Why StatefulSets?

- **Databases**: Require stable network identity and persistent storage
- **RabbitMQ**: Needs persistent storage for message durability
- **Billing App**: Single consumer pattern for queue processing

### Why Deployments?

- **API Gateway**: Stateless, can scale horizontally
- **Inventory App**: Stateless, can scale horizontally

### Horizontal Pod Autoscaling

- Automatically scales based on CPU usage
- Ensures availability during high load
- Cost-effective resource utilization

### Persistent Volumes

- Data survives pod restarts
- Enables pod migration across nodes
- Uses dynamic provisioning with PVCs

## Testing the System

### Load Testing

```bash
# Install hey (HTTP load generator)
# macOS: brew install hey
# Linux: go install github.com/rakyll/hey@latest

# Test API Gateway scaling
hey -z 60s -c 50 http://localhost:3000/api/movies

# Watch HPA scale up
kubectl get hpa -n orchestrator -w
```

### End-to-End Test

```bash
# 1. Create a movie
curl -X POST http://localhost:3000/api/movies \
  -H "Content-Type: application/json" \
  -d '{"title": "Test Movie", "description": "Test"}'

# 2. Verify movie exists
curl http://localhost:3000/api/movies

# 3. Send billing order
curl -X POST http://localhost:3000/api/billing/ \
  -H "Content-Type: application/json" \
  -d '{"user_id": 1, "number_of_items": 1, "total_amount": 9.99}'

# 4. Check billing app logs to verify order processing
kubectl logs -n orchestrator -l app=billing-app --tail=20
```

## Cleanup

```bash
# Delete the cluster and all resources
./orchestrator.sh delete

# Remove Docker images (optional)
docker rmi k3d-registry.localhost:5000/api-gateway:latest
docker rmi k3d-registry.localhost:5000/inventory-app:latest
docker rmi k3d-registry.localhost:5000/billing-app:latest
docker rmi k3d-registry.localhost:5000/inventory-db:latest
docker rmi k3d-registry.localhost:5000/billing-db:latest
docker rmi k3d-registry.localhost:5000/rabbitmq:latest
```

## Learning Outcomes

By completing this project, you will understand:

✅ Kubernetes cluster architecture and components  
✅ Deploying microservices with Deployments and StatefulSets  
✅ Horizontal Pod Autoscaling based on metrics  
✅ Persistent storage with PVCs and StatefulSets  
✅ Secret and ConfigMap management  
✅ Service discovery and networking  
✅ Container orchestration with k3d  
✅ Local development with Docker registry  

## Production Enhancements

This project includes production-ready features:

✅ **Health Checks & Readiness Probes** - Automatic failure recovery  
✅ **Network Policies** - Zero-trust security between services  
✅ **Ingress Controller** - Professional routing and load balancing  
✅ **Monitoring Stack** - Prometheus, Grafana, and Kubernetes Dashboard  
✅ **CI/CD Pipeline** - GitHub Actions for automated deployment  
✅ **Cloud Deployment Guides** - AWS EKS, Google GKE, Azure AKS  

See `ENHANCEMENTS.md` for detailed documentation.

### Quick Setup

```bash
# Enable monitoring
./scripts/setup-monitoring.sh

# Setup ingress
./scripts/setup-ingress.sh

# Monitor cluster
./scripts/monitor.sh
```

### Cloud Deployment

- AWS EKS: See `cloud/eks-deployment.md`