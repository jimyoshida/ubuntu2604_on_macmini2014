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

## gomplate.yml

Install gomplate

```bash
ansible-playbook tool/gomplate.yml
```

Installs [gomplate](https://github.com/hairyhenderson/gomplate) — a flexible command-line template renderer with support for many datasources — by downloading the official release binary from GitHub into `/usr/local/bin` (no Homebrew). Pin a different release with `-e gomplate_version=4.3.0`.

**Usage:**

```bash
gomplate -f template.tmpl -o out.txt        # render a template file
echo 'Hello {{ .Env.USER }}' | gomplate     # render from stdin
gomplate -d config=./config.yaml -f tmpl    # render with a datasource
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

## bats.yml

Install the Bats testing framework via Homebrew

```bash
ansible-playbook tool/bats.yml
```

**Prerequisite:** Requires Homebrew to be installed first (run `core/homebrew.yml` first).

Adds the `bats-core/bats-core` tap and installs:

- **bats-core** — Bash Automated Testing System
- **bats-assert** — Assertion library for Bats tests
- **bats-support** — Support library for Bats tests

```bash
bats test.bats              # Run Bats tests
```

## shellcheck.yml

Install ShellCheck via Homebrew

```bash
ansible-playbook tool/shellcheck.yml
```

**Prerequisite:** Requires Homebrew to be installed first (run `core/homebrew.yml` first).

Installs **shellcheck** — a shell script static analysis tool and linter.

```bash
shellcheck script.sh        # Lint shell scripts
```

## trivy.yml

Install Trivy via Homebrew

```bash
ansible-playbook tool/trivy.yml
```

**Prerequisite:** Requires Homebrew to be installed first (run `core/homebrew.yml` first).

Installs **trivy** — a comprehensive vulnerability scanner for containers and dependencies.

```bash
trivy image nginx:latest    # Scan container image for vulnerabilities
```

## grype-syft.yml

Install Grype and Syft via Homebrew

```bash
ansible-playbook tool/grype-syft.yml
```

**Prerequisite:** Requires Homebrew to be installed first (run `core/homebrew.yml` first).

Installs the vulnerability scanner and SBOM generator pair:

- **grype** — Vulnerability scanner for container images and filesystems
- **syft** — SBOM (Software Bill of Materials) generator for supply chain security

```bash
grype dir:.                 # Scan current directory for vulnerabilities
syft packages dir:.         # Generate Software Bill of Materials
```

## hadolint.yml

Install hadolint via Homebrew

```bash
ansible-playbook tool/hadolint.yml
```

**Prerequisite:** Requires Homebrew to be installed first (run `core/homebrew.yml` first).

Installs **hadolint** — a Dockerfile best practices linter.

```bash
hadolint Dockerfile         # Lint Dockerfile for best practices
```

## junit2html.yml

Install junit2html

```bash
ansible-playbook tool/junit2html.yml
```

Installs [junit2html](https://github.com/inorton/junit2html) — a tool that converts JUnit XML test reports into a standalone HTML report — via **pipx** (no Homebrew). The playbook installs `pipx` from apt, runs `pipx ensurepath`, then installs junit2html into an isolated environment under `~/.local/bin`.

**Usage:**

```bash
junit2html results.xml report.html   # Convert a JUnit XML report to HTML
junit2html results.xml               # Write HTML to stdout
junit2html --summary-matrix *.xml    # Summarise multiple report files
```

> **Note:** junit2html is installed to `~/.local/bin`. Start a new shell or run `source ~/.bashrc` if the command is not yet on your `PATH`.
