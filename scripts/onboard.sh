#!/usr/bin/env bash
# Onboards one vendor app from its file in tenants/vendors/.
# Runs in GitHub Actions (workflows/onboard.yml) after a PR adding the file is merged.
# Re-running is safe: every step skips what already exists.
#
# Env (set by the workflow from org variables): ORG PREFIX LOCATION PLATFORM_RG
# PLATFORM_IDENTITY AKS_NAME AKS_OIDC_ISSUER ACR_NAME CODEOWNER GH_TOKEN
set -euo pipefail
FILE=${1:?vendor file}
cd "$(dirname "$0")/.."

# --- 0. Read the vendor request ------------------------------------------------------
VENDOR=$(yq '.vendor' "$FILE")
APP=$(yq '.app' "$FILE")
ENVS=$(yq '.environments[]' "$FILE")
COLOR=$(yq '.color // "#1f6feb"' "$FILE")
GROUP=$(yq '.entraGroupId // ""' "$FILE")
NAME="$VENDOR-$APP"
RG="rg-$PREFIX-$NAME"
STORAGE=$(echo "st${PREFIX}${VENDOR}${APP}" | tr -cd 'a-z0-9' | cut -c1-24)   # global name
echo "== Onboarding $NAME"

# --- 1. Resource group for the vendor's Azure resources --------------------------------
echo "-- 1. Resource group $RG"
az group create -n "$RG" -l "$LOCATION" --tags demo="$PREFIX" vendor="$VENDOR" app="$APP" -o none

# --- 2. One AKS managed namespace per environment ---------------------------------------
# Quota, default network policy and labels belong to Azure: vendors can't loosen them.
# The pod-security label makes the cluster reject privileged containers.
echo "-- 2. Managed namespaces"
for ENV in $ENVS; do
  NS="$NAME-$ENV"
  if az aks namespace show -n "$NS" --cluster-name "$AKS_NAME" -g "$PLATFORM_RG" -o none 2>/dev/null; then
    echo "   $NS exists"; continue
  fi
  az aks namespace add -n "$NS" --cluster-name "$AKS_NAME" -g "$PLATFORM_RG" \
    --cpu-request "$(yq '.quota.cpuRequest' "$FILE")" --cpu-limit "$(yq '.quota.cpuLimit' "$FILE")" \
    --memory-request "$(yq '.quota.memoryRequest' "$FILE")" --memory-limit "$(yq '.quota.memoryLimit' "$FILE")" \
    --ingress-policy AllowSameNamespace --egress-policy AllowAll \
    --adoption-policy Never --delete-policy Delete \
    --labels "demo/vendor=$VENDOR" "demo/env=$ENV" "pod-security.kubernetes.io/enforce=baseline" \
    -o none
  echo "   $NS created"
done

# --- 3. App identity: the app reaches its own Azure resources without secrets ------------
echo "-- 3. App identity id-$NAME"
az identity create -g "$RG" -n "id-$NAME" -l "$LOCATION" -o none
APP_CLIENT_ID=$(az identity show -g "$RG" -n "id-$NAME" --query clientId -o tsv)
APP_PRINCIPAL_ID=$(az identity show -g "$RG" -n "id-$NAME" --query principalId -o tsv)
for ENV in $ENVS; do   # trust the app's service account in each namespace
  az identity federated-credential create -g "$RG" --identity-name "id-$NAME" --name "aks-$ENV" \
    --issuer "$AKS_OIDC_ISSUER" --subject "system:serviceaccount:$NAME-$ENV:$APP" \
    --audiences api://AzureADTokenExchange -o none 2>/dev/null || echo "   aks-$ENV exists"
done

