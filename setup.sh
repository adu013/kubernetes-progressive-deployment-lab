#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="practise-lab-cluster"
NAMESPACE="lab-ns"

echo "1/6 Creating kind cluster '${CLUSTER_NAME}'..."
kind delete cluster --name "${CLUSTER_NAME}" 2>/dev/null || true
kind create cluster --config kind-config.yaml

echo "2/6 Building Docker images..."
docker build -t mern-backend:v2 ./backend
docker build -t mern-frontend:v2 ./frontend

echo "3/6 Loading images into '${CLUSTER_NAME}'..."
kind load docker-image mern-backend:v2 mern-frontend:v2 --name "${CLUSTER_NAME}"

echo "4/7 Creating namespace and changing the context"
kubectl apply -f namespace.yaml
kubectl config set-context --current --namespace="${NAMESPACE}"

echo "5/7 Installing Ingress-NGINX controller..."
kubectl apply -f deploy.yaml
kubectl patch deployment ingress-nginx-controller -n ingress-nginx \
  --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/nodeSelector/ingress-ready", "value": "true"}]'
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=180s

echo "6/7 Deploying MERN manifests..."
kubectl apply -f config-secret.yaml -f mongo.yaml -f backend.yaml -f frontend.yaml -f ingress.yaml

echo "7/7 Waiting for application pods to be ready..."
kubectl wait --for=condition=ready pod -l app=mongo --timeout=90s
kubectl wait --for=condition=ready pod -l app=backend --timeout=90s
kubectl wait --for=condition=ready pod -l app=frontend --timeout=90s

echo "Done! Your MERN app is live at: http://localhost"
