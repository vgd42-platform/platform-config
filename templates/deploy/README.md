# deploy-__VENDOR__-__APP__

What runs where for __APP__ (vendor __VENDOR__). Argo CD keeps the cluster equal to `main`.

| Path | Changed by | Approval |
|---|---|---|
| `envs/dev/` | platform build, automatically | none (checks only) |
| `envs/test/` | promotion PR (Actions > promote) | code owner |
| `envs/prod/` | promotion PR (Actions > promote) | code owner |
| `infra/main.tf` | vendor PR (only the marked values) | code owner; plan posted on the PR |

Every PR runs the platform checks: schema, policy, image provenance, promotion order.
