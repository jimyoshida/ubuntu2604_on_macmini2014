# Tools

## devcontainers.yml

Install Devcontainers CLI

```bash
ansible-playbook tool/devcontainers.yml
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

Documentation: https://containers.dev

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

Documentation: https://github.com/igorshubovych/markdownlint-cli

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