# --- 4. Let the vendor's repos log in to Azure from GitHub Actions ------------------------
# src: our build pushes images. deploy: PR checks (pull_request) and Terraform (main).
echo "-- 4. GitHub OIDC trust for the vendor repos"
fedcred() { # <credential name> <subject>
  az identity federated-credential create -g "$PLATFORM_RG" --identity-name "$PLATFORM_IDENTITY" \
    --name "$1" --issuer https://token.actions.githubusercontent.com --subject "$2" \
    --audiences api://AzureADTokenExchange -o none 2>/dev/null || echo "   $1 exists"
}
fedcred "gh-src-$NAME-main"    "repo:$ORG/src-$NAME:ref:refs/heads/main"
fedcred "gh-deploy-$NAME-main" "repo:$ORG/deploy-$NAME:ref:refs/heads/main"
fedcred "gh-deploy-$NAME-pr"   "repo:$ORG/deploy-$NAME:pull_request"
sleep 30   # new federated credentials take a moment before the first login works

# --- 5. Repo from a template folder, with the placeholders filled in -----------------------
create_repo() { # <src|deploy>
  local repo="$ORG/$1-$NAME" tmp
  if gh repo view "$repo" >/dev/null 2>&1; then
    # exists: skip, unless an earlier run created it but never pushed content
    if [[ "$(gh repo view "$repo" --json isEmpty --jq .isEmpty)" != "true" ]]; then echo "   $repo exists"; return 0; fi
    echo "   $repo exists but is empty - filling it"
  else
    gh repo create "$repo" --public --description "Vendor $VENDOR, app $APP ($1)" >/dev/null
  fi
  tmp=$(mktemp -d)
  cp -r "templates/$1/." "$tmp"
  grep -rlF '__' "$tmp" | xargs -r sed -i \
    -e "s|__ORG__|$ORG|g"            -e "s|__VENDOR__|$VENDOR|g"   -e "s|__APP__|$APP|g" \
    -e "s|__PREFIX__|$PREFIX|g"      -e "s|__ACR__|$ACR_NAME|g"    -e "s|__CODEOWNER__|$CODEOWNER|g" \
    -e "s|__COLOR__|$COLOR|g"        -e "s|__LOCATION__|$LOCATION|g" -e "s|__STORAGE__|$STORAGE|g" \
    -e "s|__APP_CLIENT_ID__|$APP_CLIENT_ID|g" -e "s|__APP_PRINCIPAL_ID__|$APP_PRINCIPAL_ID|g"
  (cd "$tmp" && git init -q -b main && git add -A \
    && git -c user.name="platform-onboarding" -c user.email="onboarding@users.noreply.github.com" \
           commit -qm "Onboarding: initial content" \
    && git push -q "https://x-access-token:${GH_TOKEN}@github.com/$repo.git" main)
  gh api -X PATCH "repos/$repo" -F allow_auto_merge=true -F delete_branch_on_merge=true >/dev/null
  echo "   $repo created"
}

# --- 6. Branch protection (rulesets) ---------------------------------------------------------
# deploy: PRs only + required platform checks + code-owner approval for test/prod/infra.
# src: no force-push, no deletion -> history can be added to, never rewritten.
protect() { # <repo> <ruleset json>
  gh api "repos/$1/rulesets" --jq '.[].name' | grep -qx main-protection \
    || gh api -X POST "repos/$1/rulesets" --input "$2" >/dev/null
}

# Order matters: deploy repo first (the first build opens a PR there), src repo last
# (its first push starts the first build).
echo "-- 5/6. Repos and protection"
create_repo deploy
protect "$ORG/deploy-$NAME" scripts/rulesets/deploy.json
create_repo src
protect "$ORG/src-$NAME" scripts/rulesets/src.json

# --- 7. Optional: vendor staff group gets read-only access to its namespaces ------------------
if [[ -n "$GROUP" ]]; then
  echo "-- 7. Read-only namespace access for group $GROUP"
  for ENV in $ENVS; do
    NS_ID=$(az aks namespace show -n "$NAME-$ENV" --cluster-name "$AKS_NAME" -g "$PLATFORM_RG" --query id -o tsv)
    for role in "Azure Kubernetes Service Namespace User" "Azure Kubernetes Service RBAC Reader"; do
      az role assignment create --assignee-object-id "$GROUP" --assignee-principal-type Group \
        --role "$role" --scope "$NS_ID" -o none
    done
  done
fi

echo "== $NAME onboarded. Argo CD picks up the new project from tenants/ on its own."
