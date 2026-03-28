# Envoy Gateway Migration — Replacing ingress-nginx

## Background

The `kubernetes/ingress-nginx` repository was archived on March 24, 2026. This plan migrates the cluster from ingress-nginx to Envoy Gateway using the Kubernetes Gateway API.

### Why Envoy Gateway
- Purpose-built for Gateway API (not a bolt-on)
- Fully conformant with Gateway API v1.4.0
- CNCF project with strong ecosystem trajectory
- Clean per-Gateway isolation model (critical for external/internal split)
- All features open source — no enterprise paywall
- Extensible via SecurityPolicy, BackendTrafficPolicy CRDs if needed later

### Current State
- **ingress-nginx (external)**: `ingressClassName: external`, ClusterIP service. Cloudflared tunnel routes all external traffic here.
- **ingress-nginx-internal**: `ingressClassName: internal`, LoadBalancer service with MetalLB IP `10.1.0.22`. Wildcard DNS `*.internal.gustend.net` points here.
- **~31 total routing configs**: 6 external, ~20 internal, 5 EndpointSlice route patterns.
- **cert-manager**: DNS-01 via Cloudflare, `letsencrypt-prod` ClusterIssuer. Individual certs per internal hostname.
- **Homepage integration**: `gethomepage.dev/*` annotations on Ingress resources. Homepage supports Gateway API via `gateway: true` config.

### Target State
- **Single Envoy Gateway controller** in `envoy-gateway` namespace.
- **Two Gateway resources**: `external` (ClusterIP, HTTP-only) and `internal` (LoadBalancer via MetalLB, HTTPS with wildcard cert).
- **HTTPRoute resources** live in each app's namespace, attached to specific Gateways via `parentRefs`.
- **Wildcard cert** `*.internal.gustend.net` on the internal Gateway listener (simplification from per-hostname certs).
- **External Gateway** has no TLS (Cloudflare handles it upstream).

### Isolation Model
HTTPRoutes bind to a specific Gateway via `parentRefs`. A route attached to the `external` Gateway is only reachable through cloudflared's ClusterIP connection. A route attached to `internal` is only reachable via the MetalLB IP. There is no cross-gateway traffic path.

## Progress Summary
- Phase 0: Completed (2026-03-27)
- Phase 1: Completed (2026-03-27)
- Phase 2: Completed (2026-03-28)
- Current focus: Phase 3 ingress-nginx decommission and cleanup

---

## Phase 0 — Stand Up Envoy Gateway (Parallel to ingress-nginx)

### Status
Completed (2026-03-27)

### Goal
Install Envoy Gateway alongside the existing ingress-nginx controllers. No traffic moves yet.

### New Files

```
cluster/apps/envoy-gateway/
├── Chart.yaml                  # Helm dependency on envoy-gateway
├── values.yaml                 # Controller configuration
├── gateway-class.yaml          # GatewayClass resource
├── gateway-external.yaml       # External Gateway (ClusterIP, HTTP)
├── gateway-internal.yaml       # Internal Gateway (MetalLB temp IP, HTTPS)
└── internal-certificate.yaml   # Wildcard cert for *.internal.gustend.net
```

### Design Decisions

**GatewayClass**
- Name: `envoy-gateway`
- Controller: `gateway.envoyproxy.io/gatewayclass-controller`

**External Gateway** (`gateway-external.yaml`)
- Name: `external`
- Namespace: `envoy-gateway`
- Listener: HTTP port 80
- Hostnames: `*.gustend.net`, `gustend.net`, `*.gustin.dev`, `gustin.dev`, `*.anonafamilycounseling.com`, `anonafamilycounseling.com`
- Service type: ClusterIP (cloudflared connects to it directly by service DNS name)
- `allowedRoutes.namespaces.from: All`
- No TLS (Cloudflare handles externally)

