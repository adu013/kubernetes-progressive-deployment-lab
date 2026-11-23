# Kubernetes Progressive Hands-On Lab

A hands-on Kubernetes project deploying a full-stack **MERN (MongoDB, Express, React/Nginx, Node.js)** application onto a multi-node **kind (Kubernetes in Docker)** cluster, built incrementally across feature branches.

---

## Architecture

* **Flow:** Browser ──► Ingress-NGINX ──► Frontend/Backend Services ──► MongoDB StatefulSet.

---

## Quick Start

### 1. Initialize the `kind` Cluster
```bash
kind create cluster --config kind-config.yaml
```

### 2. Build the Local Docker Images
```bash
docker build -t mern-backend:v1 ./backend
docker build -t mern-frontend:v1 ./frontend
```

### 3. Load Images into the `kind` Cluster
```bash
kind load docker-image mern-backend:v1 mern-frontend:v1 --name practise-lab-cluster
```

### 4. Install the Ingress-NGINX Controller

Apply the Ingress-NGINX manifest:
```bash
kubectl apply -f deploy.yaml
```

> **Note (`ingress-ready` NodeSelector):** On a multi-node `kind` cluster, the controller pod must run on the `control-plane` node where ports `80` and `443` are mapped. Line **524** in `deploy.yaml` has `# ingress-ready: "true"` commented out under `nodeSelector`. You can either **uncomment line 524** before applying `deploy.yaml`, **or** patch the live Deployment afterward:

```bash
kubectl patch deployment ingress-nginx-controller -n ingress-nginx \
  --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/nodeSelector/ingress-ready", "value": "true"}]'
```

Wait for the controller pod to become ready:
```bash
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s
```

### 5. Deploy the Application Manifests
```bash
kubectl apply -f config-secrets.yaml
kubectl apply -f mongo.yaml
kubectl apply -f backend.yaml
kubectl apply -f frontend.yaml
kubectl apply -f ingress.yaml
```

### 6. Verify & Access the App
```bash
kubectl get statefulset,pods,svc,pvc,ingress
```
Open **`http://localhost`** in your browser once the pods are running and Ingress is active.

---

## Cleanup
```bash
kind delete cluster --name practise-lab-cluster
```

---

## Further Improvements

* **Health Probes & Resource Limits:** Configure `livenessProbe`, `readinessProbe`, and container resource requests/limits.
* **HPA Autoscaling:** Implement `HorizontalPodAutoscaler` metrics-based scaling for frontends and backends.
* **NetworkPolicies:** Enforce microsegmentation and strict zero-trust pod communication rules.
