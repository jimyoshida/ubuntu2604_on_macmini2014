# Container & Kubernetes Tools

## docker.yml

Docker Engine setup

```bash
ansible-playbook container/docker.yml
```

This playbook configures:
- Docker GPG key and repository
- Docker Engine, CLI, and containerd
- Docker buildx plugin and docker-compose plugin
- User group permissions for non-root Docker access

## podman.yml

Podman container runtime setup

```bash
ansible-playbook container/podman.yml
```

This playbook configures:
- Podman and podman-compose from the Ubuntu default repository
- Loginctl lingering for rootless containers (survive logout)
- X server access for containers

## kubectl.yml

Install kubectl (Kubernetes CLI)

```bash
ansible-playbook container/kubectl.yml
```

Includes bash completion and `k` alias.

## helm.yml

Install Helm (Kubernetes package manager)

```bash
ansible-playbook container/helm.yml
```

Includes bash completion.

## kind.yml

Install Kind (Kubernetes in Docker)

```bash
ansible-playbook container/kind.yml
```

Runs local Kubernetes clusters inside Docker containers. Includes bash completion.

**Prerequisites:** Docker must be installed and the user added to the `docker` group (run `docker.yml` first).

## krew.yml

Install Krew (kubectl plugin manager)

```bash
ansible-playbook container/krew.yml
```

After installation, install common plugins:
```bash
kubectl krew install ctx ns node-shell
```
