# K8s Tools

#### kubectl.yml

Install kubectl (Kubernetes CLI)

```bash
ansible-playbook k8s/kubectl.yml
```

Includes bash completion and `k` alias.

#### helm.yml

Install Helm (Kubernetes package manager)

```bash
ansible-playbook k8s/helm.yml
```

Includes bash completion.

#### krew.yml

Install Krew (kubectl plugin manager)

```bash
ansible-playbook k8s/krew.yml
```

After installation, install common plugins:
```bash
kubectl krew install ctx ns node-shell
```
