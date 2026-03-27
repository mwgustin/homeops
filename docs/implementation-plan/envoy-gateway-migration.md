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

---

## Phase 0 — Stand Up Envoy Gateway (Parallel to ingress-nginx)

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
- **TEMP**: Annotated `metallb.io/loadBalancerIPs: 10.1.0.23` during pilot phase
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
- [ ] Envoy Gateway controller pod running in `envoy-gateway` namespace
- [ ] GatewayClass accepted (`kubectl get gatewayclass`)
- [ ] Both Gateways programmed (`kubectl get gateways -n envoy-gateway`)
- [ ] Internal gateway has temp MetalLB IP `10.1.0.23` assigned
- [ ] External gateway has ClusterIP service
- [ ] Wildcard cert issued (`kubectl get certificate -n envoy-gateway`)
- [ ] No impact to existing ingress-nginx traffic

---

## Phase 1 — Pilot: gustindev

### Goal
Route `gustin.dev` (external) and `gustindev.internal.gustend.net` (internal) through Envoy Gateway while keeping ingress-nginx as fallback.

### Pilot App: gustindev
This is a test/validation site (httpbin) with both external and internal ingress — ideal for validation.

### New Files

```
cluster/apps/gustindev/
├── httproute.yaml    # NEW: Two HTTPRoute resources (external + internal)
├── ingress.yaml      # KEEP: Existing ingress as rollback
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
    - name: external
      namespace: envoy-gateway
  hostnames:
    - gustin.dev
  rules:
    - backendRefs:
        - name: gustindev-test
          port: 80
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
    - name: internal
      namespace: envoy-gateway
  hostnames:
    - gustindev.internal.gustend.net
  rules:
    - backendRefs:
        - name: gustindev-test
          port: 80
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
Since `*.internal.gustend.net` is a wildcard pointing at `10.1.0.22` (ingress-nginx-internal), the pilot internal route on the temp IP `10.1.0.23` won't receive traffic via the wildcard. Options:
1. **Manual test**: `curl --resolve gustindev.internal.gustend.net:443:10.1.0.23 https://gustindev.internal.gustend.net`
2. **Individual DNS override**: Add a specific DNS record for `gustindev.internal.gustend.net` → `10.1.0.23` if your internal DNS supports it.

Either way confirms the internal gateway + wildcard cert + HTTPRoute pipeline works.

### Rollback
- Remove the `gustin.dev` specific rule from cloudflared ConfigMap — traffic falls back to wildcard → ingress-nginx
- Internal: remove DNS override or stop testing against temp IP
- Old `ingress.yaml` is still in place and functional

### Validation
- [ ] `curl gustin.dev` returns httpbin response (via Cloudflare → cloudflared → Envoy external GW)
- [ ] `curl --resolve gustindev.internal.gustend.net:443:10.1.0.23 https://gustindev.internal.gustend.net` returns httpbin response
- [ ] TLS cert on internal is valid wildcard `*.internal.gustend.net`
- [ ] Homepage dashboard shows gustindev entries (confirms annotation scraping from HTTPRoute)
- [ ] Old ingress.yaml still works as fallback path

---

## Phase 2 — Migrate Remaining Apps

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
    - name: internal
      namespace: envoy-gateway
  hostnames:
    - <service>.internal.gustend.net
  rules:
    - backendRefs:
        - name: <service-name>
          port: <service-port>
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
    - name: external
      namespace: envoy-gateway
  hostnames:
    - <service>.gustend.net
  rules:
    - backendRefs:
        - name: <service-name>
          port: <service-port>
```

**EndpointSlice route apps** (plex-route, sonarr-route, etc.): These already have a Service pointing at the EndpointSlice. The HTTPRoute just references that Service — same pattern, no special handling needed.

**Helm-based apps** (immich): Update `values.yaml` to disable the Helm-managed ingress and add a standalone `httproute.yaml` instead.

### Full App Migration Checklist

**External apps:**
| App | Namespace | Hostname | Port |
|-----|-----------|----------|------|
| gustindev | gustindev | gustin.dev | 80 |
| anona-counseling-page | default | anona-test-page.gustend.net, anonafamilycounseling.com | 80 |
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

**Internal route apps (EndpointSlice → legacy server 10.1.10.194):**
| App | Namespace | Hostname | Legacy Port |
|-----|-----------|----------|-------------|
| plex-route | media | plex.internal.gustend.net | 32400 |
| sonarr-route | media | sonarr.internal.gustend.net | 8989 |
| radarr-route | media | radarr.internal.gustend.net | 7878 |
| deluge-route | media | deluge.internal.gustend.net | 8112 |
| nzbget-route | media | nzbget.internal.gustend.net | 7890 |

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
- Change `metallb.io/loadBalancerIPs` from `10.1.0.23` (temp) to `10.1.0.22` (production)

This step requires coordinating with ingress-nginx-internal to release the IP:
1. Scale down ingress-nginx-internal controller to 0 replicas (or delete its LoadBalancer service)
2. Wait for MetalLB to release `10.1.0.22`
3. Apply the internal gateway update with `10.1.0.22`
4. Verify `10.1.0.22` is assigned to the new gateway: `kubectl get svc -n envoy-gateway`

Because `*.internal.gustend.net` is a wildcard DNS record, all internal services will cut over simultaneously at this point.

### Validation
- [ ] All external apps reachable via their public domains
- [ ] All internal apps reachable via `*.internal.gustend.net`
- [ ] TLS working on all internal apps (wildcard cert)
- [ ] Homepage showing all services correctly
- [ ] EndpointSlice route apps (plex-route, etc.) working through new gateway

---

## Phase 3 — Decommission ingress-nginx

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
curl --resolve gustindev.internal.gustend.net:443:10.1.0.23 https://gustindev.internal.gustend.net

# Check HTTPRoute status
kubectl describe httproute <name> -n <namespace>
```
