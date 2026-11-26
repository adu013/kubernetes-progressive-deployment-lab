#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="practise-lab-cluster"

echo "1/2 Deleting kind cluster '${CLUSTER_NAME}'..."
if kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  kind delete cluster --name "${CLUSTER_NAME}"
  echo "Cluster '${CLUSTER_NAME}' deleted."
else
  echo "Cluster '${CLUSTER_NAME}' does not exist. Skipping."
fi

echo "2/2 Cleaning up dangling resources..."
docker rmi -f mern-backend:v2 mern-frontend:v2 2>/dev/null || true

echo "Teardown complete!"
