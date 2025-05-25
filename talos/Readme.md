Steps:

```bash
export CONTROL_PLANE_IP=10.1.x.x
```

generate configs and certs

```bash
talosctl gen config gustend https://$CONTROL_PLANE_IP:6443 --output-dir _out --install-image factory.talos.dev/nocloud-installer/dc7b152cb3ea99b821fcb7340ce7168313ce393d663740b791c36f6e95fc8586:v1.10.2

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
