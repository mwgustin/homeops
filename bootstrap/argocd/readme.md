
Create namespace
```bash
kubectl apply -f namespace.yaml
```

Install Argo via Kustomization
```bash
kubectl apply -k ./
```



(prior to ingress setup) Setup loadbalancer for port forwarding  
```bash
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
```

Port forward server to localhost  
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```


Get initial admin password  
```bash
argocd admin initial-password -n argocd
```

Use password to login initially  
(admin, generated password)  
```bash
argocd login localhost:8080
```

Update admin password
```bash
argocd account update-password
```

Create app
```bash
argocd app create --upsert apps --dest-namespace argocd --dest-server https://kubernetes.default.svc --repo https://github.com/mwgustin/homeops.git  --path cluster/root-app

```
