# platform-config

Owned by the platform team. Vendors read it, but can't change it.

| Folder | What it is |
|---|---|
| `tenants/vendors/` | One file per vendor app. Adding one (by PR) onboards the vendor. |
| `tenants/` | Helm chart Argo CD renders into an AppProject + Applications per vendor. |
| `.github/workflows/build.yml` | The only build that can produce deployable images (called by every `src-*` repo). |
| `.github/workflows/deploy-checks.yml` | Required checks on every PR to a `deploy-*` repo. |
| `.github/workflows/infra.yml` | Terraform plan/apply for vendor Azure resources. |
| `.github/workflows/onboard.yml` + `scripts/onboard.sh` | Onboarding automation. |
| `policies/` | Platform rules (conftest), checked on every deploy PR. |
| `modules/vendor-kit/` | Terraform module: what a vendor may get in Azure. |
| `templates/src`, `templates/deploy` | Starting content of every vendor's repos. |
| `queries/` | KQL for the 360 view in Log Analytics. |
