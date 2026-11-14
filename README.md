# ShopLite GitOps — Continuous Delivery & Cluster Reconciliation

[![ArgoCD](https://img.shields.io/badge/ArgoCD-v2.10+-EF7B4D.svg?logo=argo&logoColor=white)](https://argoproj.github.io/cd/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.28+-326CE5.svg?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Helm](https://img.shields.io/badge/Helm-v3.12+-0F1689.svg?logo=helm&logoColor=white)](https://helm.sh/)
[![GitOps](https://img.shields.io/badge/GitOps-OpenGitOps-00C7B7.svg?logo=git&logoColor=white)](https://opengitops.net/)

`shoplite-gitops` is the declarative GitOps delivery and cluster state repository for the **ShopLite** cloud-native microservices e-commerce platform. It serves as the single source of truth for runtime configurations, ArgoCD application CRDs, environment overrides, and automated self-healing policies across Kubernetes clusters.

---

## 1. What Is `shoplite-gitops`?

In enterprise cloud-native systems, combining application code with runtime deployment state creates security risks and uncontrolled configuration drift. ShopLite enforces a strict separation across two repositories:

1. **`shoplite-app` (Repository 1 — Code & CI):** Contains application source code (`catalog-api`, `order-worker`, `web`), Dockerfiles, the unified Helm chart (`helm/shoplite/`), Terraform infrastructure, and GitHub Actions CI workflows.
2. **`shoplite-gitops` (Repository 2 — Desired State & CD):** Contains declarative ArgoCD application manifests (`apps/argocd-applications/`), environment runtime values (`envs/dev/`, `envs/prod/`), chaos engineering overlays (`chaos/`), and cluster bootstrap automation.

### The Golden Rule: CI vs GitOps Separation (Constraint C2)
- **GitHub Actions (CI):** Builds, tests, security-scans container images with Trivy, pushes to Amazon ECR via AWS OIDC, and commits the updated image tag to `envs/dev/values.yaml` in this repository.
- **Absolute Prohibition:** The CI/CD pipeline **NEVER** executes `kubectl apply`, `helm upgrade`, or any direct cluster deployment command.
- **ArgoCD (GitOps Engine):** Runs autonomously *inside* the private Kubernetes cluster, continuously watches `shoplite-gitops`, pulls the desired state, and reconciles the live workloads with automated self-healing.

---

## 2. How It Works

```text
┌───────────────────────────────────────┐         ┌───────────────────────────────────────┐
│        Repository 1: shoplite-app     │         │      Repository 2: shoplite-gitops    │
│  (Code, Dockerfiles, Helm, CI Tests)  │         │   (ArgoCD Apps & Environment Values)  │
└──────────────────┬────────────────────┘         └───────────────────┬───────────────────┘
                   │                                                  │
          [GitHub Actions CI]                                         │
        (Lint, Test, Trivy Scan)                                      │
                   │                                                  │
         [Push Images to ECR]                                         │
                   │                                                  │
                   ▼ (Commit new image tag)                           │
      Updates envs/dev/values.yaml ───────────────────────────────────►
                                                                      │
                                                           [ArgoCD In-Cluster Controller]
                                                         (Watches GitOps Repo, Pulls State)
                                                                      │
                                                                      ▼
                                                       ┌──────────────────────────────┐
                                                       │   Kubernetes Cluster         │
                                                       │  Namespace: shoplite-dev     │
                                                       │  Namespace: shoplite (prod)  │
                                                       │  Self-Healing: ACTIVE        │
                                                       └──────────────────────────────┘
```

### 2.1 ArgoCD Multi-Source Pattern
ArgoCD uses the Multi-Source feature (`sources: [...]`) to dynamically merge upstream Helm chart templates from `shoplite-app` with environment values in `shoplite-gitops`:
- **Source 1 (`shoplite-app`):** Reusable chart templates (`helm/shoplite`).
- **Source 2 (`shoplite-gitops`):** Environment-specific values (`$values/envs/dev/values.yaml` or `$values/envs/prod/values.yaml`).
- **Benefit:** Application developers build and package features independently, while release engineers manage replication, autoscaling, and chaos configurations without touching application code.

### 2.2 App-of-Apps Pattern
ArgoCD manages itself and child environments through a root meta-application:
- Applying `apps/argocd-applications/app-of-apps.yaml` registers the root application in the `argocd` namespace.
- ArgoCD automatically discovers, creates, and syncs all child applications (`shoplite-dev`, `shoplite-prod`).
- Bootstrapping an entire cluster or disaster recovery region requires applying exactly one manifest.

### 2.3 Automated Drift Detection & Self-Healing
- **Continuous Comparison:** ArgoCD compares the live state in Kubernetes etcd against target manifests in Git every 3 minutes (or instantly upon Git webhook push).
- **Drift Reversal (`selfHeal: true`):** If an engineer or rogue process modifies live resources (e.g. `kubectl scale deployment --replicas=0`), ArgoCD detects the divergence (`OutOfSync`) and automatically overwrites the cluster back to match Git within seconds.
- **Resource Pruning (`prune: true`):** Deleting a resource in Git automatically cleans up the corresponding live object in the cluster, preventing zombie workloads.

---

## 3. Repository Directory Structure

```text
shoplite-gitops/
├── README.md                          # Repository documentation and operational guide
├── .gitignore                         # Local environment and secret ignore rules
├── .env.example                       # ArgoCD and cluster environment variables template
├── apps/
│   └── argocd-applications/
│       ├── app-of-apps.yaml           # Root application managing all child environments
│       ├── shoplite-dev.yaml          # Dev application (auto-sync, auto-selfHeal, prune)
│       └── shoplite-prod.yaml         # Prod application (manual promotion approval gate)
├── envs/
│   ├── dev/
│   │   └── values.yaml                # Single replicas, low CPU/RAM, mutable dev image tags
│   └── prod/
│       └── values.yaml                # HA (2 replicas), HPA 2-6, PDB, 10Gi PVC, immutable tags
├── chaos/
│   ├── chaos-exercise-playbook.md     # Question 8 Chaos & RCA operational execution manual
│   └── overlays/                      # Reusable chaos fault injection configuration stanzas
│       ├── chaos-flag1-latency.yaml   # 1500ms delay on 30% of product catalog queries
│       ├── chaos-flag2-error-rate.yaml# 20% HTTP 500 error rate on order registration
│       ├── chaos-flag3-memory-leak.yaml # 2MB unreleased memory buffer per order (OOMKilled)
│       └── chaos-flag4-slow-db.yaml   # 2000ms pg_sleep before DB update (Queue Backlog)
└── scripts/
    ├── bootstrap-argocd.sh            # Idempotent cluster bootstrap script for ArgoCD engine
    └── verify-self-healing.sh         # Automated self-healing drill and drift verification test
```

---

## 4. Environment Comparison Matrix

| Configuration Attribute | Development (`envs/dev/`) | Production (`envs/prod/`) |
| :--- | :--- | :--- |
| **Target Namespace** | `shoplite-dev` | `shoplite` |
| **Sync Policy** | **Automated** (`selfHeal: true`, `prune: true`) | **Manual Approval Gate** (`selfHeal: on-sync`) |
| **Replication** | 1 replica per microservice | 2 replicas baseline |
| **Autoscaling (HPA)** | Disabled | Enabled (2–6 replicas @ 70% CPU target) |
| **Disruption Budget (PDB)** | Disabled | Enabled (`minAvailable: 1`) |
| **PostgreSQL Storage** | 2Gi dynamic storage | 10Gi PersistentVolume via StatefulSet |
| **Image Tagging** | `dev-latest` (or commit SHA) | `v1.0.0` (immutable release SemVer) |
| **NetworkPolicy** | Zero-trust database/cache isolation | Zero-trust database/cache isolation |
| **Prometheus Scraping** | 15s scrape interval via `ServiceMonitor` | 15s scrape interval via `ServiceMonitor` |

---

## 5. Step-by-Step Operator Guide

### 5.1 Bootstrapping ArgoCD in Kubernetes
Deploy the official ArgoCD engine and register the root App-of-Apps:
```bash
# 1. Run bootstrap script
bash scripts/bootstrap-argocd.sh

# 2. Retrieve initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo

# 3. Access ArgoCD UI via port-forward (or Ingress)
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Login at https://localhost:8080 (user: admin)
```

### 5.2 Promoting a Release from Dev to Prod
1. After automated CI verification in `shoplite-dev`, note the validated commit SHA or SemVer release tag.
2. Open a Pull Request on `shoplite-gitops` updating `envs/prod/values.yaml`:
   ```yaml
   catalogApi:
     image:
       tag: "v1.1.0"
   orderWorker:
     image:
       tag: "v1.1.0"
   web:
     image:
       tag: "v1.1.0"
   ```
3. Upon PR approval and merge to `main`, navigate to the ArgoCD UI and click **Sync** on `shoplite-prod` (or execute via CLI: `argocd app sync shoplite-prod`).

### 5.3 Executing the Automated Self-Healing Drill
Run the automated verification script to demonstrate cluster resilience:
```bash
bash scripts/verify-self-healing.sh shoplite-catalog-api
```
- The script scales `shoplite-catalog-api` to `0` replicas using `kubectl`.
- ArgoCD detects divergence (`OutOfSync`) and automatically restores replicas to `1` within seconds.
- Zero manual changes can permanently alter the cluster state.

### 5.4 Running the Question 8 Chaos Drill & Recovery
1. **Inject Fault:** A peer copies one overlay from `chaos/overlays/` into `envs/prod/values.yaml` and commits to `main`.
2. **Execute Load Test:** Run `k6 run --vus 25 --duration 15m loadtest.js` against the cluster.
3. **Diagnose via Observability (Constraint C14):**
   - Alertmanager Alert (`HighErrorRate` / `HighLatency` / `QueueBacklog` / `PodCrashLooping`).
   - Golden Signals Dashboard (`uid: shoplite-golden-signals`).
   - Loki structured JSON logs (`service="catalog-api"` level="ERROR").
   - Tempo distributed trace span inspection.
4. **Instant GitOps Recovery:**
   ```bash
   git revert HEAD --no-edit
   git push origin main
   ```
   ArgoCD detects the commit revert and automatically heals the production cluster back to baseline health.

---

## 6. Security, Secrets & Compliance

- **Zero Secrets in Git (Constraint C5):** Database passwords and API keys are NEVER stored in this repository. Sensitive values are injected via Kubernetes Secrets or synced via AWS Secrets Manager.
- **Least-Privilege RBAC:** ArgoCD service accounts operate under strictly scoped Kubernetes ClusterRoles. External CI runners have zero cluster credentials.
- **Non-Root Containers:** All workloads deployed by these values enforce `runAsNonRoot: true` (UID `10001`), `readOnlyRootFilesystem: true`, and dropped capabilities.