**Internal Gateway** (`gateway-internal.yaml`)
- Name: `internal`
- Namespace: `envoy-gateway`
- Listeners:
  - HTTPS port 443, hostname `*.internal.gustend.net`, TLS terminationMode: Terminate, certificateRef to wildcard cert
  - HTTP port 80, hostname `*.internal.gustend.net` (redirect to HTTPS via HTTPRoute or policy)
- Service type: LoadBalancer
- **TEMP**: Annotated `metallb.io/loadBalancerIPs: 10.1.0.24` during pilot phase
- **FINAL**: Will be changed to `10.1.0.22` when ingress-nginx-internal is decommissioned (see Phase 3)
- `allowedRoutes.namespaces.from: All`

**Wildcard Certificate** (`internal-certificate.yaml`)
- cert-manager `Certificate` resource for `*.internal.gustend.net`
- Uses `letsencrypt-prod` ClusterIssuer (DNS-01 via Cloudflare — required for wildcards, already configured)
- Secret stored in `envoy-gateway` namespace, referenced by internal Gateway listener

**Root-app update** (`cluster/root-app/values.yaml`)
- Add entry:
  ```yaml
  - name: envoy-gateway
    namespace: envoy-gateway
    path: cluster/apps/envoy-gateway
  ```

### Validation
- [x] Envoy Gateway controller pod running in `envoy-gateway` namespace
- [x] GatewayClass accepted (`kubectl get gatewayclass`)
- [x] Both Gateways programmed (`kubectl get gateways -n envoy-gateway`)
- [x] Internal gateway has temp MetalLB IP `10.1.0.24` assigned
- [x] External gateway has ClusterIP service
- [x] Wildcard cert issued (`kubectl get certificate -n envoy-gateway`)
- [x] No impact to existing ingress-nginx traffic

Validation evidence (2026-03-27):
- Envoy pods are running in `envoy-gateway` (controller and both proxy fleets healthy).
- `GatewayClass/envoy-gateway` condition `Accepted=True`.
- `Gateway/envoy-gateway/external` and `Gateway/envoy-gateway/internal` conditions include `Programmed=True`.
- `Service/envoy-internal` is `LoadBalancer` with external IP `10.1.0.24`.
- `Service/envoy-external` is `ClusterIP` (`10.105.169.209` at validation time).
- `Certificate/internal-wildcard-gustend-net` is `Ready=True` and bound to secret `internal-wildcard-gustend-net-cert`.
- Existing ingress-nginx and ingress-nginx-internal controller pods/services remained healthy during validation.

---

## Phase 1 — Pilot: gustindev

### Status
Completed (2026-03-27)

### Goal
Route `gustin.dev` (external) and `gustindev.internal.gustend.net` (internal) through Envoy Gateway to validate pilot cutover.

### Pilot App: gustindev
This is a test/validation site (httpbin) with both external and internal ingress — ideal for validation.

### New Files

```
cluster/apps/gustindev/
├── httproute.yaml    # NEW: Two HTTPRoute resources (external + internal)
├── ingress.yaml      # REMOVED after successful pilot validation
├── deployment.yaml   # UNCHANGED
└── service.yaml      # UNCHANGED
```

**`httproute.yaml`** — External route:
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: gustindev-external
  namespace: gustindev
  annotations:
    gethomepage.dev/description: gustin.dev validation endpoint
    gethomepage.dev/enabled: "true"
    gethomepage.dev/group: Misc
    gethomepage.dev/icon: sh-httpbin
    gethomepage.dev/name: Gustin Dev Validation
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: external
      namespace: envoy-gateway
  hostnames:
    - gustin.dev
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - group: ""
          kind: Service
          name: gustindev-test
          port: 80
          weight: 1
```

**`httproute.yaml`** — Internal route (same file, `---` separated):
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: gustindev-internal
  namespace: gustindev
  annotations:
    gethomepage.dev/description: Internal gustin.dev validation endpoint
    gethomepage.dev/enabled: "true"
    gethomepage.dev/group: Misc
    gethomepage.dev/icon: sh-httpbin
    gethomepage.dev/name: Gustin Dev Validation (Internal)
    gethomepage.dev/pod-selector: app.kubernetes.io/name=gustindev-test
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: internal
      namespace: envoy-gateway
  hostnames:
    - gustindev.internal.gustend.net
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - group: ""
          kind: Service
          name: gustindev-test
          port: 80
          weight: 1
```

