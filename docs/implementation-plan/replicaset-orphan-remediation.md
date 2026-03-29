# ReplicaSet Orphan Remediation Plan

Date: 2026-03-28

## Scope
This plan addresses legacy ReplicaSets that accumulate after Deployment updates.

Primary fix:
- Explicitly set `spec.revisionHistoryLimit` on all Deployments.
- Recommended default for this cluster: `1` (keep only one rollback revision).

Why this works:
- Kubernetes Deployments retain old ReplicaSets for rollback.
- If not configured, the default retention is 10 revisions.
- Over time this creates many stale ReplicaSets per app, especially for frequently updated workloads.

## Findings
Deployment manifests scanned under `cluster/apps/**`:
- Total Deployment manifests: 27
- Already configured with `revisionHistoryLimit`: 1 (`ghost`)
- Missing `revisionHistoryLimit` and requiring remediation: 26

## Apps Requiring Remediation
1. `cluster/apps/anona-counseling-page/deployment.yaml`
2. `cluster/apps/bp-tools/Deployment.yaml`
3. `cluster/apps/cloudflared/Deployment.yaml`
4. `cluster/apps/ddb-proxy/deployment.yaml`
5. `cluster/apps/deluge/deployment.yaml`
6. `cluster/apps/ersatztv/deployment.yaml`
7. `cluster/apps/foundry/deployment.yaml`
8. `cluster/apps/gustindev/deployment.yaml`
9. `cluster/apps/jellyfin/deployment.yaml`
10. `cluster/apps/jellyseer/deployment.yaml`
11. `cluster/apps/komga/deployment.yaml`
12. `cluster/apps/kutt/deployment.yaml`
13. `cluster/apps/lidarr/deployment.yaml`
14. `cluster/apps/mosquitto/deployment.yaml`
15. `cluster/apps/n8n/deployment.yaml`
16. `cluster/apps/ntfy/Deployment.yaml`
17. `cluster/apps/nzbget/deployment.yaml`
18. `cluster/apps/planner-gen/Deployment.yaml`
19. `cluster/apps/plex-route/proxy-deployment.yaml`
20. `cluster/apps/prowlarr/03-deployment.yaml`
21. `cluster/apps/radarr/03-deployment.yaml`
22. `cluster/apps/sonarr/02-deployment.yaml`
23. `cluster/apps/tautulli/deployment.yaml`
24. `cluster/apps/test-app/Deployment.yaml`
25. `cluster/apps/uptime-kuma/deployment.yaml`
26. `cluster/apps/ytdl/deployment.yaml`

## Remediation Plan

### Phase 1: Manifest normalization
1. Add `revisionHistoryLimit: 1` to each Deployment listed above.
2. Keep placement directly under `spec` beside `replicas` for consistency.

Validation:
- `rg -n "^\s*revisionHistoryLimit:" cluster/apps -g "*deployment*.yaml" -g "*Deployment*.yaml"`
- Ensure all Deployment manifests in `cluster/apps` are reported.

### Phase 2: Apply and reconcile
1. Let ArgoCD sync updated Deployments.
2. Confirm each Deployment shows desired history limit:
   - `kubectl get deploy -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,HISTORY:.spec.revisionHistoryLimit'`
3. Trigger one controlled rollout per app (natural image updates are fine) so old histories are re-pruned over time.

### Phase 3: One-time cleanup of existing stale ReplicaSets
1. Identify old ReplicaSets currently at zero desired/ready replicas:
   - `kubectl get rs -A --sort-by=.metadata.creationTimestamp`
2. Delete stale zero-sized ReplicaSets for each remediated app namespace after verifying owner Deployment still exists.
3. Keep newest active ReplicaSet plus rollback allowance implied by `revisionHistoryLimit`.

Safety checks before deletion:
- Owner Deployment exists and is Healthy.
- Candidate ReplicaSet has `DESIRED=0` and `CURRENT=0`.
- Candidate is older than the latest successful rollout.

### Phase 4: Regression prevention in authoring standards
1. Enforce Deployment guidance in repository instructions so future apps include `revisionHistoryLimit` by default.
2. Add review checklist item: any new Deployment without `revisionHistoryLimit` fails review.

## Execution Checklist
1. [x] Add `revisionHistoryLimit: 1` to all 26 affected Deployment manifests.
2. [ ] Sync apps in ArgoCD and verify Deployment specs reflect history limit.
3. [ ] Clean existing stale ReplicaSets per namespace with safety checks.
4. [ ] Re-run inventory and confirm stale ReplicaSet count is reduced/controlled.
5. [x] Update relevant Deployment templates/guidance in `.github/copilot-instructions.md`.

## Current Status
- Phase 1 complete: all 27 Deployment manifests under `cluster/apps` now explicitly define `revisionHistoryLimit`.
- `.github/copilot-instructions.md` updated so future Deployment examples include `revisionHistoryLimit`.
