Steps:

- Install Talos on VMs and join cluster
- Deploy external-snapshotter-crd
  - `kubectl apply -k external-snapshotter-crd`
- Deploy external-snapshotter-controller
  - `kubectl apply -k external-snapshotter-crd`
- Synology CSI
  - update config/client-info.yaml credentials
  - run `./scripts/deploy.sh run`
- Install ArgoCD [readme](./argocd/readme.md)
- Cloudflared credentials.json and create secret




TODO:
- Can the snapshotter + synology csi be moved into Argo apps?
- Terraform
  - Proxmox
  - Cloudflare