**ReferenceGrant** — Required for cross-namespace backend references. Since HTTPRoutes in app namespaces reference Gateways in `envoy-gateway`, and the Gateways reference services in app namespaces, a `ReferenceGrant` may be needed. Envoy Gateway's `allowedRoutes.namespaces.from: All` handles the route→gateway direction. The route→backend direction is same-namespace (HTTPRoute and Service both in `gustindev`), so no ReferenceGrant needed for backends.

### Cloudflared ConfigMap Change
Add a specific hostname rule **above** the wildcard entries for `gustin.dev`:

```yaml
ingress:
  # Pilot: route gustin.dev through Envoy Gateway
  - hostname: gustin.dev
    service: http://envoy-external-envoy-gateway.envoy-gateway.svc.cluster.local:80
  # Existing wildcard rules (still handled by ingress-nginx)
  - hostname: gustend.net
    service: http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80
  - hostname: "*.gustend.net"
    service: http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80
  # ... rest unchanged
```

Note: The exact service name for the external gateway will be determined by the Envoy Gateway Helm chart output. Verify with `kubectl get svc -n envoy-gateway` after Phase 0.

### Internal Pilot Validation
Since `*.internal.gustend.net` is a wildcard pointing at `10.1.0.22` (ingress-nginx-internal), the pilot internal route on the temp IP `10.1.0.24` won't receive traffic via the wildcard. Options:
1. **Manual test**: `curl --resolve gustindev.internal.gustend.net:443:10.1.0.24 https://gustindev.internal.gustend.net`
2. **Individual DNS override**: Add a specific DNS record for `gustindev.internal.gustend.net` → `10.1.0.24` if your internal DNS supports it.

Either way confirms the internal gateway + wildcard cert + HTTPRoute pipeline works.

### Rollback
- Remove the `gustin.dev` specific rule from cloudflared ConfigMap — traffic falls back to wildcard → ingress-nginx
- Internal: remove DNS override or stop testing against temp IP
- Old `ingress.yaml` has been removed; fallback can be restored from Git history if required

### Validation
- [x] `curl gustin.dev` returns httpbin response (via Cloudflare → cloudflared → Envoy external GW)
- [x] `curl --resolve gustindev.internal.gustend.net:443:10.1.0.24 https://gustindev.internal.gustend.net` returns httpbin response
- [x] TLS cert on internal is valid wildcard `*.internal.gustend.net`
- [x] Homepage dashboard metadata is present on HTTPRoutes (annotation scraping source)
- [x] HTTPRoutes accepted and resolved by Envoy Gateway controller

Validation evidence (2026-03-27):
- `HTTPRoute/gustindev-external` and `HTTPRoute/gustindev-internal` in namespace `gustindev` report `Accepted=True` and `ResolvedRefs=True`.
- `curl https://gustin.dev` returned `HTTP/2 200` with httpbin content.
- `curl --resolve gustindev.internal.gustend.net:443:10.1.0.24 https://gustindev.internal.gustend.net` returned `HTTP/2 200` with httpbin content.
- TLS served on `10.1.0.24:443` for `gustindev.internal.gustend.net` presents certificate `CN=*.internal.gustend.net` (issuer `Let's Encrypt R13`, SAN includes `*.internal.gustend.net`).
- `gethomepage.dev/*` annotations are present on both HTTPRoutes.

---

## Phase 2 — Migrate Remaining Apps

### Status
Completed (2026-03-28)

### Goal
Convert all remaining Ingress resources to HTTPRoute and cut over cloudflared + MetalLB to Envoy Gateway.

### Step 2a: Create HTTPRoute for Each App

