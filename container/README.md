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

Installs Helm from the official Helm APT repository (`packages.buildkite.com/helm-linux/helm-debian`), so it stays updatable through `apt`. Verifies the repository key fingerprint before trusting it, removes the retired `baltocdn.com` repository if present, includes bash completion, and verifies the install with `helm version`.

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

## Retired: krew.yml

`krew.yml` installed Krew, the kubectl plugin manager, into the invoker's `~/.krew` and put
`$HOME/.krew/bin` on that account's `PATH`. It was retired on 2026-08-14 rather than migrated to
`_multi-user/` — see [Retired: `container/krew.yml`](../README.md#retired-containerkrewyml) in
the root README for why, and [MIGRATION3.md](../MIGRATION3.md#scope) for its place in the
migration plan.

kubectl finds plugins on `PATH` without any manager, so the three plugins this section used to
recommend can be installed as plain binaries named `kubectl-ctx`, `kubectl-ns` and
`kubectl-node_shell` in `/usr/local/bin`. An account that wants krew itself can still run
[krew's own installer](https://krew.sigs.k8s.io/docs/user-guide/setup/install/); nothing here
prevents it. Existing `~/.krew` trees are untouched by the retirement and keep working.
