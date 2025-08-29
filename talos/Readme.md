Steps:

```bash
export CONTROL_PLANE_IP=10.1.x.x
```

generate configs and certs

```bash
talosctl gen config gustend https://$CONTROL_PLANE_IP:6443 --output-dir _out --install-image factory.talos.dev/nocloud-installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.10.7

```

Apply config
```bash
talosctl apply-config --insecure --nodes $CONTROL_PLANE_IP --file _out/controlplane.yaml
```

```bash
export TALOSCONFIG="_out/talosconfig"
talosctl config endpoint $CONTROL_PLANE_IP
talosctl config node $CONTROL_PLANE_IP
```

on first node, bootstrap cluster
```bash
talosctl bootstrap
```

Setup kubeconfig
```bash
talosctl kubeconfig
```