For each app currently using an Ingress resource, create an `httproute.yaml` in the app's directory. The pattern follows the gustindev pilot.

**Internal app HTTPRoute template:**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <app-name>
  namespace: <app-namespace>
  annotations:
    gethomepage.dev/description: <description>
    gethomepage.dev/enabled: "true"
    gethomepage.dev/group: <group>
    gethomepage.dev/icon: sh-<icon>
    gethomepage.dev/name: <display-name>
    gethomepage.dev/pod-selector: app.kubernetes.io/name=<app-name>
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: internal
      namespace: envoy-gateway
  hostnames:
    - <service>.internal.gustend.net
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - group: ""
          kind: Service
          name: <service-name>
          port: <service-port>
          weight: 1
```

**External app HTTPRoute template:**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <app-name>
  namespace: <app-namespace>
  annotations:
    gethomepage.dev/description: <description>
    gethomepage.dev/enabled: "true"
    gethomepage.dev/group: <group>
    gethomepage.dev/icon: sh-<icon>
    gethomepage.dev/name: <display-name>
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: external
      namespace: envoy-gateway
  hostnames:
    - <service>.gustend.net
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - group: ""
          kind: Service
          name: <service-name>
          port: <service-port>
          weight: 1
```

**EndpointSlice route apps** (plex-route, sonarr-route, etc.): These already have a Service pointing at the EndpointSlice. The HTTPRoute just references that Service — same pattern, no special handling needed.

**Helm-based apps** (immich): Update `values.yaml` to disable the Helm-managed ingress and add a standalone `httproute.yaml` instead.

### Full App Migration Checklist

**External apps:**
| App | Namespace | Hostname | Port |
|-----|-----------|----------|------|
| gustindev | gustindev | gustin.dev | 80 |
| anona-counseling-page | default | anona-test-page.gustend.net, anonafamilycounseling.com | 80 |
| bp-tools | default | bptools.gustend.net | 5262 |
| planner-gen | default | planner-gen.gustend.net | 3000 |
| test-app | default | home.gustend.net, bintest.gustend.net, protectedtest.gustend.net | 80 |
| jellyfin | media | jellyfin.gustend.net | 8096 |
| kutt | default | lnk.gustend.net | 3000 |
| foundry | foundry | foundry.gustend.net | 30000 |
| ghost | ghost-k8s | blog.gustend.net | 2368 |

**Internal apps:**
| App | Namespace | Hostname | Port |
|-----|-----------|----------|------|
| homepage | homepage | home.internal.gustend.net | 80 |
| postgres-op-ui | postgres-operator | pgop.internal.gustend.net | 80 |
| mosquitto | default | mqtt.internal.gustend.net | 9001 |
| jellyseer | media | requests.internal.gustend.net | 5055 |
| komga | media | komga.internal.gustend.net | 25600 |
| tautulli | media | plex-mon.internal.gustend.net | 8181 |
| sonarr | media | sonarr.internal.gustend.net | 8989 |
| radarr | media | radarr.internal.gustend.net | 7878 |
| prowlarr | media | prowlarr.internal.gustend.net | 9696 |
| lidarr | media | lidarr.internal.gustend.net | 8686 |
| n8n | n8n | n8n.internal.gustend.net | 3000 |
| ytdl | media | ytdl.internal.gustend.net | 8945 |
| ersatztv | media | ersatztv.internal.gustend.net | 8409 |
| deluge | media | deluge.internal.gustend.net | 8112 |
| nzbget | media | nzbget.internal.gustend.net | 6789 |
| uptime-kuma | default | uptime.internal.gustend.net | 3001 |
| ntfy | ntfy | ntfy.internal.gustend.net | 80 |
| ddb-proxy | foundry | ddb-proxy.internal.gustend.net | 3000 |
| printers-aurora | default | aurora.internal.gustend.net | 80 |
| printers-bastion | default | bastion.internal.gustend.net | 80 |
| test-app | default | test.internal.gustend.net | 80 |

