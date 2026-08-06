# GUI Tools

## vscode.yml

Install Visual Studio Code

```bash
ansible-playbook gui-tools/vscode.yml
```

**What it does:**

- Adds Microsoft's GPG key to the apt keyring
- Adds the official VSCode apt repository
- Installs the latest stable version of Visual Studio Code
- Verifies the installation

**Post-installation:**

VSCode is available via the `code` command. You can launch it from the terminal or find it in your application menu.
