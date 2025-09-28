# Copilot Instructions for homeops

This repository manages a Kubernetes cluster using Talos, with a focus on declarative infrastructure, GitOps, and external integrations. AI agents should follow these guidelines for effective contributions:

## Steps for Adding a New App
When requested to onboard a new app, follow these steps:
1. **Define a Deployment**: Create a deployment manifest for the app, including resource requests/limits and the `app.kubernetes.io/name` label.
2. **Define a Service**: Create a service manifest (usually `ClusterIP`) with selectors matching the deployment labels.
3. **Define PVCs (if needed)**: If persistent storage is required, create PVC manifests. For NFS mounts, also define the associated StorageClass and update the deployment to mount the PVC.
4. **Define an Ingress**: By default, use the internal ingress manifest pattern unless otherwise specified.
5. **Add Other Resources**: Create any additional resources needed (ConfigMaps, Secrets, RBAC, etc.).
6. **Update ArgoCD App-of-Apps**: Add an entry for the app in `cluster/root-app/values.yaml` to onboard it into ArgoCD management.

## Architecture Overview
- **Talos Cluster**: Cluster configuration is generated and managed via Talos (`talos/_out/controlplane.yaml`, `talos/Readme.md`). Talos replaces traditional Linux OS for Kubernetes nodes.
- **Bootstrap**: The `bootstrap/` directory contains manifests and scripts for initial cluster setup, including external snapshotter CRDs/controllers and Synology CSI integration.
- **Apps**: The `cluster/apps/` directory organizes Kubernetes applications by subfolder. Each app typically contains manifests (`*.yaml`), Helm charts, and configuration files.
- **Secrets & External Integrations**: Integrations with Cloudflare, Azure Key Vault, and external secrets are managed via dedicated manifests and secrets files (see `cert-manager-cloudflare/secrets.yaml`, `azkv-secret-store/keyvault-secret-store.yaml`).

## Developer Workflows
- **Talos Setup**:
  - Generate configs: `talosctl gen config ...`
  - Apply config: `talosctl apply-config --insecure --nodes $CONTROL_PLANE_IP --file _out/controlplane.yaml`
  - Bootstrap cluster: `talosctl bootstrap`
  - Setup kubeconfig: `talosctl kubeconfig`
- **Bootstrap Scripts**:
  - For Synology CSI: Copy template, update credentials, then run `./scripts/deploy.sh run` in `bootstrap/synology-csi-talos/`.
- **Kubernetes Manifests**:
  - Use `kubectl apply -k` for kustomize directories (e.g., `external-snapshotter-crd`, `external-snapshotter-controller`).
  - Secrets are created via `kubectl create secret ...` or by applying manifest files.
- **App Deployment**:
  - Each app in `cluster/apps/` is self-contained. Some use Helm charts (`Chart.yaml`, `values.yaml`), others use raw manifests.
  - Ingress, service, and deployment patterns are consistent across apps.

## Project-Specific Conventions
- **Directory Structure**: All cluster resources are organized by function (bootstrap, apps, root-app, talos).
- **Secrets Management**: Sensitive credentials are stored in external secret stores or Kubernetes secrets, never hardcoded.
- **RBAC**: Cluster roles and permissions are defined per app (see `cluster-role.yaml` in app folders).
- **Ingress**: Ingress resources use consistent annotations and pathing (see `manual-route.yaml` in route apps).
- **Cloud Integrations**: Cloudflare and Azure Key Vault integrations require manual secret creation and manifest updates.

## Integration Points

## Details

## ArgoCD & App-of-Apps Pattern
- **Cluster Management**: The cluster is managed declaratively with ArgoCD (`cluster/apps/argo-cd/`).
- **App-of-Apps**: The `root-app` implements the app-of-apps pattern, orchestrating deployment of all other apps.
- **Adding New Apps**: To onboard a new app, add its configuration to the `root-app/values.yaml` file. This ensures ArgoCD will automatically deploy and manage the app as part of the cluster.
- **Workflow**: After updating `values.yaml`, ArgoCD will reconcile and deploy the new app according to its manifest or Helm chart.
- For secrets, add manifest to the appropriate app folder and apply with `kubectl`.

## References
- `Readme.md` (root): High-level setup steps and cloud integration notes.
- `talos/Readme.md`: Talos cluster setup and config generation.
- `bootstrap/synology-csi-talos/readme.md`: Synology CSI deployment workflow.

---

## Specific cluster resource details and examples


### Deployment
- Always include resource requests/limits for containers.
- Use common Kubernetes labels like `app.kubernetes.io/name`.

**Deployment Example:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <deployment-name>
  labels:
    app.kubernetes.io/name: <app-name>
spec:
  replicas: <replica-count>
  selector:
    matchLabels:
      app.kubernetes.io/name: <app-name>
  template:
    metadata:
      labels:
        app.kubernetes.io/name: <app-name>
    spec:
      containers:
        - name: <container-name>
          image: <container-image>
          ports:
            - containerPort: <container-port>
          resources:
            requests:
              cpu: "<cpu-request>"
              memory: "<memory-request>"
            limits:
              cpu: "<cpu-limit>"
              memory: "<memory-limit>"
          volumeMounts:
            - name: <volume-name>
              mountPath: <mount-path>
      volumes:
        - name: <volume-name>
          persistentVolumeClaim:
            claimName: <pvc-name>
