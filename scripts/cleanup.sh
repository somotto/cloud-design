#!/bin/bash

echo "Cleaning up Orchestrator resources..."

# Delete the k3d cluster
echo "Deleting k3d cluster..."
k3d cluster delete orchestrator-cluster

# Remove Docker images (optional)
read -p "Do you want to remove Docker images? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo "Removing Docker images..."
    docker rmi k3d-registry.localhost:5000/api-gateway:latest 2>/dev/null
    docker rmi k3d-registry.localhost:5000/inventory-app:latest 2>/dev/null
    docker rmi k3d-registry.localhost:5000/billing-app:latest 2>/dev/null
    docker rmi k3d-registry.localhost:5000/inventory-db:latest 2>/dev/null
    docker rmi k3d-registry.localhost:5000/billing-db:latest 2>/dev/null
    docker rmi k3d-registry.localhost:5000/rabbitmq:latest 2>/dev/null
    echo "Images removed"
fi

echo "Cleanup complete!"
