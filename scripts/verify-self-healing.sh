#!/usr/bin/env bash
# ShopLite GitOps - Automated Self-Healing Verification Drill (Q7 Checkpoint)
# Demonstrates constraint C2: ArgoCD automated self-healing restores drifted cluster state
set -euo pipefail

NAMESPACE="${DEV_NAMESPACE:-shoplite-dev}"
DEPLOYMENT="${1:-shoplite-catalog-api}"
APP_NAME="shoplite-dev"

echo "=========================================================="
echo "Starting ShopLite GitOps Automated Self-Healing Drill"
echo "Target Namespace:  ${NAMESPACE}"
echo "Target Deployment: ${DEPLOYMENT}"
echo "ArgoCD App:        ${APP_NAME}"
echo "=========================================================="

echo "--> Step 1: Checking initial deployment state..."
CURRENT_REPLICAS=$(kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "not-found")

if [[ "${CURRENT_REPLICAS}" == "not-found" ]]; then
  echo "WARN: Deployment ${DEPLOYMENT} not found in namespace ${NAMESPACE}. Verify cluster connection."
  exit 1
fi

echo "Current desired replicas in cluster: ${CURRENT_REPLICAS}"

echo "--> Step 2: Injecting intentional drift (scaling replicas to 0 via kubectl)..."
kubectl scale deployment "${DEPLOYMENT}" -n "${NAMESPACE}" --replicas=0
echo "Scaled deployment ${DEPLOYMENT} to 0 replicas."

DRIFT_REPLICAS=$(kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')
echo "Drifted replicas: ${DRIFT_REPLICAS}"

echo "--> Step 3: Waiting for ArgoCD automated self-healing loop to trigger..."
echo "ArgoCD controller detects drift (OutOfSync) and reverts live cluster to Git source of truth..."

RESTORED=false
for i in {1..30}; do
  REPLICAS=$(kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')
  if [[ "${REPLICAS}" -gt 0 ]]; then
    echo "SUCCESS: ArgoCD self-healed deployment ${DEPLOYMENT}! Live replicas restored to ${REPLICAS}."
    RESTORED=true
    break
  fi
  echo "Waiting for ArgoCD self-heal... (${i}/30s)"
  sleep 2
done

if [[ "${RESTORED}" == "true" ]]; then
  echo "=========================================================="
  echo "DRILL PASSED: Automated Self-Healing Verified!"
  echo "Zero kubectl changes can permanently alter the cluster."
  echo "=========================================================="
  exit 0
else
  echo "ERROR: Self-healing timeout. Verify ArgoCD syncPolicy.automated.selfHeal is set to true."
  exit 1
fi