**Internal route apps (EndpointSlice → legacy server 10.1.10.194):**
| App | Namespace | Hostname | Legacy Port |
|-----|-----------|----------|-------------|
| plex-route | media | plex.internal.gustend.net | 32400 |
| sonarr-route | media | sonarr.internal.gustend.net | 8989 |
| radarr-route | media | radarr.internal.gustend.net | 7878 |
| deluge-route | media | deluge.internal.gustend.net | 8112 |
| nzbget-route | media | nzbget.internal.gustend.net | 7890 |

**Special route (root-app template, separate from normal internal app routes):**
| Route | Template Source | Hostname | Backend | Port | Notes |
|-------|------------------|----------|---------|------|-------|
| argocd-server | `cluster/root-app/templates/argo-route.yaml` | argocd.internal.gustend.net | argocd-server (namespace `argocd`) | 443 | Includes `BackendTLSPolicy` and is managed from root-app templates, not an app-local `cluster/apps/*/httproute.yaml` |

**Current known exception:**
- `immich.internal.gustend.net` has not been udpated as it's been removed from the cluster values.yaml. Had issues, so it will need reworking either way. 

### Step 2b: Cut Over Cloudflared (External)
Update `cluster/apps/cloudflared/ConfigMap.yaml` — replace all `ingress-nginx-controller.ingress-nginx.svc.cluster.local:80` references with the Envoy external gateway service:

```yaml
ingress:
  - hostname: gustend.net
    service: http://<envoy-external-svc>.envoy-gateway.svc.cluster.local:80
  - hostname: "*.gustend.net"
    service: http://<envoy-external-svc>.envoy-gateway.svc.cluster.local:80
  - hostname: gustin.dev
    service: http://<envoy-external-svc>.envoy-gateway.svc.cluster.local:80
  - hostname: "*.gustin.dev"
    service: http://<envoy-external-svc>.envoy-gateway.svc.cluster.local:80
  - hostname: anonafamilycounseling.com
    service: http://<envoy-external-svc>.envoy-gateway.svc.cluster.local:80
  - hostname: "*.anonafamilycounseling.com"
    service: http://<envoy-external-svc>.envoy-gateway.svc.cluster.local:80
  - service: http_status:404
```

### Step 2c: Cut Over MetalLB IP (Internal)
Update `cluster/apps/envoy-gateway/gateway-internal.yaml`:
- Change `metallb.io/loadBalancerIPs` from `10.1.0.24` (temp) to `10.1.0.22` (production)

This step requires coordinating with ingress-nginx-internal to release the IP:
1. Scale down ingress-nginx-internal controller to 0 replicas (or delete its LoadBalancer service)
2. Wait for MetalLB to release `10.1.0.22`
3. Apply the internal gateway update with `10.1.0.22`
4. Verify `10.1.0.22` is assigned to the new gateway: `kubectl get svc -n envoy-gateway`

Because `*.internal.gustend.net` is a wildcard DNS record, all internal services will cut over simultaneously at this point.

### Validation
- [x] External routes migrated and validated through Envoy external Gateway
- [x] Internal routes validated through Envoy internal Gateway on production IP `10.1.0.22`
- [x] TLS termination working via wildcard `*.internal.gustend.net` certificate on internal Gateway
- [x] Homepage annotations present on migrated HTTPRoute resources
- [x] EndpointSlice-style internal routes validated through new gateway path

Validation evidence (2026-03-28):
- HTTPRoute coverage was expanded for the previously missing targets: `bp-tools`, `planner-gen`, `test-app` (external + internal), and `printers` (aurora + bastion internal).
- Internal MetalLB cutover was completed by moving Envoy internal from temporary `10.1.0.24` to production `10.1.0.22`, then releasing the legacy ingress-nginx-internal ownership.
- ingress-nginx-internal was converted to non-LB/paused state for migration, and Envoy internal became the active LB endpoint for wildcard internal DNS traffic.
- Envoy autosync was resumed after cutover; ingress-nginx remained paused for phased decommission safety.
- Standard route validation returned expected healthy/app-auth responses across migrated services (including success responses such as `200` and expected auth/redirect responses such as `401`/`302` where applicable).
- EndpointSlice/manual-route style validations succeeded post-cutover, including restored `200` responses for `aurora.internal.gustend.net` and `bastion.internal.gustend.net` after rollback of a regression attempt.
- Noted exception during validation pass: `jellyfin` was intentionally excluded from blocker status for this phase's completion criteria.