```

### Service
- Typically use `ClusterIP` type.
- Use common Kubernetes labels like `app.kubernetes.io/name`.
- Selector should match the deployment/spec `app.kubernetes.io/name` label.

**Service Example:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: <service-name>
  labels:
    app.kubernetes.io/name: <app-name>
spec:
  type: ClusterIP
  ports:
    - port: <service-port>
      targetPort: <container-port>
      protocol: TCP
      name: http
  selector:
    app.kubernetes.io/name: <app-name>
```


### Ingress
- **Internal ingress** uses domain `{service}.internal.gustend.net` and must reference a TLS certificate from `letsencrypt-prod`.
- **External ingress** uses domain `{service}.gustend.net` and does NOT require a TLS reference (handled by external Cloudflare tunnel).
- Both ingress types use `gethomepage.dev` annotations for homepage integration.

**Internal Ingress Example:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <service-name>
  labels:
    app.kubernetes.io/name: <service-name>
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    gethomepage.dev/description: <Service Description>
    gethomepage.dev/enabled: "true"
    gethomepage.dev/group: <Service Group>
    gethomepage.dev/icon: <Service Icon>
    gethomepage.dev/name: <Service Display Name>
    gethomepage.dev/pod-selector: app.kubernetes.io/name=<service-name>
spec:
  ingressClassName: internal
  tls:
    - hosts:
      - <service>.internal.gustend.net
      secretName: <service>-internal-gustend-net-cert
  rules:
    - host: <service>.internal.gustend.net
      http:
        paths:
          - path: "/"
            pathType: Prefix
            backend:
              service:
                port:
                  number: <service-port>
```

**External Ingress Example:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <service-name>
  annotations:
    kubernetes.io/ingress.class: "external"
    gethomepage.dev/description: <Service Description>
    gethomepage.dev/enabled: "true"
    gethomepage.dev/group: <Service Group>
    gethomepage.dev/icon: <Service Icon>
    gethomepage.dev/name: <Service Display Name>
spec:
  ingressClassName: external
  rules:
    - host: <service>.gustend.net
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: <service-name>
                port:
                  number: <service-port>
```
### External Secrets
- All secrets are managed using the external secret store (Azure KeyVault).
- The external secret store is a `ClusterSecretStore` named `azure-secret-store`.

**External Secret Example:**
```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: <secret-name>
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: azure-secret-store
    kind: ClusterSecretStore
  target:
    name: <secret-name>
    creationPolicy: Owner
  data:
    - secretKey: <secret-key>
      remoteRef:
        key: <remote-key>
```

- Two primary storage methods:
  - `synology-iscsi` for most PVCs (creates iSCSI volumes on Synology NAS).
  - NFS via `nfs.csi.k8s.io` provisioner for shared volumes, with server `library.gustend.local`.

**NFS Storage Class Example:**
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-library-media
provisioner: nfs.csi.k8s.io
parameters:
  share: /volume1/Media

### Persistent Volume Claims
- Most PVCs use `synology-iscsi`. For shared volumes, use a custom NFS storage class and mount.

**PVC Examples:**
```yaml
# synology-iscsi PVC
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: <pvc-name>
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: <size>
  storageClassName: synology-iscsi

# NFS PVC and PV
apiVersion: v1
kind: PersistentVolume
metadata:
  name: <pv-name>
spec:
  capacity:
    storage: <size>
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  nfs:
    server: library.gustend.local
    path: /volume1/Media
  storageClassName: nfs-library-media
```

### External Manual Route (Proxy to Legacy Server)
To temporarily proxy requests to resources on a legacy server, create an EndpointSlice, a Service, and an Ingress. The Service and Ingress route traffic to the external IP defined in the EndpointSlice. 

Unless otherwise specified, the legacy service will always be at 10.1.10.194, but with different ports

**EndpointSlice Example:**
```yaml
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: <service-name>
  labels:
    kubernetes.io/service-name: <service-name>
addressType: IPv4
endpoints:
  - addresses:
      - "10.1.10.194"
    conditions:
      ready: true
ports:
  - name: http
    protocol: TCP
    port: <external-port>
```

**Service Example:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: <service-name>
spec:
  ports:
    - protocol: TCP
      port: <service-port>
      targetPort: <external-port>
```

**Ingress Example:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <service-ingress>
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    gethomepage.dev/pod-selector: ""
    gethomepage.dev/description: <Service Description>
    gethomepage.dev/enabled: "true"
    gethomepage.dev/group: <Service Group>
    gethomepage.dev/icon: <Service Icon>
    gethomepage.dev/name: <Service Display Name>
spec:
  ingressClassName: internal
  tls:
    - hosts:
        - <service>.internal.gustend.net
      secretName: <service>-internal-gustend-net-tls
  rules:
    - host: "<service>.internal.gustend.net"
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: <service-name>
                port:
                  number: <service-port>
```


