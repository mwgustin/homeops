Steps:

- Install Talos on VMs and join cluster
- bootstrap:
    - `cd bootstrap`
    - Deploy external-snapshotter-crd
    - `kubectl apply -k external-snapshotter-crd`
    - Deploy external-snapshotter-controller
    - `kubectl apply -k external-snapshotter-controller`
    - Synology CSI
    - update config/client-info.yaml credentials
    - run `./scripts/deploy.sh run`
    - Install ArgoCD [readme](./bootstrap/argocd/readme.md)
- Cloudflared credentials.json and create secret
- Cloudflare API key for DNS challenge
  - Add to Cloudflare Profile
  - Add secret from cert-manager-cloudflare/secrets.yaml



TODO:
- Can the snapshotter + synology csi be moved into Argo apps?
- Terraform
  - Proxmox
  - Cloudflare
