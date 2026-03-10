#!/bin/bash

echo "=== Setting up Monitoring Stack ==="
echo ""

# Add Helm repos
echo "Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm repo update

# Create monitoring namespace
echo "Creating monitoring namespace..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Install Prometheus
echo "Installing Prometheus..."
helm upgrade --install prometheus prometheus-community/prometheus \
  --namespace monitoring \
  --values monitoring/prometheus-values.yaml \
  --wait

# Install Grafana
echo "Installing Grafana..."
helm upgrade --install grafana grafana/grafana \
  --namespace monitoring \
  --values monitoring/grafana-values.yaml \
  --wait

# Install Kubernetes Dashboard
echo "Installing Kubernetes Dashboard..."
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
  --namespace kubernetes-dashboard \
  --create-namespace \
  --set service.type=NodePort \
  --set service.nodePort=30002 \
  --wait

# Apply admin user for dashboard
kubectl apply -f monitoring/kubernetes-dashboard.yaml

echo ""
echo "=== Monitoring Stack Installed ==="
echo ""
echo "📊 Prometheus: http://localhost:30003"
echo "   kubectl port-forward -n monitoring svc/prometheus-server 30003:80"
echo ""
echo "📈 Grafana: http://localhost:30001"
echo "   Username: admin"
echo "   Password: admin"
echo ""
echo "🎛️  Kubernetes Dashboard: http://localhost:30002"
echo "   Get token with: kubectl -n kubernetes-dashboard create token admin-user"
echo ""
echo "To access services:"
echo "  kubectl port-forward -n monitoring svc/prometheus-server 9090:80"
echo "  kubectl port-forward -n monitoring svc/grafana 3001:80"
echo ""
