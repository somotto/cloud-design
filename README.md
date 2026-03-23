# Cloud-Design: Microservices on AWS EKS

A cloud-native microservices application for movie inventory and billing management, deployed on AWS EKS using Terraform, Docker, and Kubernetes. The project demonstrates scalable, secure, and observable infrastructure following modern DevOps practices.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [AWS Services Used](#aws-services-used)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
- [Deployment](#deployment)
  - [Local Development (k3d)](#local-development-k3d)
  - [AWS EKS Production](#aws-eks-production)
- [Microservices](#microservices)
- [Infrastructure as Code](#infrastructure-as-code)
- [Networking & Security](#networking--security)
- [Monitoring & Observability](#monitoring--observability)
- [Auto-Scaling](#auto-scaling)
- [Cost Management](#cost-management)
- [API Usage](#api-usage)
- [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
                          ┌──────────────────────────────────────────────────┐
                          │                    AWS VPC                        │
                          │  ┌─────────────────────────────────────────────┐ │
                          │  │           Public Subnets (ALB)               │ │
                          │  │  ┌──────────────────────────────────────┐   │ │
  Internet ──────────────────▶│  Application Load Balancer (HTTPS/443) │   │ │
                          │  │  └──────────────┬───────────────────────┘   │ │
                          │  └─────────────────│───────────────────────────┘ │
                          │                    │                              │
                          │  ┌─────────────────▼───────────────────────────┐ │
                          │  │           Private Subnets (EKS Nodes)        │ │
                          │  │                                               │ │
                          │  │   ┌─────────────────────────────────────┐    │ │
                          │  │   │         orchestrator namespace        │    │ │
                          │  │   │                                       │    │ │
                          │  │   │  ┌──────────────┐                    │    │ │
                          │  │   │  │  API Gateway  │ :3000              │    │ │
                          │  │   │  │  (Deployment) │                    │    │ │
                          │  │   │  │  HPA: 1-5     │                    │    │ │
                          │  │   │  └──────┬────────┘                    │    │ │
                          │  │   │         │                              │    │ │
                          │  │   │    ┌────┴──────────────────────┐      │    │ │
                          │  │   │    │                           │      │    │ │
                          │  │   │    ▼ HTTP :8080         RabbitMQ msg  │    │ │
                          │  │   │  ┌──────────────┐             │      │    │ │
                          │  │   │  │ Inventory App │             ▼      │    │ │
                          │  │   │  │ (Deployment)  │  ┌──────────────┐ │    │ │
                          │  │   │  │ HPA: 1-5      │  │ billing-queue│ │    │ │
                          │  │   │  └──────┬────────┘  │ (StatefulSet)│ │    │ │
                          │  │   │         │ :5432      │  RabbitMQ    │ │    │ │
                          │  │   │         ▼            └──────┬───────┘ │    │ │
                          │  │   │  ┌──────────────┐          │ consume  │    │ │
                          │  │   │  │ inventory-db  │          ▼          │    │ │
                          │  │   │  │ (StatefulSet) │  ┌──────────────┐  │    │ │
                          │  │   │  │ PostgreSQL    │  │  Billing App │  │    │ │
                          │  │   │  │ PVC: 10Gi     │  │ (StatefulSet)│  │    │ │
                          │  │   │  └──────────────┘  └──────┬───────┘  │    │ │
                          │  │   │                           │ :5432     │    │ │
                          │  │   │                           ▼           │    │ │
                          │  │   │                   ┌──────────────┐   │    │ │
                          │  │   │                   │  billing-db  │   │    │ │
                          │  │   │                   │ (StatefulSet)│   │    │ │
                          │  │   │                   │  PostgreSQL  │   │    │ │
                          │  │   │                   │  PVC: 10Gi   │   │    │ │
                          │  │   │                   └──────────────┘   │    │ │
                          │  │   └───────────────────────────────────────┘    │ │
                          │  └─────────────────────────────────────────────┘ │
                          └──────────────────────────────────────────────────┘
```

### Design Decisions

**Stateless vs Stateful workloads**: API Gateway and Inventory App run as `Deployments` since they are stateless and benefit from horizontal scaling. Databases, RabbitMQ, and Billing App run as `StatefulSets` to guarantee stable network identities and persistent storage.

**Async billing via RabbitMQ**: The API Gateway publishes billing orders to a RabbitMQ queue instead of calling the Billing App directly. This decouples the two services, gives immediate responses to clients, and makes billing processing fault-tolerant and independently scalable.

**Private subnets for workloads**: EKS worker nodes live in private subnets with no direct internet exposure. Only the ALB in public subnets accepts inbound traffic, which is then forwarded to pods via IP target type.

**Separate databases per service**: Each service owns its database, following the database-per-service pattern. This prevents tight coupling and allows independent schema evolution.

---

## AWS Services Used

| Service | Purpose |
|---|---|
| EKS | Managed Kubernetes cluster for container orchestration |
| EC2 (t3.small) | Worker nodes, auto-scaled 1–4 nodes |
| EBS (gp2) | Persistent volumes for PostgreSQL and RabbitMQ |
| ECR | Private Docker image registry for all 5 services |
| ALB | Internet-facing load balancer, routes HTTPS to pods |
| VPC | Isolated network with public/private subnets across 2 AZs |
| NAT Gateway | Outbound internet access for private subnet nodes |
| AWS Secrets Manager | Stores database and RabbitMQ credentials |
| ACM | TLS certificate for HTTPS on the ALB |
| CloudWatch | EKS control plane logs (API, audit, authenticator, scheduler) |
| IAM (IRSA) | Fine-grained pod-level AWS permissions via OIDC |

---

## Project Structure

```
.
├── srcs/                        # Application source code
│   ├── api-gateway-app/         # API Gateway (Flask, port 3000)
│   ├── inventory-app/           # Inventory service (Flask, port 8080)
│   ├── billing-app/             # Billing consumer (Flask, port 5000)
│   ├── postgres-db/             # Custom PostgreSQL image
│   └── rabbitmq/                # Custom RabbitMQ image
├── manifests/                   # Kubernetes manifests (local k3d)
├── manifests/eks/               # Kubernetes manifests (AWS EKS)
├── terraform/
│   ├── environments/production/ # Root module — wires everything together
│   └── modules/
│       ├── vpc/                 # VPC, subnets, IGW, NAT, route tables
│       ├── eks/                 # EKS cluster, node group, OIDC, add-ons
│       ├── iam/                 # IRSA roles for EBS CSI and ALB controller
│       ├── ecr/                 # ECR repositories
│       └── secrets/             # AWS Secrets Manager entries
├── monitoring/                  # Prometheus, Grafana, AlertManager configs
├── scripts/                     # Automation scripts
│   ├── deploy-eks.sh            # Full end-to-end EKS deployment
│   ├── build-and-push.sh        # Build and push Docker images
│   ├── setup-monitoring.sh      # Install monitoring stack via Helm
│   ├── test-api.sh              # API smoke tests
│   └── load-test.sh             # Load testing
├── cloud/eks-deployment.md      # Manual EKS setup reference
├── docker-compose.yaml          # Local development with Docker Compose
└── orchestrator.sh              # Local k3d cluster management
```

---

## Prerequisites

### Tools

| Tool | Version | Install |
|---|---|---|
| AWS CLI | v2+ | [docs.aws.amazon.com](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) |
| Terraform | >= 1.5.0 | [terraform.io](https://developer.hashicorp.com/terraform/install) |
| kubectl | >= 1.29 | [kubernetes.io](https://kubernetes.io/docs/tasks/tools/) |
| Helm | v3+ | [helm.sh](https://helm.sh/docs/intro/install/) |
| Docker | v24+ | [docker.com](https://docs.docker.com/get-docker/) |
| eksctl | latest | [eksctl.io](https://eksctl.io/installation/) *(optional, for manual setup)* |

### AWS Permissions

Your IAM user or role needs permissions to manage: EKS, EC2, VPC, ECR, IAM, Secrets Manager, and CloudWatch. For a quick start, `AdministratorAccess` works; for production, scope it down to the specific services above.

```bash
# Verify your credentials are configured
aws sts get-caller-identity
```

---

## Configuration

### 1. Environment variables (local / Docker Compose)

```bash
cp .env.example .env
# Edit .env with your values
```

```env
INVENTORY_DB_USER=inv_user
INVENTORY_DB_PASSWORD=your_strong_password
INVENTORY_DB_NAME=inventory_db

BILLING_DB_USER=bill_user
BILLING_DB_PASSWORD=your_strong_password
BILLING_DB_NAME=billing_db

RABBITMQ_USER=rabbit_admin
RABBITMQ_PASSWORD=your_strong_password
RABBITMQ_QUEUE=billing_queue

RABBITMQ_PORT=5672
INVENTORY_APP_PORT=8080
BILLING_APP_PORT=5000
APIGATEWAY_PORT=3000
```

### 2. Terraform variables (AWS EKS)

```bash
cp terraform/environments/production/terraform.tfvars.example \
   terraform/environments/production/terraform.tfvars
# Edit terraform.tfvars — never commit this file
```

```hcl
aws_region   = "us-east-1"
project_name = "orchestrator"

# EKS cluster
cluster_version    = "1.29"
node_instance_type = "t3.small"
node_min_size      = 1
node_max_size      = 4
node_desired_size  = 2

# Networking
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b"]
private_subnets    = ["10.0.1.0/24", "10.0.2.0/24"]
public_subnets     = ["10.0.101.0/24", "10.0.102.0/24"]

# Secrets — use strong passwords
inventory_db_user     = "inv_user"
inventory_db_password = "CHANGE_ME"
inventory_db_name     = "inventory_db"

billing_db_user     = "bill_user"
billing_db_password = "CHANGE_ME"
billing_db_name     = "billing_db"

rabbitmq_user     = "rabbit_admin"
rabbitmq_password = "CHANGE_ME"
rabbitmq_queue    = "billing_queue"
```

> Credentials are stored in AWS Secrets Manager by Terraform and injected into pods as Kubernetes Secrets. They are never baked into images or committed to source control.

---

## Deployment

### Local Development (k3d)

Runs the full stack locally using k3d (Kubernetes in Docker) with a local image registry.

```bash
# 1. Create the k3d cluster and local registry
./orchestrator.sh create

# 2. Build and push images to the local registry
./scripts/build-and-push.sh

# 3. Apply Kubernetes manifests
kubectl apply -f manifests/

# 4. Wait for all pods to be ready
kubectl wait --for=condition=Ready pods --all -n orchestrator --timeout=300s

# 5. Run smoke tests
./scripts/test-api.sh
```

The API Gateway is available at `http://localhost:3000`.

To tear down:
```bash
./orchestrator.sh delete
```

### AWS EKS Production

The `deploy-eks.sh` script handles the full deployment pipeline end-to-end.

```bash
# Full deployment (Terraform + build + deploy)
./scripts/deploy-eks.sh

# Skip Terraform if infrastructure already exists
./scripts/deploy-eks.sh --skip-terraform

# Skip image build if images are already in ECR
./scripts/deploy-eks.sh --skip-build
```

What the script does, in order:

1. Validates all required tools and AWS credentials
2. Runs `terraform init && terraform apply` to provision VPC, EKS, IAM, ECR, and Secrets Manager
3. Updates `kubeconfig` for the new cluster
4. Builds Docker images and pushes them to ECR
5. Installs the AWS Load Balancer Controller via Helm
6. Installs the Kubernetes Metrics Server
7. Applies all manifests from `manifests/eks/`
8. Installs the monitoring stack (Prometheus + Grafana + AlertManager)

#### Manual step-by-step

If you prefer to run each step manually:

```bash
# Step 1 — Provision infrastructure
cd terraform/environments/production
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Step 2 — Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name orchestrator-cluster

# Step 3 — Build and push images to ECR
ECR_REGISTRY=$(terraform output -raw ecr_registry)
docker build -t ${ECR_REGISTRY}/orchestrator/api-gateway:latest srcs/api-gateway-app/
docker push ${ECR_REGISTRY}/orchestrator/api-gateway:latest
# ... repeat for each service

# Step 4 — Install AWS Load Balancer Controller
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=orchestrator-cluster

# Step 5 — Deploy application
kubectl apply -f manifests/eks/

# Step 6 — Set up monitoring
./scripts/setup-monitoring.sh

# Step 7 — Get the ALB endpoint
kubectl get ingress -n orchestrator
```

#### Verify deployment

```bash
# Check all pods are running
kubectl get pods -n orchestrator

# Check HPA status
kubectl get hpa -n orchestrator

# Get the ALB DNS name
kubectl get ingress -n orchestrator

# Run API smoke tests
./scripts/test-api.sh
```

The ALB takes 5–10 minutes to provision. Once ready, the API is accessible at the DNS name shown by `kubectl get ingress`.

#### Tear down

```bash
# Remove Kubernetes resources first (releases ALB)
kubectl delete -f manifests/eks/

# Destroy all AWS infrastructure
cd terraform/environments/production
terraform destroy
```

---

## Microservices

### API Gateway — port 3000

Entry point for all client requests. Routes `GET /api/movies` and `POST /api/movies` to the Inventory App, and sends billing orders to RabbitMQ for async processing.

### Inventory App — port 8080

Handles movie CRUD operations backed by PostgreSQL. Stateless — scales horizontally.

### Billing App — port 5000

Consumes messages from the RabbitMQ `billing_queue` and persists orders to the billing database. Runs as a single replica (single-consumer pattern) to avoid duplicate order processing.

### inventory-db — port 5432

PostgreSQL 13 instance for the inventory service. Backed by a 10Gi EBS volume.

### billing-db — port 5432

PostgreSQL 13 instance for the billing service. Backed by a 10Gi EBS volume.

### billing-queue (RabbitMQ) — ports 5672 / 15672

Message broker that decouples the API Gateway from the Billing App. Backed by a 5Gi EBS volume for message durability. The management UI is available on port 15672.

---

## Infrastructure as Code

All AWS resources are provisioned with Terraform. The production environment at `terraform/environments/production/` composes four reusable modules:

### `modules/vpc`
- VPC (`10.0.0.0/16`) with DNS support enabled
- 2 public subnets across `us-east-1a` and `us-east-1b` — tagged for ALB discovery
- 2 private subnets — tagged for EKS node placement
- Internet Gateway for public subnet routing
- NAT Gateways (one per AZ) for private subnet outbound traffic

### `modules/eks`
- EKS cluster (Kubernetes 1.29) with private and public endpoint access
- OIDC provider for IAM Roles for Service Accounts (IRSA)
- Managed node group (`t3.medium`, 1–4 nodes) in private subnets
- CoreDNS, kube-proxy, and VPC CNI add-ons
- CloudWatch log group with 30-day retention for all control plane log types

### `modules/iam`
- EBS CSI Driver IRSA role — allows pods to provision EBS volumes
- AWS Load Balancer Controller IRSA role — allows the controller to manage ALBs
- Both roles use OIDC federation so only the specific service accounts can assume them

### `modules/secrets`
- AWS Secrets Manager entries for database credentials and RabbitMQ credentials
- 7-day recovery window to prevent accidental permanent deletion

### `modules/ecr`
- Private ECR repositories for: `api-gateway`, `inventory-app`, `billing-app`, `postgres-db`, `rabbitmq`

---

## Networking & Security

### VPC layout

```
VPC: 10.0.0.0/16
├── Public subnets (ALB)
│   ├── 10.0.101.0/24  us-east-1a
│   └── 10.0.102.0/24  us-east-1b
└── Private subnets (EKS nodes)
    ├── 10.0.1.0/24    us-east-1a
    └── 10.0.2.0/24    us-east-1b
```

### Kubernetes Network Policies

Each pod is restricted to only the connections it needs:

| Pod | Allowed inbound | Allowed outbound |
|---|---|---|
| api-gateway | ALB (any) on :3000 | inventory-app :8080, billing-queue :5672, DNS |
| inventory-app | api-gateway on :8080 | inventory-db :5432, DNS |
| billing-app | — | billing-db :5432, billing-queue :5672, DNS |
| inventory-db | inventory-app on :5432 | — |
| billing-db | billing-app on :5432 | — |
| billing-queue | api-gateway :5672, billing-app :5672, any :15672 | — |

### TLS / HTTPS

The ALB Ingress is configured to:
- Listen on both HTTP (80) and HTTPS (443)
- Redirect all HTTP traffic to HTTPS
- Use an ACM certificate (set `alb.ingress.kubernetes.io/certificate-arn` in `manifests/eks/09-ingress.yaml`)

### Secrets management

Credentials flow: `terraform.tfvars` → AWS Secrets Manager → Kubernetes Secrets → pod environment variables. No credentials are stored in Docker images or committed to source control.

### IRSA (IAM Roles for Service Accounts)

The EBS CSI Driver and AWS Load Balancer Controller each have dedicated IAM roles scoped to their specific Kubernetes service accounts via OIDC federation. No node-level IAM permissions are used.

---

## Monitoring & Observability

Install the full monitoring stack:

```bash
./scripts/setup-monitoring.sh
```

This installs Prometheus, Grafana, and AlertManager into the `monitoring` namespace via Helm.

### Prometheus

- Scrape interval: 15 seconds
- Retention: 15 days
- Storage: 8Gi persistent volume
- Scrapes metrics from all pods and nodes via `nodeExporter`

### Grafana

- Storage: 5Gi persistent volume
- Pre-configured Prometheus datasource
- Pre-loaded dashboards: Kubernetes Cluster overview and Pod-level metrics
- Access: `kubectl port-forward svc/grafana 3001:80 -n monitoring`
- Default credentials: `admin` / `admin` (change on first login)

### AlertManager

Alerts are grouped by `alertname`, `cluster`, and `service` with the following rules:

| Alert | Condition | Severity |
|---|---|---|
| PodDown | Pod unreachable for > 1 min | critical |
| HighCPUUsage | CPU > 80% for 5 min | warning |
| HighMemoryUsage | Memory > 90% of limit for 5 min | warning |
| PodRestartingTooOften | Restart rate > 0 over 15 min | warning |
| PVCAlmostFull | PVC usage > 80% | warning |

Critical and warning alerts route to separate webhook receivers — configure the webhook URLs in `monitoring/alertmanager-config.yaml` to point to your notification system (Slack, PagerDuty, etc.).

### CloudWatch

EKS control plane logs (API server, audit, authenticator, controller manager, scheduler) are shipped to CloudWatch automatically with a 30-day retention policy.

### Health checks

Every pod has liveness and readiness probes:
- Applications: HTTP GET on their respective API paths
- PostgreSQL: `pg_isready` exec probe
- RabbitMQ: `rabbitmq-diagnostics ping` exec probe

---

## Auto-Scaling

### Horizontal Pod Autoscaler (HPA)

| Service | Min replicas | Max replicas | Scale-up trigger |
|---|---|---|---|
| api-gateway | 1 | 5 | CPU > 60% or Memory > 70% |
| inventory-app | 1 | 5 | CPU > 60% or Memory > 70% |

The Metrics Server (installed by `deploy-eks.sh`) provides the resource metrics HPA relies on.

### Cluster Autoscaler

The EKS node group is configured with:
- Min: 1 node
- Max: 4 nodes
- Desired: 2 nodes

The Cluster Autoscaler (installed via `manifests/eks/11-cluster-autoscaler.yaml`) watches for unschedulable pods and provisions new nodes automatically. Nodes are tagged with `k8s.io/cluster-autoscaler/enabled` and `k8s.io/cluster-autoscaler/orchestrator-cluster` for discovery.

### Load testing

```bash
./scripts/load-test.sh
```

Watch HPA react in real time:

```bash
kubectl get hpa -n orchestrator -w
```

---

## Cost Management

Estimated monthly cost for the default configuration (`t3.medium` × 2 nodes, `us-east-1`):

| Resource | Estimated cost |
|---|---|
| EKS cluster | ~$73/month |
| EC2 nodes (2× t3.medium) | ~$60/month |
| NAT Gateways (2×) | ~$65/month |
| EBS volumes (~25Gi total) | ~$2.50/month |
| ALB | ~$20/month |
| ECR storage | ~$1/month |
| Secrets Manager (3 secrets) | ~$1.20/month |
| **Approximate total** | **~$220/month** |

To reduce costs:
- Use `t3.small` nodes for non-production workloads
- Use a single NAT Gateway (reduces AZ redundancy but cuts NAT cost in half)
- Set `node_min_size = 0` and scale to zero when idle
- Delete the cluster when not in use: `terraform destroy`
- Set up AWS Budgets alerts to get notified before spending exceeds your threshold

---

## API Usage

All requests go through the API Gateway at port 3000 (or the ALB DNS name in production).

```bash
# Get all movies
curl http://<ALB_DNS>/api/movies

# Add a movie
curl -X POST http://<ALB_DNS>/api/movies \
  -H "Content-Type: application/json" \
  -d '{"title": "Inception", "director": "Christopher Nolan", "year": 2010}'

# Create a billing order (sent async via RabbitMQ)
curl -X POST http://<ALB_DNS>/api/billing \
  -H "Content-Type: application/json" \
  -d '{"user_id": "123", "movie_id": "456", "amount": 9.99}'
```

Run the full test suite:

```bash
./scripts/test-api.sh
```

---

## Troubleshooting

**Pods stuck in `Pending`**
```bash
kubectl describe pod <pod-name> -n orchestrator
# Usually a PVC provisioning issue or insufficient node capacity
```

**ALB not provisioning**
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
# Check IAM permissions for the ALB controller service account
```

**Database connection errors**
```bash
kubectl get secret db-secrets -n orchestrator -o yaml
# Verify secrets were created correctly by Terraform
```

**Images not pulling**
```bash
kubectl describe pod <pod-name> -n orchestrator | grep -A5 Events
# Ensure ECR_REGISTRY in manifests was replaced by deploy-eks.sh
# Verify node IAM role has AmazonEC2ContainerRegistryReadOnly policy
```

**Check all resource status**
```bash
kubectl get all -n orchestrator
kubectl get pvc -n orchestrator
kubectl get hpa -n orchestrator
kubectl get ingress -n orchestrator
```