### Phase 3 Go/No-Go Checklist

Use this checklist immediately before starting Phase 3 decommission tasks.

Go criteria (all required unless explicitly waived):
- [x] Envoy internal service is stable on `10.1.0.22`
- [x] Sampled external routes return expected outcomes (`2xx`, expected auth `401`, or expected redirect `3xx`) through Envoy external.
- [x] Sampled internal routes return expected outcomes through Envoy internal, including at least one route from each app group (media, default, foundry, ntfy, homepage).
- [x] EndpointSlice/manual-route paths are verified working (`plex-route`, `sonarr-route`, `radarr-route`, `deluge-route`, `nzbget-route`, plus printer legacy routes).
- [x] HTTPRoute status checks are clean for critical apps: `Accepted=True`, `ResolvedRefs=True`, and no persistent backend availability errors.
- [x] Wildcard TLS cert (`*.internal.gustend.net`) is `Ready=True` and actively served by Envoy internal listener.
- [x] Cloudflared points external wildcard/public host rules to Envoy external service with no stale ingress-nginx backend references.
- [x] ArgoCD app health is green for envoy and routing-related apps; intended pause state is documented for ingress-nginx apps. 
- [x] Rollback path is confirmed (ability to re-enable ingress-nginx-internal and restore prior service wiring if required).

No-go triggers (stop Phase 3 and remediate first):
- [ ] Reproducible `5xx`/timeout on critical routes without a known app-side cause.
- [ ] Any critical HTTPRoute has unresolved refs or backend-unavailable conditions that persist across retries.
- [ ] Envoy internal loses or flaps `10.1.0.22` assignment.
- [ ] TLS handshake/certificate mismatch for `*.internal.gustend.net` hosts.
- [ ] Cloudflared still routes any production external wildcard traffic to ingress-nginx.

Decision record:
- [x] Final go/no-go decision captured in PR or operations log with timestamp and approver.
- [x] Decision: GO
- [x] Timestamp: 2026-03-28 17:37:59 CDT
- [x] Approver: gustin

---

## Phase 3 — Decommission ingress-nginx

### Status
Repository cleanup completed (2026-03-28)

### Goal
Remove ingress-nginx and ingress-nginx-internal from the cluster.

### Steps

1. **Remove old Ingress resources** from each app directory (delete `ingress.yaml` files, or the ingress portions of multi-resource files).

2. **Remove ingress-nginx from root-app** — delete these entries from `cluster/root-app/values.yaml`:
   ```yaml
   - name: ingress-nginx-internal
     namespace: ingress-nginx-internal
     path: cluster/apps/ingress-nginx-internal

   - name: ingress-nginx
     namespace: ingress-nginx
     path: cluster/apps/ingress-nginx
   ```

3. **Delete ingress-nginx app directories**:
   - `cluster/apps/ingress-nginx/`
   - `cluster/apps/ingress-nginx-internal/`

4. **Update copilot-instructions.md** — Replace Ingress resource templates with HTTPRoute templates. Update the "Steps for Adding a New App" section to reference HTTPRoute + Gateway API instead of Ingress.

5. **Update external-domain-routing-via-cloudflare-tunnel.md** — The existing implementation plan references `ingress-nginx-controller.ingress-nginx.svc.cluster.local:80`. Update to reference the Envoy external gateway service.

### Validation
- [ ] ingress-nginx and ingress-nginx-internal namespaces cleaned up
- [ ] No Ingress resources remain in cluster (except any third-party Helm charts that create them)
- [ ] All traffic flowing through Envoy Gateway
- [ ] ArgoCD shows clean sync state

