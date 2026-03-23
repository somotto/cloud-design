#!/bin/bash
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-orchestrator-cluster}"
PROJECT_NAME="${PROJECT_NAME:-orchestrator}"
SKIP_TERRAFORM=false
SKIP_BUILD=false

for arg in "$@"; do
  case $arg in
    --skip-terraform) SKIP_TERRAFORM=true ;;
    --skip-build)     SKIP_BUILD=true ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo -e "\n\033[1;34m▶ $*\033[0m"; }
ok()   { echo -e "\033[1;32m✔ $*\033[0m"; }
die()  { echo -e "\033[1;31m✘ $*\033[0m" >&2; exit 1; }

check_deps() {
  log "Checking dependencies..."
  for cmd in aws terraform kubectl helm docker; do
    command -v "$cmd" &>/dev/null || die "$cmd is not installed"
  done
  aws sts get-caller-identity &>/dev/null || die "AWS credentials not configured"
  ok "All dependencies present"
}

# ── Step 1: Terraform ─────────────────────────────────────────────────────────
run_terraform() {
  log "Provisioning AWS infrastructure with Terraform..."
  cd "${PROJECT_ROOT}/terraform/environments/production"

  [ -f terraform.tfvars ] || die "terraform.tfvars not found. Copy terraform.tfvars.example and fill in values."

  terraform init
  terraform plan -out=tfplan
  terraform apply tfplan

  # Export outputs for use in later steps
  ECR_REGISTRY=$(terraform output -raw ecr_registry_url)
  export ECR_REGISTRY

  cd - > /dev/null
  ok "Terraform apply complete"
}

# ── Step 2: Configure kubectl ─────────────────────────────────────────────────
configure_kubectl() {
  log "Configuring kubectl for EKS..."
  aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
  kubectl get nodes || die "Cannot connect to cluster"
  ok "kubectl configured"
}

# ── Step 3: Build & push images to ECR ───────────────────────────────────────
build_and_push() {
  log "Building and pushing Docker images to ECR..."

  ECR_REGISTRY="${ECR_REGISTRY:-$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${AWS_REGION}.amazonaws.com}"

  # ECR login
  aws ecr get-login-password --region "$AWS_REGION" \
    | docker login --username AWS --password-stdin "$ECR_REGISTRY"

  build_push() {
    local name=$1 context=$2
    local tag="${ECR_REGISTRY}/${PROJECT_NAME}/${name}:latest"
    echo "  Building ${name}..."
    docker build -t "$tag" "$context"
    docker push "$tag"
  }

  build_push "postgres-db"    srcs/postgres-db
  build_push "rabbitmq"       srcs/rabbitmq
  build_push "inventory-app"  srcs/inventory-app
  build_push "billing-app"    srcs/billing-app
  build_push "api-gateway"    srcs/api-gateway-app

  ok "All images pushed to ECR"
}

# ── Step 4: Install AWS Load Balancer Controller ──────────────────────────────
install_alb_controller() {
  log "Installing AWS Load Balancer Controller..."

  ALB_ROLE_ARN=$(aws iam get-role \
    --role-name "${PROJECT_NAME}-alb-controller-role" \
    --query 'Role.Arn' --output text 2>/dev/null || echo "")

  [ -z "$ALB_ROLE_ARN" ] && die "ALB controller IAM role not found. Run Terraform first."

  helm repo add eks https://aws.github.io/eks-charts
  helm repo update

  helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    --namespace kube-system \
    --set clusterName="$CLUSTER_NAME" \
    --set serviceAccount.create=true \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$ALB_ROLE_ARN" \
    --wait

  ok "AWS Load Balancer Controller installed"
}

# ── Step 5: Deploy application manifests ─────────────────────────────────────
deploy_manifests() {
  log "Deploying application to EKS..."

  ECR_REGISTRY="${ECR_REGISTRY:-$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${AWS_REGION}.amazonaws.com}"

  # Substitute ECR_REGISTRY placeholder in manifests and apply
  TMPDIR=$(mktemp -d)
  trap "rm -rf $TMPDIR" EXIT

  for f in manifests/eks/*.yaml; do
    sed "s|ECR_REGISTRY|${ECR_REGISTRY}|g" "$f" > "${TMPDIR}/$(basename $f)"
  done

  # Also substitute cluster name in cluster-autoscaler manifest
  AUTOSCALER_ROLE_ARN=$(aws iam get-role \
    --role-name "${PROJECT_NAME}-cluster-autoscaler-role" \
    --query 'Role.Arn' --output text 2>/dev/null || echo "ROLE_NOT_FOUND")

  sed -i "s|CLUSTER_AUTOSCALER_ROLE_ARN|${AUTOSCALER_ROLE_ARN}|g" \
    "${TMPDIR}/11-cluster-autoscaler.yaml"
  sed -i "s|CLUSTER_NAME|${CLUSTER_NAME}|g" \
    "${TMPDIR}/11-cluster-autoscaler.yaml"

  kubectl apply -f "${TMPDIR}/"

  log "Waiting for deployments to be ready..."
  kubectl rollout status deployment/inventory-app -n orchestrator --timeout=300s
  kubectl rollout status deployment/api-gateway   -n orchestrator --timeout=300s

  ok "Application deployed"
}

# ── Step 6: Install metrics-server (required for HPA) ────────────────────────
install_metrics_server() {
  log "Installing metrics-server..."
  helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
  helm repo update
  helm upgrade --install metrics-server metrics-server/metrics-server \
    --namespace kube-system \
    --set args[0]="--kubelet-insecure-tls" \
    --wait
  ok "metrics-server installed"
}

# ── Step 7: Setup monitoring ──────────────────────────────────────────────────
setup_monitoring() {
  log "Setting up monitoring stack..."
  ./scripts/setup-monitoring.sh
  ok "Monitoring stack deployed"
}

# ── Step 8: Print summary ─────────────────────────────────────────────────────
print_summary() {
  log "Deployment complete. Getting endpoints..."

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  ORCHESTRATOR — AWS EKS DEPLOYMENT SUMMARY"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  ALB_URL=$(kubectl get ingress orchestrator-ingress -n orchestrator \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending...")

  echo "  API Gateway:  http://${ALB_URL}/api/movies"
  echo ""
  echo "  Cluster:      ${CLUSTER_NAME}"
  echo "  Region:       ${AWS_REGION}"
  echo ""
  echo "  Pods:"
  kubectl get pods -n orchestrator
  echo ""
  echo "  HPA status:"
  kubectl get hpa -n orchestrator
  echo ""
  echo "  Monitoring:"
  echo "    kubectl port-forward -n monitoring svc/grafana 3001:80"
  echo "    kubectl port-forward -n monitoring svc/prometheus-server 9090:80"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ── Main ──────────────────────────────────────────────────────────────────────
check_deps

if [ "$SKIP_TERRAFORM" = false ]; then
  run_terraform
fi

configure_kubectl

if [ "$SKIP_BUILD" = false ]; then
  build_and_push
fi

install_alb_controller
install_metrics_server
deploy_manifests
setup_monitoring
print_summary
