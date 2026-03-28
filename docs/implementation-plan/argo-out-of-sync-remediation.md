# ArgoCD Out-of-Sync Remediation Plan

Date: 2026-03-28

## Scope
This plan documents current ArgoCD `OutOfSync` applications, diagnosis for each, and a remediation sequence.

Data source used:
- `kubectl get applications.argoproj.io -n argocd -o wide`
- `kubectl get applications.argoproj.io <app> -n argocd -o jsonpath=...`
- `kubectl get externalsecret <name> -n <ns> -o yaml`

## Out-of-Sync App Inventory
At time of analysis, these Argo applications were `OutOfSync`:
1. `apps`
2. `cloudflared`
3. `discord-activity-bot`
4. `foundry`
5. `gustend-ghost`
6. `kutt`

## Diagnosis By App

### 1) apps
Status:
- Health: `Healthy`
- Drifted resources:
  - `Namespace` `/metallb-system`
  - `BackendTLSPolicy` `argocd/argocd-server-backend-tls`
  - `HTTPRoute` `argocd/argocd-server`
- Argo condition:
  - `SharedResourceWarning`: each of the above resources is part of both applications `apps` and `root-app`.

Diagnosis:
- This is ownership overlap, not a runtime failure.
- The resources are rendered by `root-app` chart templates, while also being observed under the parent `apps` application.
- This is causing predictable sync drift due to shared ownership.

Manifest locations involved:
- `cluster/root-app/templates/namespaces.yaml`
- `cluster/root-app/templates/argo-route.yaml`

### 2) cloudflared
Status:
- Health: `Healthy`
- Drifted resource:
  - `ExternalSecret` `default/tunnel-credentials`

Diagnosis:
- The live `ExternalSecret` contains controller/defaulted fields not explicitly declared in Git, including:
  - `spec.target.deletionPolicy: Retain`
  - `spec.data[].remoteRef.conversionStrategy: Default`
  - `spec.data[].remoteRef.decodingStrategy: None`
  - `spec.data[].remoteRef.metadataPolicy: None`
- This matches the pattern of default-value drift.

Manifest location:
- `cluster/apps/cloudflared/external-secret-tunnel-credentials.yaml`

### 3) discord-activity-bot
Status:
- Health: `Healthy`
- Drifted resources:
  - `ExternalSecret` `default/discord-server-id`
  - `ExternalSecret` `default/discord-token`
  - `ExternalSecret` `default/ghcr-docker-pull-secret`
  - `ExternalSecret` `default/google-sa`
  - `ExternalSecret` `default/sheet-id`

Diagnosis:
- Same default-value drift pattern as cloudflared for all ExternalSecrets.
- Additional template-related defaults are present on `ghcr-docker-pull-secret` in live state:
  - `spec.target.template.engineVersion: v2`
  - `spec.target.template.mergePolicy: Replace`
  - `spec.target.template.metadata: {}`
- These are likely webhook/controller-applied defaults and not currently mirrored in manifests.

Manifest locations:
- `cluster/apps/discord-activity-bot/external-secret-discord-token.yaml`
- `cluster/apps/discord-activity-bot/external-secret-google-sa.yaml`
- `cluster/apps/discord-activity-bot/external-secret-private-ghcr.yaml`
- `cluster/apps/discord-activity-bot/external-secret-sheet-and-server-id.yaml`

### 4) foundry
Status:
- Health: `Healthy`
- Drifted resources:
  - `ExternalSecret` `foundry/foundry-admin-key`
  - `ExternalSecret` `foundry/foundry-user-name`
  - `ExternalSecret` `foundry/foundry-user-password`

Diagnosis:
- Same ExternalSecret default-value drift pattern:
  - `spec.target.deletionPolicy: Retain`
  - `spec.data[].remoteRef.{conversionStrategy,decodingStrategy,metadataPolicy}` defaulted in live state.

Manifest location:
- `cluster/apps/foundry/external-secret.yaml`

### 5) gustend-ghost
Status:
- Health: `Healthy`
- Drifted resources:
  - `ExternalSecret` `ghost-k8s/ghost-config-mysql-pass`
  - `ExternalSecret` `ghost-k8s/ghost-config-prod`

Diagnosis:
- Same ExternalSecret default-value drift pattern:
  - `spec.target.deletionPolicy: Retain`
  - `spec.data[].remoteRef.{conversionStrategy,decodingStrategy,metadataPolicy}` defaulted in live state.

Manifest location:
- `cluster/apps/ghost/01-config-secrets.yaml`

### 6) kutt
Status:
- Health: `Healthy`
- Drifted resource:
  - `ExternalSecret` `default/kutt-jwt-secret`

Diagnosis:
- Same ExternalSecret default-value drift pattern as above.

Manifest location:
- `cluster/apps/kutt/external-secret.yaml`

## Root-Cause Summary
1. Shared ownership drift in parent app (`apps`) due to resources being owned by both `apps` and `root-app`.
2. ExternalSecret default-field drift where live objects include explicit defaults not represented in Git manifests.

## Remediation Strategy

### Phase 1: Eliminate parent app shared-resource drift
Choose one owner for these resources:
- `Namespace/metallb-system`
- `HTTPRoute/argocd-server`
- `BackendTLSPolicy/argocd-server-backend-tls`

Recommended:
- Keep these resources in `root-app` templates.
- Stop rendering them under `apps` if currently duplicated by path scope.

Validation:
- `kubectl get app apps -n argocd -o jsonpath='{.status.sync.status}'` should become `Synced`.

### Phase 2: Normalize ExternalSecret manifests to match live defaults
For each ExternalSecret manifest listed above, explicitly set:
- `spec.target.deletionPolicy: Retain`
- For every `spec.data[].remoteRef`:
  - `conversionStrategy: Default`
  - `decodingStrategy: None`
  - `metadataPolicy: None`

For docker pull secret template (`ghcr-docker-pull-secret`), also set:
- `spec.target.template.engineVersion: v2`
- `spec.target.template.mergePolicy: Replace`
- `spec.target.template.metadata: {}`

Validation:
- `kubectl get app <app> -n argocd -o jsonpath='{.status.sync.status}'` should return `Synced` for each affected app.

### Phase 3: Optional hardening to prevent future default-drift churn
If drift recurs due to CRD/operator defaults, add targeted `ignoreDifferences` rules in `cluster/root-app/values.yaml` using the existing `ignoreDifferences` support in `cluster/root-app/templates/app-set.yaml`.

Candidate ignore rule style:
- Kind: `ExternalSecret`
- Group: `external-secrets.io`
- Limit by jsonPointers only to defaulted fields above

Note:
- Prefer explicit manifests first; use ignore rules only when defaults are unstable across versions.

## Execution Checklist
1. Resolve shared ownership for `apps` and `root-app` resources.
2. Update all ExternalSecret manifests to include explicit defaulted fields.
3. Sync affected applications in ArgoCD.
4. Verify all six applications report `Synced`.
5. If any remain drifted, capture `kubectl get app <name> -n argocd -o yaml` and add app-specific ignore rules.

## Expected Outcome
After Phase 1 and Phase 2, all currently `OutOfSync` apps should return to `Synced` without changing runtime behavior, because fixes align desired manifests with existing live defaults and remove ownership ambiguity.
