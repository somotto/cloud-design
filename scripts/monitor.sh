#!/bin/bash

NAMESPACE="orchestrator"

echo "=== Orchestrator Monitoring Dashboard ==="
echo ""

echo "📊 Cluster Nodes:"
kubectl get nodes
echo ""

echo "🚀 Pods Status:"
kubectl get pods -n $NAMESPACE
echo ""

echo "📦 Services:"
kubectl get svc -n $NAMESPACE
echo ""

echo "📈 Horizontal Pod Autoscalers:"
kubectl get hpa -n $NAMESPACE
echo ""

echo "💾 Persistent Volume Claims:"
kubectl get pvc -n $NAMESPACE
echo ""

echo "🔐 Secrets:"
kubectl get secrets -n $NAMESPACE
echo ""

echo "⚙️  ConfigMaps:"
kubectl get configmap -n $NAMESPACE
echo ""

echo "📊 Resource Usage (if metrics-server is available):"
kubectl top pods -n $NAMESPACE 2>/dev/null || echo "Metrics not available. Install metrics-server for resource usage."
echo ""

echo "🔍 Recent Events:"
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -10
echo ""

echo "=== Quick Commands ==="
echo "Watch pods: kubectl get pods -n $NAMESPACE -w"
echo "View logs: kubectl logs -f <pod-name> -n $NAMESPACE"
echo "Describe pod: kubectl describe pod <pod-name> -n $NAMESPACE"
echo "Port-forward API: kubectl port-forward svc/api-gateway 3000:3000 -n $NAMESPACE"
echo "Port-forward RabbitMQ UI: kubectl port-forward svc/billing-queue 15672:15672 -n $NAMESPACE"
