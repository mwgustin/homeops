# HomeOps Project Architecture Blueprint

> **Generated:** March 29, 2026  
> **Repository:** homeops-final-final  
> **Technology Stack:** Proxmox VE, Kubernetes (Talos), ArgoCD, Envoy Gateway, Azure Key Vault, Terraform  
> **Architecture Pattern:** GitOps with App-of-Apps

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Overview](#2-architecture-overview)
3. [Architecture Visualization](#3-architecture-visualization)
4. [Core Architectural Components](#4-core-architectural-components)
5. [Architectural Layers and Dependencies](#5-architectural-layers-and-dependencies)
6. [Data Architecture](#6-data-architecture)
7. [Cross-Cutting Concerns](#7-cross-cutting-concerns)
8. [Service Communication Patterns](#8-service-communication-patterns)
9. [Technology-Specific Patterns](#9-technology-specific-patterns)
10. [Implementation Patterns](#10-implementation-patterns)
11. [Testing Architecture](#11-testing-architecture)
12. [Deployment Architecture](#12-deployment-architecture)
13. [Extension and Evolution Patterns](#13-extension-and-evolution-patterns)
14. [Architectural Pattern Examples](#14-architectural-pattern-examples)
15. [Architectural Decision Records](#15-architectural-decision-records)
16. [Architecture Governance](#16-architecture-governance)
17. [Blueprint for New Development](#17-blueprint-for-new-development)

---

## 1. Executive Summary

### Project Purpose
HomeOps is a **production-grade home Kubernetes infrastructure** managed through GitOps principles. It provides a declarative, reproducible platform for running self-hosted applications including media servers, automation tools, web applications, and development services.

### Guiding Principles
- **GitOps Source of Truth**: All cluster state is defined in Git; manual changes are automatically reconciled
- **Declarative Infrastructure**: Infrastructure and applications are defined as code (IaC)
- **Security by Default**: External secrets management, TLS everywhere, network segmentation
- **Minimal OS Footprint**: Talos Linux eliminates traditional OS attack surface
- **Separation of Concerns**: Platform services, application workloads, routing, storage, and secrets are managed as distinct layers with clear boundaries
- **Self-Healing**: Automatic drift detection and correction

### Technology Stack Summary

| Layer | Technology | Purpose |
|-------|------------|---------|
| **Virtualization** | Proxmox VE | Hypervisor platform hosting the Talos control plane and worker nodes |
| **Operating System** | Talos Linux | Immutable, minimal Kubernetes OS |
| **Kubernetes** | v1.33.4 | Container orchestration |
| **GitOps** | ArgoCD | Continuous deployment and reconciliation |
| **Gateway** | Envoy Gateway | Ingress/egress traffic management |
| **Secrets** | External Secrets + Azure Key Vault | Secure credential management |
| **Storage** | Synology CSI (iSCSI) + NFS | Persistent storage. iSCSI for internal persistent storage (config, DBs, etc), NFS for shared resources (media, shared downloads/processing, etc) |
| **Certificates** | cert-manager (internal) + Cloudflare edge certs (external) | Internal ingress TLS is managed in-cluster; external TLS is terminated and managed by Cloudflare pre-tunnel |
| **Load Balancing** | MetalLB | Internal LAN/VPN ingress IPs for the Envoy internal gateway |
| **Infrastructure** | Terraform + Terraform Cloud | Cloud resource provisioning |
| **Tunneling** | Cloudflared | External ingress only via Cloudflare Tunnel to the Envoy external gateway |

---

## 2. Architecture Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                               ACCESS PATHS                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│  Internet (external only) ──► Cloudflare ──► cloudflared tunnel ──► Envoy  │
│  External Gateway                                                           │
│  VPN/LAN (internal only) ──► MetalLB IP ──► Envoy Internal Gateway         │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
┌─────────────────────────────────────┴───────────────────────────────────────┐
│                           KUBERNETES CLUSTER                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   ArgoCD    │  │ cert-manager│  │  MetalLB    │  │ext-secrets  │        │
│  │  (GitOps)   │  │   (TLS)     │  │   (L4 LB)   │  │  (secrets)  │        │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘        │
│                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                        APPLICATION WORKLOADS                          │  │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐        │  │
│  │  │ Media   │ │Automation│ │  Web    │ │Database │ │ Tools   │        │  │
│  │  │ Stack   │ │  (n8n)   │ │ (Ghost) │ │(Postgres)│ │(Homepage)│       │  │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘        │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
┌─────────────────────────────────────┴───────────────────────────────────────┐
│                           STORAGE & SECRETS                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐    ┌─────────────────────┐                         │
│  │   Synology NAS      │    │   Azure Key Vault   │                         │
│  │  • iSCSI (CSI)      │    │  • Application Secrets                        │
│  │  • NFS (Media)      │    │  • SOPS Encryption Keys                       │
│  └─────────────────────┘    └─────────────────────┘                         │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Directory Structure

```
homeops-final-final/
├── bootstrap/                    # Initial cluster setup (manual apply)
│   ├── external-snapshotter-crd/    # CSI snapshot CRDs
│   ├── external-snapshotter-controller/  # Snapshot controller
│   └── synology-csi-talos/          # Synology CSI driver
│
├── cluster/                      # GitOps-managed resources
│   ├── apps/                        # Application manifests (50+ apps)
│   │   ├── argo-cd/                    # ArgoCD configuration
│   │   ├── envoy-gateway/              # Gateway infrastructure
│   │   ├── external-secrets/           # ESO operator
│   │   ├── azkv-secret-store/          # Azure KV integration
│   │   ├── jellyfin/                   # Media server
│   │   ├── n8n/                        # Automation
│   │   └── ...                         # 45+ more applications
│   │
│   ├── infra/                       # Terraform infrastructure
│   │   ├── main/                       # Production Azure resources
│   │   └── mgmt/                       # Management/SOPS infrastructure
│   │
│   └── root-app/                    # ArgoCD app-of-apps
│       ├── Chart.yaml
│       ├── values.yaml                 # Application registry
│       └── templates/                  # ApplicationSet generators
│
├── talos/                        # Talos cluster configuration
│   ├── Readme.md                    # Bootstrap instructions
│   └── _out/                        # Generated configs
│
├── docs/                         # Documentation
├── Taskfile.yaml                 # Task automation
└── renovate.json                 # Dependency updates
```

---

## 3. Architecture Visualization

### Component Interaction Diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              GITOPS FLOW                                      │
└──────────────────────────────────────────────────────────────────────────────┘

  GitHub Repository                ArgoCD                    Kubernetes
  ┌─────────────┐              ┌─────────────┐            ┌─────────────┐
  │  homeops    │   webhook    │   root-app  │   sync     │  Namespaces │
  │  main branch├─────────────►│   (App of   ├───────────►│  & Resources│
  │             │              │    Apps)    │            │             │
  └─────────────┘              └──────┬──────┘            └─────────────┘
                                      │
                          ┌───────────┼───────────┐
                          │           │           │
                          ▼           ▼           ▼
                   ┌──────────┐ ┌──────────┐ ┌──────────┐
                   │ Wave 0   │ │ Wave 1   │ │ Wave N   │
                   │ metallb  │ │ envoy-gw │ │ apps...  │
                   │ cert-mgr │ │ secrets  │ │          │
                   └──────────┘ └──────────┘ └──────────┘
```

### Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           EXTERNAL REQUEST FLOW                              │
└─────────────────────────────────────────────────────────────────────────────┘

Public Internet Request (*.gustend.net):
┌────────┐    ┌───────────┐    ┌───────────┐    ┌────────────┐    ┌─────────┐
│Internet├───►│Cloudflare ├───►│cloudflared├───►│ Envoy      ├───►│ App     │
│        │    │   CDN     │    │  tunnel   │    │ External   │    │ Service │
└────────┘    └───────────┘    └───────────┘    │ Gateway    │    └─────────┘
                                                └────────────┘

Internal Request (*.internal.gustend.net):
┌────────┐    ┌────────────┐    ┌─────────┐
│VPN/LAN ├───►│ Envoy      ├───►│ App     │
│        │    │ Internal   │    │ Service │
└────────┘    │ Gateway    │    └─────────┘
              └────────────┘
```

### Storage Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           STORAGE ARCHITECTURE                               │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────┐    ┌──────────────────────────────────┐
│      SYNOLOGY NAS (iSCSI)        │    │       SYNOLOGY NAS (NFS)         │
│      library.gustend.local       │    │       library.gustend.local      │
├──────────────────────────────────┤    ├──────────────────────────────────┤
│                                  │    │                                  │
│  ┌─────────────────────────┐     │    │  ┌─────────────────────────┐     │
│  │   synology-iscsi        │     │    │  │   nfs.csi.k8s.io        │     │
│  │   StorageClass          │     │    │  │   StorageClass          │     │
│  └───────────┬─────────────┘     │    │  └───────────┬─────────────┘     │
│              │                   │    │              │                   │
│  Used by:    │                   │    │  Used by:    │                   │
│  • jellyfin-config (5Gi)         │    │  • jellyfin-media (100Gi)        │
│  • n8n (5Gi)                     │    │  • radarr-media                  │
│  • komga (10Gi)                  │    │  • sonarr-media                  │
│  • foundry (10Gi)                │    │  • lidarr-media                  │
│  • uptime-kuma (5Gi)             │    │  • nzbget-downloads              │
│  • kutt (5Gi)                    │    │  • deluge-downloads              │
│                                  │    │                                  │
│  AccessMode: ReadWriteOnce       │    │  AccessMode: ReadWriteMany       │
└──────────────────────────────────┘    └──────────────────────────────────┘
```

---

## 4. Core Architectural Components

### 4.1 GitOps Layer (ArgoCD)

**Purpose:** Continuous deployment, drift detection, and reconciliation

**Internal Structure:**
- `cluster/apps/argo-cd/` - ArgoCD installation via Kustomize
- `cluster/root-app/` - App-of-apps Helm chart
- `cluster/root-app/values.yaml` - Application registry

**Interaction Patterns:**
- Watches GitHub repository for changes
- Generates child Applications via ApplicationSet pattern
- Self-manages its own deployment
- Exposes UI via internal HTTPRoute

**Key Files:**
```
cluster/root-app/
├── Chart.yaml                    # Helm chart metadata
├── values.yaml                   # Application definitions (60+ apps)
└── templates/
    ├── app-set.yaml              # ApplicationSet for local apps
    ├── repo-app-set.yaml         # ApplicationSet for external repos
    ├── argo-cd.yaml              # ArgoCD self-management
    ├── argo-route.yaml           # ArgoCD UI routing
    ├── namespaces.yaml           # Pre-created namespaces
    └── root-app.yaml             # Bootstrap Application
```

### 4.2 Gateway Layer (Envoy Gateway)

**Purpose:** L7 traffic routing, TLS termination, access control

**Internal Structure:**
- Helm chart deployment: `gateway-helm:v1.7.1`
- Two Gateway instances: `internal` and `external`
- Internal gateway TLS certificates are managed in-cluster via cert-manager
- External ingress TLS is terminated at Cloudflare and is not cluster-managed

**Key Resources:**
```
cluster/apps/envoy-gateway/
├── Chart.yaml                    # Helm dependency
├── values.yaml                   # Envoy configuration
└── templates/
    ├── gateway-class.yaml        # GatewayClass definition
    ├── gateway-internal.yaml     # Internal gateway (*.internal.gustend.net)
    ├── gateway-external.yaml     # External gateway (*.gustend.net)
    ├── envoyproxy-internal.yaml  # Envoy proxy config
    ├── envoyproxy-external.yaml  # Envoy proxy config
    └── internal-wildcard-certificate.yaml  # TLS cert
```

### 4.3 Secrets Management Layer

**Purpose:** Secure credential storage and injection

**Architecture:**
```
Azure Key Vault (gustend-k8s-cluster)
        │
        ▼
ClusterSecretStore (azure-secret-store)
        │
        ▼
ExternalSecret (per-app)
        │
        ▼
Kubernetes Secret (injected into pods)
```

**Key Files:**
```
cluster/apps/azkv-secret-store/
└── keyvault-secret-store.yaml    # ClusterSecretStore definition

cluster/apps/external-secrets/
├── Chart.yaml                    # ESO Helm chart
└── values.yaml                   # ESO configuration
```

### 4.4 Storage Layer

**Purpose:** Persistent storage provisioning

**Components:**
1. **Synology CSI Driver** (iSCSI)
   - Location: `bootstrap/synology-csi-talos/`
   - StorageClass: `synology-iscsi`
   - Use case: App configuration, databases, single-pod access

2. **NFS CSI Driver**
   - Location: `cluster/apps/csi-driver-nfs/`
   - StorageClass: Custom per-app (e.g., `jellyfin-nfs-library-media`)
   - Use case: Shared media libraries, multi-pod access

### 4.5 Certificate Management

**Purpose:** Automated TLS certificate provisioning for internal ingress only

**Architecture:**
```
Internal DNS / Cloudflare DNS validation (for internal cert issuance)
      │
      ▼
cert-manager (DNS01 challenge)
      │
      ▼
Internal certificate resources
      │
      ▼
Envoy internal gateway TLS listeners
```

**External Ingress TLS:**
- External TLS certificates are handled by Cloudflare at the edge before traffic enters the cloudflared tunnel
- External certificate lifecycle is not managed by this cluster

**Key Files:**
```
cluster/apps/cert-manager/
├── Chart.yaml                    # cert-manager Helm chart
└── values.yaml

cluster/apps/cert-manager-cloudflare/
├── certificate.yaml              # Internal certificate definitions
├── cluster-issuer.yaml           # Issuer used for internal certificate automation
└── secrets.yaml                  # Credentials for internal certificate automation
```

---

## 5. Architectural Layers and Dependencies

### Layer Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          LAYER 5: APPLICATIONS                               │
│  jellyfin, radarr, sonarr, n8n, ghost, homepage, foundry, etc.              │
│  Dependencies: Gateway routes, Storage PVCs, Secrets                         │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          LAYER 4: SERVICES                                   │
│  postgres-operator, mongodb-operator                                         │
│  Dependencies: Storage, Secrets                                              │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          LAYER 3: PLATFORM                                   │
│  envoy-gateway, external-secrets, cert-manager                               │
│  Dependencies: MetalLB, CRDs                                                 │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          LAYER 2: INFRASTRUCTURE                             │
│  metallb, csi-driver-nfs, csi-driver-smb, metrics-server                    │
│  Dependencies: Kubernetes API                                                │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          LAYER 1: BOOTSTRAP                                  │
│  synology-csi, external-snapshotter-crd, external-snapshotter-controller    │
│  Applied manually before ArgoCD                                              │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          LAYER 0: CLUSTER                                    │
│  Talos Linux, Kubernetes v1.33.4                                            │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Sync Wave Ordering

ArgoCD uses sync waves to enforce deployment order:

| Wave | Components | Purpose |
|------|------------|---------|
| **0** | metallb, cert-manager, csi-drivers | Core infrastructure |
| **1** | envoy-gateway, external-secrets | Platform services |
| **2+** | All applications | User workloads |

---

## 6. Data Architecture

### Storage Patterns

**1. iSCSI Storage (synology-iscsi)**
```yaml
# Single-pod application data
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-config
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: synology-iscsi
  resources:
    requests:
      storage: 5Gi
```

**2. NFS Storage (shared media)**
```yaml
# Multi-pod shared access
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: jellyfin-nfs-library-media
provisioner: nfs.csi.k8s.io
parameters:
  server: library.gustend.local
  share: /volume1/Media
mountOptions:
  - nolock

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jellyfin-media
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: jellyfin-nfs-library-media
  resources:
    requests:
      storage: 100Gi
```

### Database Patterns

**PostgreSQL (via postgres-operator):**
- Operator-managed clusters
- Automatic failover and backups
- Used by: n8n, ghost, kutt

**MongoDB (via mongodb-operator):**
- Operator-managed deployments
- Used by: specialized applications

---

## 7. Cross-Cutting Concerns

### 7.1 Authentication & Authorization

**Current Implementation:**
- No cluster-wide authentication layer (individual app auth)
- ArgoCD: Built-in authentication
- Individual apps: App-specific auth (basic auth, OAuth, etc.)

**Network Security:**
- Internal gateway: VPN/LAN access only, exposed through MetalLB-assigned internal addresses
- External gateway: Internet access only through Cloudflare tunnel (cloudflared) with origin certificates

### 7.2 Error Handling & Resilience

**ArgoCD Retry Policy:**
```yaml
retry:
  limit: 10
  backoff:
    duration: 1m
    maxDuration: 16m
    factor: 2
```

**Self-Healing:**
```yaml
syncPolicy:
  automated:
    prune: true      # Remove orphaned resources
    selfHeal: true   # Auto-sync on drift
```

### 7.3 Logging & Monitoring

**Current Implementation:**
- `metrics-server`: Cluster metrics for HPA
- `uptime-kuma`: External uptime monitoring
- `tautulli`: Plex-specific monitoring

**Future Considerations:**
- Prometheus stack (commented in values.yaml)
- Grafana dashboards

### 7.4 Configuration Management

**Patterns:**
1. **ConfigMaps**: Non-sensitive configuration
2. **ExternalSecrets**: Sensitive configuration from Azure Key Vault
3. **Helm values.yaml**: Chart-specific configuration
4. **Environment variables**: Runtime configuration

### 7.5 Secret Management

**Azure Key Vault Integration:**
```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: app-secret
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: azure-secret-store
    kind: ClusterSecretStore
  target:
    name: app-secret
    creationPolicy: Owner
    deletionPolicy: Retain
  data:
    - secretKey: api-key
      remoteRef:
        conversionStrategy: Default
        decodingStrategy: None
        key: app-api-key
        metadataPolicy: None
```

---

## 8. Service Communication Patterns

### Internal Service Communication

**Pattern:** Kubernetes DNS-based service discovery
```
Service A ──► service-b.namespace.svc.cluster.local:port
```

### External Access Patterns

**1. Cloudflare Tunnel (Public, External Access Only)**
```
Internet ──► Cloudflare ──► cloudflared ──► Envoy External ──► Service
```

**2. Direct Internal (VPN/LAN, Internal Access Only)**
```
VPN Client ──► MetalLB IP ──► Envoy Internal ──► Service
```

**3. Legacy Proxy Pattern**
For services running outside the cluster:
```yaml
# EndpointSlice pointing to external IP
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: plex-external
  labels:
    kubernetes.io/service-name: plex-external
addressType: IPv4
endpoints:
  - addresses:
      - "10.1.10.194"
ports:
  - name: http
    port: 32400
```

### API Patterns

**HTTPRoute-based routing:**
- Path-based routing: `path: PathPrefix /api`
- Host-based routing: `hostnames: [app.gustend.net]`
- Backend weighting for canary deployments

---

## 9. Technology-Specific Patterns

### 9.1 Kubernetes Patterns

**Deployment Strategy:**
```yaml
# Stateful apps (media servers)
spec:
  strategy:
    type: Recreate

# Stateless apps (web servers)
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
```

**Resource Management:**
```yaml
resources:
  requests:
    cpu: "100m"
    memory: "256Mi"
  limits:
    cpu: "1000m"
    memory: "2Gi"
```

**Pod Security:**
```yaml
securityContext:
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  allowPrivilegeEscalation: false
```

### 9.2 Helm Chart Patterns

**Wrapper Chart Pattern:**
```yaml
# Chart.yaml
apiVersion: v2
name: app-name
version: 1.0.0
dependencies:
  - name: upstream-chart
    version: "1.2.3"
    repository: https://charts.example.com

# values.yaml - values passed under dependency key
upstream-chart:
  setting: value
```

### 9.3 Gateway API Patterns

**HTTPRoute with Homepage Integration:**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app-name
  namespace: <app-namespace>
  labels:
    app.kubernetes.io/name: app-name
  annotations:
    gethomepage.dev/description: "App Description"
    gethomepage.dev/enabled: "true"
    gethomepage.dev/group: "Category"
    gethomepage.dev/icon: "sh-app-name"
    gethomepage.dev/name: "Display Name"
    gethomepage.dev/pod-selector: "app.kubernetes.io/name=app-name"
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: internal
      namespace: envoy-gateway
  hostnames:
    - app.internal.gustend.net
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - group: ""
          kind: Service
          name: app-name
          port: 8080
          weight: 1
```

---

## 10. Implementation Patterns

### 10.1 Standard Application Structure

**Raw Manifest App (Recommended for most apps):**
```
cluster/apps/app-name/
├── deployment.yaml       # Required: Application workload
├── service.yaml          # Required: Service exposure
├── httproute.yaml        # Required: Gateway routing
├── pvc.yaml              # Optional: Persistent storage
├── storage-class.yaml    # Optional: Custom NFS storage
├── pv.yaml               # Optional: Manual PV (NFS only)
├── external-secret.yaml  # Optional: Secrets from Azure KV
└── config-map.yaml       # Optional: Non-sensitive config
```

**Helm Chart App (For complex upstream charts):**
```
cluster/apps/app-name/
├── Chart.yaml            # Required: Helm chart definition
├── values.yaml           # Required: Configuration values
└── templates/            # Optional: Additional resources
    └── httproute.yaml
```

### 10.2 Service Naming Conventions

| Resource | Naming Pattern | Example |
|----------|----------------|---------|
| Deployment | `{app-name}` | `jellyfin` |
| Service | `{app-name}` | `jellyfin` |
| HTTPRoute | `{app-name}` | `jellyfin` |
| PVC (config) | `{app-name}` or `{app-name}-config` | `jellyfin-config` |
| PVC (data) | `{app-name}-{type}` | `jellyfin-media` |
| StorageClass | `{app-name}-nfs-{source}` | `jellyfin-nfs-library-media` |
| Namespace | `{app-name}` or `{category}` | `media`, `n8n` |

### 10.3 Label Standards

```yaml
metadata:
  labels:
    app.kubernetes.io/name: app-name
    app.kubernetes.io/instance: app-name
    app.kubernetes.io/component: server  # optional
    app.kubernetes.io/part-of: app-name  # optional
```

---

## 11. Testing Architecture

### Current Testing Approach

**Manual Verification:**
1. ArgoCD sync status monitoring
2. kubectl health checks
3. uptime-kuma external monitoring

**Recommended Testing Workflow:**
```bash
# 1. Validate manifests locally
kubectl --dry-run=client -f deployment.yaml

# 2. Apply to staging namespace (if available)
kubectl apply -f . -n staging

# 3. Monitor ArgoCD sync
argocd app get app-name

# 4. Verify endpoints
curl -I https://app.internal.gustend.net
```

### Validation Patterns

**ArgoCD Health Checks:**
- Deployment: Ready replicas match desired
- Service: Endpoints populated
- PVC: Bound status
- HTTPRoute: Accepted by gateway

---

## 12. Deployment Architecture

### Cluster Topology

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         TALOS KUBERNETES CLUSTER                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Control Plane Node (10.1.9.138)                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  etcd │ kube-apiserver │ kube-controller-manager │ kube-scheduler   │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  Worker Nodes                                                                │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │
│  │  Worker 1       │  │  Worker 2       │  │  Worker N       │             │
│  │  • kubelet      │  │  • kubelet      │  │  • kubelet      │             │
│  │  • kube-proxy   │  │  • kube-proxy   │  │  • kube-proxy   │             │
│  │  • CSI node     │  │  • CSI node     │  │  • CSI node     │             │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘             │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Deployment Workflow

```
1. Developer commits to main branch
          │
          ▼
2. GitHub triggers ArgoCD webhook (optional)
          │
          ▼
3. ArgoCD detects out-of-sync state
          │
          ▼
4. Sync waves execute in order (0 → 1 → N)
          │
          ▼
5. Resources created/updated
          │
          ▼
6. Health checks pass
          │
          ▼
7. Continuous reconciliation (every 3 minutes)
```

### Environment Configuration

**Production (only environment):**
- Cluster: Talos v1.10.7, Kubernetes v1.33.4
- Gateway domains: `*.gustend.net`, `*.internal.gustend.net`
- Storage: Synology NAS (library.gustend.local)
- Secrets: Azure Key Vault (gustend-k8s-cluster)

---

## 13. Extension and Evolution Patterns

### Adding a New Application

**Step-by-Step Process:**

1. **Create app directory:**
   ```bash
   mkdir cluster/apps/new-app
   ```

2. **Create deployment.yaml:**
   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: new-app
     labels:
       app.kubernetes.io/name: new-app
   spec:
     replicas: 1
     revisionHistoryLimit: 1
     selector:
       matchLabels:
         app.kubernetes.io/name: new-app
     template:
       metadata:
         labels:
           app.kubernetes.io/name: new-app
       spec:
         containers:
           - name: new-app
             image: registry/new-app:tag
             ports:
               - containerPort: 8080
             resources:
               requests:
                 cpu: "100m"
                 memory: "256Mi"
               limits:
                 cpu: "500m"
                 memory: "512Mi"
   ```

3. **Create service.yaml:**
   ```yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: new-app
     labels:
       app.kubernetes.io/name: new-app
   spec:
     type: ClusterIP
     ports:
       - port: 8080
         targetPort: 8080
         protocol: TCP
         name: http
     selector:
       app.kubernetes.io/name: new-app
   ```

4. **Create httproute.yaml:**
   ```yaml
   apiVersion: gateway.networking.k8s.io/v1
   kind: HTTPRoute
   metadata:
     name: new-app
     namespace: <app-namespace>
     labels:
       app.kubernetes.io/name: new-app
     annotations:
       gethomepage.dev/description: "New App description"
       gethomepage.dev/enabled: "true"
       gethomepage.dev/group: "Applications"
       gethomepage.dev/icon: "sh-new-app"
       gethomepage.dev/name: "New App"
       gethomepage.dev/pod-selector: app.kubernetes.io/name=new-app
   spec:
     parentRefs:
       - group: gateway.networking.k8s.io
         kind: Gateway
         name: internal
         namespace: envoy-gateway
     hostnames:
       - new-app.internal.gustend.net
     rules:
       - matches:
           - path:
               type: PathPrefix
               value: /
         backendRefs:
           - group: ""
             kind: Service
             name: new-app
             port: 8080
             weight: 1
   ```

5. **Register in root-app/values.yaml:**

   > **Note:** Set `namespace` to the dedicated namespace for this app (e.g., `new-app`), or an existing shared namespace (e.g., `media`). Namespaces are managed by ArgoCD — never use `default`.

   ```yaml
   apps:
     # ... existing apps ...
     - name: new-app
       namespace: new-app
       path: cluster/apps/new-app
   ```

6. **Commit and push:**
   ```bash
   git add cluster/apps/new-app cluster/root-app/values.yaml
   git commit -m "Add new-app"
   git push
   ```

### Adding External Secrets

```yaml
# cluster/apps/new-app/external-secret.yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: new-app-secret
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: azure-secret-store
    kind: ClusterSecretStore
  target:
    name: new-app-secret
    creationPolicy: Owner
    deletionPolicy: Retain
  data:
    - secretKey: api-key
      remoteRef:
        conversionStrategy: Default
        decodingStrategy: None
        key: new-app-api-key
        metadataPolicy: None
```

### Adding Persistent Storage

**iSCSI (single-pod):**
```yaml
# cluster/apps/new-app/pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: new-app-data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: synology-iscsi
  resources:
    requests:
      storage: 10Gi
```

**NFS (shared access):**
```yaml
# cluster/apps/new-app/storage-class.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: new-app-nfs-media
provisioner: nfs.csi.k8s.io
parameters:
  server: library.gustend.local
  share: /volume1/Media
mountOptions:
  - nolock

---
# cluster/apps/new-app/pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: new-app-media
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: new-app-nfs-media
  resources:
    requests:
      storage: 100Gi

---
# cluster/apps/new-app/pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: new-app-media
spec:
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  nfs:
    server: library.gustend.local
    path: /volume1/Media
  storageClassName: new-app-nfs-media
```

---

## 14. Architectural Pattern Examples

### Example 1: Media Server (Jellyfin)

**File Structure:**
```
cluster/apps/jellyfin/
├── deployment.yaml
├── service.yaml
├── httproute.yaml
├── pvc.yaml         (iSCSI config PVC and NFS media PVC)
├── storage-class.yaml (NFS StorageClass)
└── pv.yaml          (NFS PersistentVolume)
```

**Key Patterns:**
- Recreate deployment strategy (media transcoding)
- Dual storage: iSCSI for config, NFS for media
- External gateway (public access)

### Example 2: Automation Platform (n8n)

**File Structure:**
```
cluster/apps/n8n/
├── deployment.yaml
├── service.yaml
├── httproute.yaml
├── pvc.yaml
└── namespace.yaml
```

**Key Patterns:**
- Own namespace for isolation
- PostgreSQL database connection
- Internal gateway only

### Example 3: Helm-based Infrastructure (Envoy Gateway)

**File Structure:**
```
cluster/apps/envoy-gateway/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── gateway-class.yaml
    ├── gateway-internal.yaml
    ├── gateway-external.yaml
    └── ...
```

**Key Patterns:**
- Upstream Helm chart as dependency
- Custom templates for gateway resources
- Sync wave 1 (depends on cert-manager)

---

## 15. Architectural Decision Records

### ADR-001: GitOps with ArgoCD

**Context:** Need automated, auditable deployments with drift detection.

**Decision:** Use ArgoCD with app-of-apps pattern.

**Consequences:**
- ✅ All changes tracked in Git
- ✅ Automatic reconciliation
- ✅ Self-healing capabilities
- ⚠️ Learning curve for ArgoCD
- ⚠️ Need to manage sync waves carefully

### ADR-002: Talos Linux for Nodes

**Context:** Need secure, minimal OS for Kubernetes nodes.

**Decision:** Use Talos Linux instead of traditional distributions.

**Consequences:**
- ✅ Immutable, secure by design
- ✅ API-driven configuration
- ✅ No SSH, reduced attack surface
- ⚠️ Debugging requires different approach
- ⚠️ Some CSI drivers need adaptation

### ADR-003: Gateway API over Ingress

**Context:** Need modern, expressive routing capabilities.

**Decision:** Use Gateway API with Envoy Gateway instead of Ingress.

**Consequences:**
- ✅ More expressive routing rules
- ✅ Better separation of concerns
- ✅ Multi-tenancy support
- ⚠️ Newer API, less ecosystem support
- ⚠️ Two gateways to manage

### ADR-004: External Secrets with Azure Key Vault

**Context:** Need secure secret management integrated with cloud.

**Decision:** Use External Secrets Operator with Azure Key Vault backend.

**Consequences:**
- ✅ Secrets never stored in Git
- ✅ Automatic rotation support
- ✅ Audit trail in Azure
- ⚠️ Azure dependency
- ⚠️ Additional infrastructure to manage

### ADR-005: Proxmox for Virtualization Layer

**Context:** Physical hardware must be virtualized to host Kubernetes nodes with flexible resource allocation, easy VM lifecycle management, and snapshot/backup capabilities.

**Decision:** Use Proxmox VE as the bare-metal hypervisor to host Talos Linux VMs that form the Kubernetes cluster.

**Consequences:**
- ✅ Free, open-source hypervisor with enterprise features
- ✅ Native support for VM snapshots and backups
- ✅ Web UI and API for VM lifecycle management
- ✅ Supports live migration between nodes
- ✅ Integrates with Terraform via the Proxmox provider (planned)
- ⚠️ Proxmox Terraform automation not yet implemented (tracked in Readme TODO)
- ⚠️ Manual VM provisioning required until Terraform integration is complete

### ADR-006: Terraform for External Resource Management

**Context:** Resources outside the Kubernetes cluster (cloud services, DNS, hypervisor) need to be provisioned and managed in a repeatable, auditable, and declarative way — consistent with the GitOps philosophy applied to in-cluster resources.

**Decision:** Use Terraform with Terraform Cloud as the backend to manage all external infrastructure. Secrets are encrypted at rest using SOPS with an Azure Key Vault-backed RSA key.

**Scope:**
- **Active:** Azure (Key Vault, service principals, resource groups)
- **Planned:** Proxmox (VM provisioning for Kubernetes nodes)
- **Planned:** Cloudflare (DNS records, tunnel configuration)
- **Planned:** GitHub Actions / automation (repository secrets, workflow variables, runner configuration)

**Workspace Structure:**
- `cluster/infra/mgmt/` — Management workspace: provisions the SOPS encryption key and synchronizes secrets to Terraform Cloud workspace variables
- `cluster/infra/main/` — Main workspace: provisions application-facing Azure resources (Key Vault, secrets)

**Consequences:**
- ✅ External resources managed as code alongside cluster configuration
- ✅ State stored remotely in Terraform Cloud for collaboration and auditability
- ✅ SOPS encryption ensures secrets are never stored in plaintext in Git
- ✅ `Taskfile.yaml` provides consistent `plan`/`apply`/`encrypt`/`decrypt` developer workflows
- ⚠️ Proxmox and Cloudflare providers not yet implemented
- ⚠️ Initial bootstrap requires manual SOPS key setup before Terraform can run



---

## 16. Architecture Governance

### Automated Checks

**Renovate Bot:**
- Monitors image versions
- Creates PRs for updates
- Configured in `renovate.json`

**ArgoCD Sync Policies:**
```yaml
syncPolicy:
  automated:
    prune: true      # Removes untracked resources
    selfHeal: true   # Corrects drift
```

### Naming Conventions

| Resource | Convention |
|----------|------------|
| App directories | lowercase, hyphenated |
| Kubernetes names | lowercase, hyphenated |
| Labels | `app.kubernetes.io/*` standards |
| Hostnames | `{app}.internal.gustend.net` or `{app}.gustend.net` |

### Required Labels

All deployments must include:
```yaml
metadata:
  labels:
    app.kubernetes.io/name: {app-name}
```

### Resource Requirements

All deployments must specify:
```yaml
resources:
  requests:
    cpu: "..."
    memory: "..."
  limits:
    cpu: "..."
    memory: "..."
```

---

## 17. Blueprint for New Development

### Development Workflow

1. **Plan:** Identify requirements, storage needs, secret requirements
2. **Create:** Build manifests following patterns in this document
3. **Register:** Add app to `root-app/values.yaml`
4. **Deploy:** Commit and push; ArgoCD handles deployment
5. **Verify:** Check ArgoCD sync status and app health
6. **Monitor:** Use uptime-kuma or app-specific monitoring

### Implementation Checklist

- [ ] Create app directory under `cluster/apps/`
- [ ] Create `deployment.yaml` with resource limits and labels
- [ ] Create `service.yaml` with appropriate selectors
- [ ] Create `httproute.yaml` with homepage annotations
- [ ] Add storage resources if needed (PVC, StorageClass)
- [ ] Add ExternalSecret if secrets needed
- [ ] Add entry to `cluster/root-app/values.yaml`
- [ ] Set appropriate namespace (existing or request new)
- [ ] Set sync wave if dependency ordering needed
- [ ] Commit with descriptive message
- [ ] Verify ArgoCD sync success
- [ ] Test endpoint accessibility

### Common Pitfalls

| Pitfall | Prevention |
|---------|------------|
| Missing resource limits | Template includes limits |
| Wrong label selectors | Copy from template, update consistently |
| Storage class not found | Use `synology-iscsi` or define NFS class |
| Gateway not accepting route | Check `parentRefs` namespace |
| Secrets not syncing | Verify ClusterSecretStore and Azure KV key |
| Deployment stuck | Check events, pod logs, image pull status |

### File Templates

Templates for all resource types are documented in `.github/copilot-instructions.md` and should be used as the starting point for new applications.

---

## Appendix: Quick Reference

### Key URLs

| Service | URL |
|---------|-----|
| ArgoCD | `https://argocd.internal.gustend.net` |
| Homepage | `https://homepage.internal.gustend.net` |
| (Apps) | `https://{app}.internal.gustend.net` |

### Key Commands

```bash
# SOPS encrypt/decrypt
task sops-encrypt-all
task sops-decrypt-all

# Terraform
task tf-plan-main
task tf-apply-main

# Talos
talosctl --talosconfig talos/_out/talosconfig health
talosctl kubeconfig

# kubectl
kubectl get applications -n argocd
kubectl get httproutes -A
kubectl get pvc -A
```

### Important Files

| Purpose | Location |
|---------|----------|
| App registry | `cluster/root-app/values.yaml` |
| Cloud & cluster setup notes | `Readme.md` |
| Talos bootstrap & config generation | `talos/Readme.md` |
| Talos generated config | `talos/_out/controlplane.yaml` |
| Terraform secrets | `cluster/infra/*/env/secrets.enc.json` |
| Copilot patterns | `.github/copilot-instructions.md` |

---

*This blueprint should be updated whenever significant architectural changes are made to the cluster.*
