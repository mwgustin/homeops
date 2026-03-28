# External Domain Routing via Cloudflare Tunnel

## Purpose
This implementation plan describes how to add a new primary domain that follows the existing routing pattern:

Cloudflare -> cloudflared tunnel -> Envoy external Gateway -> app-level HTTPRoute

## Prerequisite
1. Domain registration and DNS setup in Cloudflare
- Ensure the new primary domain is added to Cloudflare and ready to be routed through the existing tunnel.

## Implementation
2. Update tunnel ingress rules
- File: `cluster/apps/cloudflared/ConfigMap.yaml`
- Add both host patterns under `ingress`:
  - `<new-domain.tld>`
  - `*.<new-domain.tld>`
- Route both to:
  - `http://envoy-external.envoy-gateway.svc.cluster.local:80`

## Validation
3. Verify routing end-to-end
- Push and allow ArgoCD to reconcile.
- Confirm cloudflared accepts the new hostnames.
- Confirm requests resolve through Cloudflare to the cluster.

## Note: Per-Resource Implementation
To expose a specific app/resource on the new domain, add an external HTTPRoute hostname like:

- `<app>.<new-domain.tld>`

No app-level in-cluster certificate/TLS configuration is required for this Cloudflare tunnel routing path.
