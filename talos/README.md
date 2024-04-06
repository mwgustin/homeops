
Steps:

generate configs and certs
```bash
talosctl gen config gustend https://cluster.gustend.local:6443
```

Apply config
```bash
talosctl apply-config --insecure --nodes 10.1.10.132 --file controlplane.yaml
```

on first node, bootstrap cluster
```bash
talosctl bootstrap --nodes 10.1.10.132 --endpoints 10.1.10.132 --talosconfig=./talosconfig
```

Setup kubeconfig
```bash
talosctl kubeconfig -n 10.1.10.132 -e cluster.gustend.local --talosconfig=./talosconfig
```


(apply config on addtl nodes)