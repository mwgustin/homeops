To wipe a disk:

1. Create a namespace
```bash
kubectl create namespace wipe-disks
```
2. Update the labels on the namespace to allow privileged execution.
```bash
kubectl label --overwrite ns wipe-disks \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/warn=baseline \
  pod-security.kubernetes.io/audit=baseline
```

3. Deploy privileged pod to wipe disks.  Replace `<node name>` and `<device>` with node and disk device ("talos-2", "/dev/sda")
```bash
cat <<EOF | kubectl apply -f -                                                      
apiVersion: v1
kind: Pod
metadata:
  name: disk-wipe
  namespace: wipe-disks
spec:
  restartPolicy: Never
  nodeName: <node name>
  containers:
  - name: disk-wipe
    image: busybox
    securityContext:
      allowPrivilegeEscalation: true
      privileged: true
    command: ["/bin/sh", "-c", "dd if=/dev/zero bs=1M count=100 oflag=direct of=<device>"]
EOF

```

4. Remove pod
```bash
kubectl delete -n wipe-disk disk-wipe
```

5. Remove namespace
```bash
kubectl delete ns wipe-disk
```