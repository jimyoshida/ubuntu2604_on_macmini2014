# Container & Kubernetes Tools

## devcontainers.yml

Install Devcontainers CLI

```bash
ansible-playbook container/devcontainers.yml
```

**Prerequisites:**

- System-wide Node.js installed via apt: `sudo apt install nodejs npm`
  - version manager-managed Node.js will cause the playbook to fail

This playbook:

- Installs Devcontainers CLI globally via npm (`npm install -g @devcontainers/cli@latest`)
- Verifies the installation

After installation, use Devcontainers CLI to manage development containers:

```bash
devcontainer build                      # Build a container image
devcontainer run-user-commands          # Run user commands in container
devcontainer up                         # Create and start a dev container
devcontainer open                       # Open a folder in a dev container
devcontainer features log               # Show installed features
```

Documentation: [containers.dev](https://containers.dev)

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

## minikube.yml

Install Minikube (local Kubernetes cluster)

```bash
ansible-playbook container/minikube.yml
```

Runs a local Kubernetes cluster using Docker as the driver. Includes bash completion.

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