---

## Nginx Features — Migration Notes

Features from the ingress-nginx config blocks that need consideration:

| Feature | ingress-nginx Config | Envoy Gateway Equivalent | Action |
|---------|---------------------|--------------------------|--------|
| User-agent blocking | `block-user-agents` in ConfigMap | SecurityPolicy or Envoy filter | **Deferred** — not critical, can add later via SecurityPolicy |
| Brotli compression | `enable-brotli: "true"` | EnvoyProxy compression config | **Dropped** — marginal benefit for internal/tunneled traffic |
| Large body size | `proxy-body-size: 0`, `client-body-buffer-size: 100M` | BackendTrafficPolicy or EnvoyProxy config | **Monitor** — Envoy defaults may be sufficient; add if uploads fail |
| Real IP forwarding | `use-forwarded-headers`, `enable-real-ip` | Envoy handles X-Forwarded-For natively | **Automatic** |
| TLS protocols | `ssl-protocols: TLSv1.3 TLSv1.2` | Envoy defaults to TLS 1.2+ | **Automatic** |
| Keep-alive settings | `keep-alive: 120`, `keep-alive-requests: 10000` | Envoy connection management | **Default** — Envoy's defaults are production-grade |
| JSON access logging | Custom `log-format-upstream` | EnvoyProxy access log config | **Deferred** — can configure Envoy access logs later if needed |
| Proxy buffer size | `proxy-buffer-size: 16k` | Envoy buffer settings | **Default** — increase if large headers cause issues |
| OCSP stapling | `enable-ocsp: "true"` | Not directly available | **Dropped** — minimal impact |
| Hide server headers | `hide-headers: Server,X-Powered-By` | SecurityPolicy or response header filter | **Deferred** — add later if desired |

---

## Deferred: Blocked User Agents

User-agent blocking is intentionally out of scope for the initial Envoy Gateway migration.

Reasoning:
- Cloudflare already provides upstream filtering where it matters most for external traffic.
- This behavior is not a hard requirement for the gateway cutover.
- Deferring it keeps the migration focused on routing, TLS, and controller replacement.

If this is revisited later, the preferred implementation is an `EnvoyExtensionPolicy` with a small Lua script attached to the `external` Gateway. That approach is a good fit for case-insensitive substring matching on the `User-Agent` header.

Future enhancement notes:
- Target the `external` Gateway first
- Keep the logic GitOps-managed via ConfigMap + `EnvoyExtensionPolicy`
- Treat it as an optional edge-hardening feature, not a routing dependency

---

## Future: Observability Integration

When the Prometheus + Grafana + logging stack is built out (separate initiative), integrate Envoy Gateway metrics:
- Enable Envoy Gateway Prometheus metrics export (proxy metrics + controller metrics)
- Import official Envoy Gateway Grafana dashboards ([docs](https://gateway.envoyproxy.io/docs/tasks/observability/grafana-integration/))
- Configure Envoy proxy access logging (replaces the JSON access log format from ingress-nginx)
- Consider enabling tracing (OpenTelemetry) for request-level visibility

---

## Reference: Key Commands

```bash
# Check gateway status
kubectl get gatewayclass
kubectl get gateways -n envoy-gateway
kubectl get httproutes --all-namespaces

# Check certificate
kubectl get certificate -n envoy-gateway
kubectl describe certificate wildcard-internal -n envoy-gateway

# Check Envoy Gateway controller
kubectl get pods -n envoy-gateway
kubectl logs -n envoy-gateway -l app.kubernetes.io/name=envoy-gateway

# Verify external gateway service name (needed for cloudflared config)
kubectl get svc -n envoy-gateway

# Test internal gateway on temp IP
curl --resolve gustindev.internal.gustend.net:443:10.1.0.24 https://gustindev.internal.gustend.net

# Check HTTPRoute status
kubectl describe httproute <name> -n <namespace>
```
