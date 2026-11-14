# ShopLite GitOps (`shoplite-gitops`)

Declarative GitOps repository for the ShopLite cloud-native microservices platform, reconciled via ArgoCD.

## Repository Layout
- `apps/argocd-applications/`: ArgoCD Application manifests (`shoplite-dev.yaml`, `shoplite-prod.yaml`).
- `envs/dev/`: Development environment Helm overrides (`values.yaml`).
- `envs/prod/`: Production environment Helm overrides (`values.yaml`).
