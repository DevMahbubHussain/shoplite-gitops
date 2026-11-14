# Question 8: Chaos Engineering & GitOps Recovery Playbook

> **Scope:** Assessment Milestone 4 / Question 8 (Chaos Engineering & Root Cause Analysis)  
> **Repository:** `shoplite-gitops`  
> **Constraints:** Strict adherence to **C14** (Zero inspecting commits/diffs during diagnosis; recovery executed strictly via GitOps revert).

---

## 1. Chaos Fault Injection Matrix

| Flag | File Location | Trigger Parameter | System Impact | Primary Observability Signal |
| :---: | :--- | :--- | :--- | :--- |
| **Flag 1** | `chaos/overlays/chaos-flag1-latency.yaml` | `chaosLatencyMs: 1500` | 1.5s delay added to 30% of product queries | p95 latency spikes $> 1.5\text{s}$; Tempo trace shows delay inside FastAPI span |
| **Flag 2** | `chaos/overlays/chaos-flag2-error-rate.yaml` | `chaosErrorRate: 0.2` | 20% of `POST /orders` fail with HTTP 500 | `HighErrorRate` fires; Loki logs show 500 status; metric error rate hits 20% |
| **Flag 3** | `chaos/overlays/chaos-flag3-memory-leak.yaml` | `chaosMemoryLeakMb: 2` | Worker leaks 2MB per order without releasing | Pod memory climbs linearly to limit; `OOMKilled` (Exit 137); `PodCrashLooping` fires |
| **Flag 4** | `chaos/overlays/chaos-flag4-slow-db.yaml` | `chaosSlowDbMs: 2000` | Worker runs 2s slow query before DB update | Worker throughput drops; `order_queue_depth` spikes; `QueueBacklog` alert fires |

---

## 2. Step-by-Step Exercise Execution Protocol

### Step 1: Fault Injection (Peer Action)
A peer engineer or assessor copies one chaos flag overlay into `envs/prod/values.yaml` and commits to `shoplite-gitops`:
```bash
# Example: Inject Flag 2 (High Error Rate)
git checkout main
# Apply chaos overlay to envs/prod/values.yaml
git commit -am "chore(ops): adjust production runtime parameters"
git push origin main
```
ArgoCD syncs the change to the cluster (or operator approves manual sync).

### Step 2: Traffic Generation Under Load
Run the 15-minute synthetic load test at $\ge 20\text{ RPS}$:
```bash
# From shoplite-app directory:
k6 run --vus 25 --duration 15m scripts/loadtest.js
```

### Step 3: Observability-Driven Diagnosis (Strict C14 Protocol)
**CRITICAL:** Do NOT inspect Git commit history, pull request diffs, or pod environment variables before diagnosing the issue.

Diagnose the fault strictly through the observability chain:
1. **Alertmanager Alert Trigger:**
   - Note which alert fires (`HighErrorRate`, `HighLatency`, `QueueBacklog`, or `PodCrashLooping`).
   - Open the alert's annotated `runbook_url`.
2. **Golden Signals Dashboard Panels:**
   - Identify the affected signal: Latency (Panel 2), Error Rate (Panel 3), Saturation (Panel 4), or Queue Backlog (Panel 5).
3. **Loki Structured Log Inspection:**
   - Filter logs by `service="catalog-api"` or `service="order-worker"` with `level="ERROR"`.
   - Inspect single-line JSON log fields and extract the `trace_id`.
4. **Tempo Distributed Trace Navigation:**
   - Click the **View Distributed Trace in Tempo** derived field badge.
   - Inspect the waterfall graph: identify the exact span injecting latency, failing with 500, or timing out.

---

## 3. GitOps Recovery Protocol (The Golden Rule)
Once the fault is isolated via observability evidence:
1. Revert the Git commit on `shoplite-gitops`:
   ```bash
   git revert HEAD --no-edit
   git push origin main
   ```
2. In ArgoCD UI, observe the sync transition from `OutOfSync` $\to$ `Synced`.
3. Kubernetes executes a rolling update restoring clean baseline pods.
4. Verify on the Golden Signals Dashboard that error rates drop to zero, latencies normalize, and queue backlog drains.

---

## 4. Root Cause Analysis (RCA) Documentation
Following recovery, author the formal 1–2 page RCA report at `docs/RCA/RCA_REPORT.md` in `shoplite-app` using the evidence screenshots captured from Grafana, Loki, and Tempo.
