# Tools

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
