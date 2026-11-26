#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="practise-lab-cluster"
NAMESPACE="lab-ns"

echo ""
echo "1/9 Creating kind cluster '${CLUSTER_NAME}'..."
kind delete cluster --name "${CLUSTER_NAME}" 2>/dev/null || true
kind create cluster --config kind-config.yaml

echo ""
echo "2/9 Building Docker images..."
docker build -t mern-backend:v2 ./backend
docker build -t mern-frontend:v2 ./frontend

echo ""
echo "3/9 Loading images into '${CLUSTER_NAME}'..."
kind load docker-image mern-backend:v2 mern-frontend:v2 --name "${CLUSTER_NAME}"

echo ""
echo "4/9 Creating namespace and changing the context"
kubectl apply -f namespace.yaml
kubectl config set-context --current --namespace="${NAMESPACE}"

echo ""
echo "5/9 Installing Calico and applying zero-trust network policies..."
kubectl apply -f addons/calico/calico.yaml
kubectl rollout status daemonset/calico-node -n kube-system --timeout=180s
kubectl rollout status deployment/calico-kube-controllers -n kube-system --timeout=180s
kubectl apply -f network-policies.yaml

echo ""
echo "6/9 Installing Ingress-NGINX controller..."
kubectl apply -f deploy.yaml
kubectl patch deployment ingress-nginx-controller -n ingress-nginx \
  --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/nodeSelector/ingress-ready", "value": "true"}]'
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=180s

echo ""
echo "7/9 Installing Metrics Server..."
kubectl apply -f addons/metrics-server/components.yaml
kubectl patch deployment metrics-server -n kube-system \
  --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
kubectl rollout status deployment/metrics-server -n kube-system --timeout=90s

echo ""
echo "8/9 Deploying MERN manifests..."
kubectl apply -f config-secret.yaml
kubectl apply -f rbac.yaml
kubectl apply -f mongo.yaml
kubectl apply -f backend.yaml
kubectl apply -f frontend.yaml
kubectl apply -f ingress.yaml
kubectl apply -f hpa.yaml

echo ""
echo "9/9 Waiting for application pods to be ready..."
kubectl wait --for=condition=ready pod -l app=mongo --timeout=90s
kubectl wait --for=condition=ready pod -l app=backend --timeout=90s
kubectl wait --for=condition=ready pod -l app=frontend --timeout=90s

echo ""
echo "Done! Your MERN app is live at: http://localhost"
