# Kubernetes Progressive Hands-On Lab

A hands-on Kubernetes project deploying a full-stack **MERN (MongoDB, Express, React/Nginx, Node.js)** application onto a multi-node **kind (Kubernetes in Docker)** cluster, built incrementally across feature branches.

---

## Architecture & Branch Progression

```text
Browser (http://localhost)
   │
   ▼  (Port 80 via kind extraPortMappings)
Ingress-NGINX Controller (Pinned to control-plane)
   ├─── Path: /      ──► frontend-service (ClusterIP:80) ──► Frontend Pods (2 replicas)
   └─── Path: /api   ──► backend-service (ClusterIP:5000) ──► Backend Pods (2 replicas)
                                                                 │
                                                                 ▼
                                                        mongo-service (Headless)
                                                                 │
                                                                 ▼
                                                        mongo-ss StatefulSet (mongo:8.3)
                                                           │                    ▲
                                                           ▼                    │ (mongodump)
                                              mongo-data PVC (1Gi)      mongo-backup-job / cronjob
                                                                                │
                                                                                ▼
                                                                      mongo-backup-pvc (1Gi)
```

| Branch | Milestone | Key Kubernetes Concepts |
| :--- | :--- | :--- |
| `01-feat/deployments-services-pv` | Base working MERN stack | `Deployment`, `Service` (`ClusterIP` & `NodePort`), `PersistentVolumeClaim` |
| `02-feat/configmaps-secrets` | Externalized configuration | `ConfigMap`, `Secret`, `envFrom` injection |
| `03-feat/statefulsets` | Stateful database layer | `StatefulSet`, Headless `Service` (`clusterIP: None`), `volumeClaimTemplates` |
| `04-feat/ingress` | Layer 7 HTTP routing | `Ingress`, `IngressClass` (`nginx`), `nodeSelector` (`ingress-ready: "true"`) |
| `05-feat/mongo-backup-job` | On-demand database backups | `Job`, `mongodump --archive --gzip`, dedicated backup `PersistentVolumeClaim` |
| `06-feat/mongo-backup-cronjob` | Scheduled backups & retention | `CronJob`, `concurrencyPolicy`, history limits, 5-archive retention pruning |
| `07-feat/namespace` | Workload & resource isolation | `Namespace` (`lab-ns`), `kubectl config set-context --current --namespace` |
| `08-feat/probes` | Health probes | `livenessProbe`, `readinessProbe` |
| `09-feat/resources` | Container resource bounds | `resources.requests` and `resources.limits` (CPU & memory) |
| `10-feat/hpa` | Horizontal Pod Autoscaling | `HorizontalPodAutoscaler` (`autoscaling/v2`), `metrics-server` |

---

## Quick Start

### 1. Initialize the `kind` Cluster
```bash
kind create cluster --config kind-config.yaml
```

### 2. Build the Local Docker Images
```bash
docker build -t mern-backend:v2 ./backend
docker build -t mern-frontend:v2 ./frontend
```

### 3. Load Images into the `kind` Cluster
```bash
kind load docker-image mern-backend:v2 mern-frontend:v2 --name practise-lab-cluster
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

### 5. Install `metrics-server` (for Autoscaling)
```bash
kubectl apply -f addons/metrics-server/components.yaml
kubectl patch deployment metrics-server -n kube-system \
  --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
kubectl rollout status deployment/metrics-server -n kube-system --timeout=90s
```
*(Note: `--kubelet-insecure-tls` is required on `kind` because local nodes use self-signed Kubelet TLS certificates.)*

### 5. Deploy the Application Manifests
```bash
kubectl apply -f namespace.yaml
kubectl config set-context --current --namespace=lab-ns
kubectl apply -f config-secret.yaml
kubectl apply -f mongo.yaml
kubectl apply -f backend.yaml
kubectl apply -f frontend.yaml
kubectl apply -f ingress.yaml
kubectl apply -f hpa.yaml
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

## MongoDB Backups (`Job` & `CronJob`)

### On-Demand Backup (`Job`)
```bash
kubectl apply -f mongo-backup-job.yaml -n=lab-ns
kubectl logs job/mongo-backup-job -n=lab-ns
```
*(Automatically cleans up the finished `Job` and `Pod` after 60 seconds via `ttlSecondsAfterFinished: 60` while preserving `.archive.gz` files on `mongo-backup-pvc`.)*

### Scheduled Backups (`CronJob`)
```bash
kubectl apply -f mongo-backup-cronjob.yaml -n=lab-ns
kubectl get cronjob,jobs,pods -n=lab-ns
```
*(Runs on a recurring schedule—`*/2 * * * *` for testing (change it to `0 2 * * *` for nightly backups). Automatically prunes older files to retain only the latest 5 archives.)*

---

## Horizontal Pod Autoscaling (`HPA`)

### Apply & Monitor Autoscalers
```bash
kubectl apply -f hpa.yaml -n=lab-ns
kubectl get hpa -n=lab-ns
kubectl top pods -n=lab-ns
```
* **`backend-hpa`:** Scales `backend-deployment` between **2 and 5 replicas** when average CPU utilization exceeds **75%**.
* **`frontend-hpa`:** Scales `frontend-deployment` between **2 and 4 replicas** when average CPU utilization exceeds **75%**.

### Simulate Load to Test Scaling
Open a watcher in seperate terminal windows:
```bash
kubectl get pods -n=lab-ns -w
kubectl get hpa -n=lab-ns -w
```
Generate HTTP traffic from a temporary `busybox` pod in a second terminal:
```bash
kubectl run load-generator --rm -it --restart=Never --image=busybox:1.36 -n=lab-ns -- \
  /bin/sh -c "while true; do wget -q -O- http://backend-service:5000/api/health >/dev/null 2>&1 || wget -q -O- http://backend-service:5000/ >/dev/null 2>&1; done"
```
Press **`Ctrl + C`** to stop the load generator (which automatically deletes the pod) and watch `backend-deployment` scale back down to 2 replicas after the stabilization window passes.

---

## Additional Guide: Automated Setup & Teardown

Automate the entire cluster lifecycle using the included helper scripts:

### One-Command Spin Up (`setup.sh`)
```bash
chmod +x setup.sh
./setup.sh
```
*Creates `practise-lab-cluster`, builds and loads the Docker images, installs/pins Ingress-NGINX, and deploys all MERN manifests.*

### One-Command Cleanup (`teardown.sh`)
```bash
chmod +x teardown.sh
./teardown.sh
```
*Deletes `practise-lab-cluster`, removes associated resources, and cleans up local lab images.*

---

## Further Improvements

* **HPA Autoscaling:** Implement `HorizontalPodAutoscaler` metrics-based scaling for frontends and backends.
* **NetworkPolicies:** Enforce microsegmentation and strict zero-trust pod communication rules.
* **RBAC & Pod Security:** Configure dedicated `ServiceAccount`s, least-privilege `Role`/`RoleBinding`s, and non-root `securityContext` constraints.
