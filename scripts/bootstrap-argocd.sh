#!/usr/bin/env bash
# ShopLite GitOps - ArgoCD Cluster Bootstrap & App-of-Apps Deployment
# Installs ArgoCD and registers root App-of-Apps manifest
set -euo pipefail

ARGOCD_NAMESPACE="argocd"
ARGOCD_VERSION="v2.10.2"

echo "=========================================================="
echo "Bootstrapping ArgoCD GitOps Engine"
echo "Target Namespace: ${ARGOCD_NAMESPACE}"
echo "=========================================================="

echo "--> 1. Creating argocd namespace..."
kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "--> 2. Installing official ArgoCD manifests..."
kubectl apply -n "${ARGOCD_NAMESPACE}" -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "--> 3. Waiting for ArgoCD Server and Application Controller to be ready..."
kubectl rollout status deployment/argocd-server -n "${ARGOCD_NAMESPACE}" --timeout=300s
kubectl rollout status deployment/argocd-applicationset-controller -n "${ARGOCD_NAMESPACE}" --timeout=300s

echo "--> 4. Registering Root App-of-Apps Application..."
kubectl apply -f apps/argocd-applications/app-of-apps.yaml

echo "=========================================================="
echo "ArgoCD Bootstrapped Successfully!"
echo "Retrieve initial admin password via:"
echo "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo "=========================================================="
