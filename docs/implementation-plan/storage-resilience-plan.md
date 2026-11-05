# Storage Resilience Plan

Status: proposed. Written after the Nov 2026 cluster rebuild, where Argo recreated
PVCs as new empty Synology LUNs instead of reattaching the existing ones.

## Background

- `synology-iscsi` (default) uses `reclaimPolicy: Delete` and dynamic provisioning.
  A rebuilt cluster has no PVs, so every PVC provisions a fresh empty LUN.
- Recovery was done by creating static PVs that point at the old LUN UUIDs
  (`volumeHandle`) and pinning PVCs with `spec.volumeName`. These live in each
  app's `pv.yaml` / `pvc.yaml`. 23 PVCs are pinned this way.
- The CSI driver stores `<namespace>/<pvc-name>` in each LUN's description, which
  is how orphaned LUNs are matched to PVCs (DSM API `SYNO.Core.ISCSI.LUN` list).

## Goals

1. A rebuild restores data from backup instead of depending on LUNs surviving.
2. Accidentally deleting a PVC or app does not delete data.
3. Re-mapping after a rebuild is documented and repeatable.

## Phase 1: Backups (highest value)

Pick one or combine:

- **Synology Snapshot Replication** on the LUNs: scheduled snapshots plus
  replication to a second volume or NAS. Lowest effort; works for every app.
- **Synology Hyper Backup** of the LUNs to an offsite target (cloud / second NAS).
- **Velero (CSI snapshots)**: uses the existing `synology-iscsi-snapshot`
  VolumeSnapshotClass. Backs up PVC data and Kubernetes objects to object storage.
- **App-level exports**: Sonarr/Radarr/Lidarr/Prowlarr already write `Backups/`;
  Ghost (content export + MySQL dump), n8n (workflow export), Foundry (worlds),
  Kutt/Uptime Kuma (DB dumps) can be scheduled as CronJobs to NFS.

Acceptance: restore one app (e.g. lidarr) from backup into a scratch namespace and
confirm it starts with its data. Repeat after any backup tooling change.

Priority apps (hard to recreate): foundry, ghost-k8s (mysql + static), n8n,
jellyfin-config, kutt-db-data, uptime-kuma, then the *arr configs.

## Phase 2: Retain reclaim policy

- Add a new StorageClass (e.g. `synology-iscsi-retain`) with `reclaimPolicy: Retain`
  in `bootstrap/synology-csi-talos/deploy/kubernetes/*/storage-class.yml`.
  StorageClass parameters/reclaimPolicy cannot be edited in place, so this is a new
  class, not a change to `synology-iscsi`.
- Use it for new PVCs. Existing PVCs keep their class; to migrate, patch the bound
  PV: `kubectl patch pv <pv> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'`.
  Patching live PVs is non-destructive and is the quickest win for dynamic PVs.
- Optionally make it the default class once existing PVs are patched.
- Note: Retain leaves orphaned LUNs behind on delete; clean up in DSM periodically.

## Phase 3: Keep or retire the pinned PVs

- **Keep** pinned PVs for data you cannot lose (foundry, ghost, n8n, jellyfin config).
  They make a rebuild reattach automatically as long as the LUNs exist.
- Be aware: UUIDs are hard-coded; a deleted/recreated LUN leaves the PVC Pending.
  `volumeName` is immutable, so changing it means deleting the PVC (Argo shows a
  diff/immutable error until the PVC is recreated).
- Once Phase 1 is proven, pins are optional: a rebuild can instead provision new
  PVCs and restore into them.

## Rebuild runbook (until Phase 1 is proven)

1. Rebuild cluster; let Argo sync. PVs in `pv.yaml` may not be created by Argo if
   a PVC `volumeName` diff fails: apply them directly
   (`kubectl apply -f cluster/apps/<app>/pv.yaml`) before or right after sync.
2. For any PVC bound to a new empty PV (not the pinned one): scale/delete the pod,
   delete the PVC, let Argo recreate it so it binds to the pinned PV.
3. For unpinned apps, list LUNs in DSM (name `k8s-csi-pvc-<uid>`, description
   `<namespace>/<pvc>`), compare to `kubectl get pv`, and create a static PV with
   `csi.volumeHandle` = LUN UUID (`dsm: Library.gustend.local`, `protocol: iscsi`,
   `fsType: ext4`, `Retain`, `claimRef` to the PVC) plus `volumeName` on the PVC.
4. When several LUNs share a description, mount each read-only in a throwaway pod
   to inspect contents/size/dates before choosing. Delete the throwaway resources.
5. Verify data in the app, then clean up orphaned empty LUNs in DSM.

## Open items

- Resolved 2026-11-05: the orphaned LUNs and their iSCSI targets from the rebuild
  (3 old `test-app-pvc`, `pgdata-test-pg-0`, empty foundry LUN) were deleted. LUNs
  deleted directly through the DSM API leave their iSCSI target behind; delete the
  target too (`SYNO.Core.ISCSI.Target` delete, `target_id` JSON-quoted), and a LUN
  still mapped to a target will not delete until the target is removed.
- Resolved 2026-11-05: root `apps` OutOfSync was caused by the bootstrap `apps`
  Application and the self-managed `root-app` both rendering `cluster/root-app`.
  Fixed by deleting `apps` with `--cascade=orphan`.
- `metrics-server` was Degraded: kubelet serving certs have no IP SANs. Fixed
  with `--kubelet-insecure-tls`. Proper fix (optional): enable
  `rotate-server-certificates` in the Talos kubelet config so the existing
  kubelet-serving-cert-approver issues real certs, then drop the flag.
- Decide backup tooling for Phase 1.
