# Tools

## markdownlint.yml

Install Markdownlint CLI

```bash
ansible-playbook tool/markdownlint.yml
```

**Prerequisites:**

- System-wide Node.js installed via apt: `sudo apt install nodejs npm`
  - version manager-managed Node.js will cause the playbook to fail

This playbook:

- Installs Markdownlint CLI globally via npm (`npm install -g markdownlint-cli@latest`)
- Verifies the installation

After installation, use Markdownlint to lint and fix markdown files:

```bash
markdownlint '**/*.md'              # Lint all markdown files
markdownlint --fix '**/*.md'        # Automatically fix fixable issues
markdownlint --config .markdownlintrc.json '**/*.md'  # Use custom config
```

Documentation: [markdownlint-cli](https://github.com/igorshubovych/markdownlint-cli)

## vault.yml

Install HashiCorp Vault OSS

```bash
ansible-playbook tool/vault.yml
```

Installs Vault from the official HashiCorp APT repository (pinned to `noble` — Ubuntu 26.04 `resolute` is not yet supported upstream). Configures file storage at `/opt/vault/data`, enables the UI, and starts the `vault` systemd service on port `8200`. Adds `VAULT_ADDR=http://127.0.0.1:8200` to `~/.bashrc`.

**After installation:**

```bash
source ~/.bashrc

# 1. Initialize (run once — save the output securely)
vault operator init

# 2. Unseal (run 3 times with 3 different unseal keys from above)
vault operator unseal

# 3. Log in with the root token
vault login <root-token>
```

UI is available at `http://127.0.0.1:8200/ui`.

> **Note:** TLS is disabled in the default config. For production use, configure a certificate in `/etc/vault.d/vault.hcl` and remove `tls_disable = 1`.

## kube-score.yml

Install kube-score

```bash
ansible-playbook tool/kube-score.yml
```

Installs [kube-score](https://github.com/zegl/kube-score) — a static code analysis tool for Kubernetes object definitions — by downloading the official release binary from GitHub into `/usr/local/bin` (no Homebrew). Pin a different release with `-e kube_score_version=1.20.0`.

**Usage:**

```bash
kube-score score deployment.yaml            # analyze a manifest
helm template ./chart | kube-score score -  # analyze rendered Helm output
kube-score list                             # list all available checks
```

## vscode.yml

Install Visual Studio Code

```bash
ansible-playbook tool/vscode.yml
```

**What it does:**

- Adds Microsoft's GPG key to the apt keyring
- Adds the official VSCode apt repository
- Installs the latest stable version of Visual Studio Code
- Verifies the installation

**Post-installation:**

VSCode is available via the `code` command. You can launch it from the terminal or find it in your application menu.

## freshrss.yml

Install FreshRSS via Docker

```bash
ansible-playbook tool/freshrss.yml
```

**Prerequisites:**

- Docker must be installed first (run `container/docker.yml`)

This playbook:

- Verifies Docker is installed
- Creates persistent storage directories for FreshRSS configuration, data, and extensions
- Sets up a Docker network for the container
- Deploys FreshRSS image on port `8081`
- Waits for the service to be ready before reporting success

**After installation:**

FreshRSS web UI is available at `http://127.0.0.1:8081`. Follow the setup wizard to configure your feeds and preferences. Persistent data is stored at `~/freshrss-data/`.

**Managing the container:**

```bash
docker stop freshrss      # Stop the container
docker start freshrss     # Start the container
docker logs freshrss      # View container logs
```

## modern-cli-tools.yml

Install modern CLI tools via Homebrew

```bash
ansible-playbook tool/modern-cli-tools.yml
```

**Prerequisite:** Requires Homebrew to be installed first (run `core/homebrew.yml` first).

Installs the following modern CLI tools:

- **gum** — Charming CLI for building interactive shell scripts
- **fzf** — Fuzzy finder for command-line (with bash key bindings)
  - `Ctrl+R` — fuzzy search command history
  - `Ctrl+T` — fuzzy search files in current directory
  - `Alt+C` — fuzzy search directories and cd into them
- **jq** — JSON processor (brew version, newer than apt)
- **yq** — YAML processor (like jq but for YAML)
- **jsonnet** — Data templating language
- **bat** — Cat clone with syntax highlighting and Git integration
- **eza** — Modern replacement for `ls` with colors and icons
- **lsd** — LSDeluxe, another modern `ls` replacement with icons
- **duf** — Modern replacement for `df` (disk usage with better formatting)
- **dust** — Modern replacement for `du` (directory usage analyzer)
- **procs** — Modern replacement for `ps` with colored output
- **gdu** — Fast disk usage analyzer with TUI (ncurses interface)
- **htop** — Interactive process viewer (better than top)
- **glow** — Markdown renderer for the terminal

After installation, source your bashrc to enable fzf key bindings:

```bash
source ~/.bashrc
```

## test-and-security.yml

Install testing and security tools via Homebrew

```bash
ansible-playbook tool/test-and-security.yml
```

**Prerequisite:** Requires Homebrew to be installed first (run `core/homebrew.yml` first).

Installs the following testing and security tools:

**Testing Tools:**

- **bats-core** — Bash Automated Testing System
- **shellcheck** — Shell script static analysis and linter

**Security & Linting Tools:**

- **trivy** — Comprehensive vulnerability scanner for containers and dependencies
- **grype** — Vulnerability scanner for container images and filesystems
- **syft** — SBOM (Software Bill of Materials) generator for supply chain security
- **hadolint** — Dockerfile best practices linter

**Note:** Bats helper libraries (bats-assert, bats-support, bats-file) are not available via Homebrew. If you need these libraries for your tests, install them manually from their GitHub repositories:

- [bats-assert](https://github.com/bats-core/bats-assert)
- [bats-support](https://github.com/bats-core/bats-support)
- [bats-file](https://github.com/bats-core/bats-file)

Usage examples:

```bash
bats test.bats              # Run Bats tests
shellcheck script.sh        # Lint shell scripts
trivy image nginx:latest    # Scan container image for vulnerabilities
grype dir:.                 # Scan current directory for vulnerabilities
syft packages dir:.         # Generate Software Bill of Materials
hadolint Dockerfile         # Lint Dockerfile for best practices
```
