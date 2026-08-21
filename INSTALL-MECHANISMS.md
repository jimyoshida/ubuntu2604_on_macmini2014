# Install Mechanisms

A classification of how each playbook under [`playbooks/`](playbooks/) gets its tool onto
the filesystem.

Each playbook picks the first of the following that applies: an Ubuntu apt package, if the
distro package is current enough and named as expected; a vendor's own apt repository, if one
exists and the distro package lags; an upstream release artifact straight to
`/usr/local/bin` (or equivalent), for a single static binary or similar; an upstream git tag
plus its own install script, for a tool that ships as a git repository; pipx as root, for a
Python application; or `npm install -g` with `become`, for a Node.js application. 56 playbooks,
six canonical mechanisms plus a handful of second-layer package managers that sit on top of a
shared prerequisite rather than installing a runtime themselves.

| Mechanism | Playbooks |
| --- | ---: |
| 1. Ubuntu apt package | 11 |
| 2. Vendor apt repository | 15 |
| 3. Upstream release artifact → `/usr/local/bin` (or equivalent) | 19 |
| 4. Upstream git tag + install script / tree | 2 |
| 5. pipx as root | 2 |
| 6. `npm install -g` with `become` | 5 |
| Second-layer package manager (see below) | 2 |

## 1. Ubuntu apt package

The distro package is current enough and named as expected — `state: present` at a pinned
version, no repository work needed.

| Playbook | Package(s) |
| --- | --- |
| [core/shellcheck.yml](playbooks/core/shellcheck.yml) | `shellcheck` |
| [core/jq.yml](playbooks/core/jq.yml) | `jq` |
| [core/openjdk.yml](playbooks/core/openjdk.yml) | `default-jdk` (pulls in `default-jre` + `default-jdk-headless`) |
| [core/dotnet.yml](playbooks/core/dotnet.yml) | `dotnet-sdk-10.0` — Ubuntu 26.04 carries .NET 10 directly; no Microsoft repo needed |
| [core/core-tools.yml](playbooks/core/core-tools.yml) | 18 packages: curl, gnupg, lsb-release, git, git-lfs, git-secret, python3-pip, zip, unzip, vim, net-tools, ncat, figlet, dos2unix, make, parallel, ca-certificates, aha |
| [core/modern-tools.yml](playbooks/core/modern-tools.yml) | 13 packages (bat→`batcat`+symlink, fd→`fdfind`+symlink, fzf+`/etc/profile.d` hook, plus 10 more) |
| [core/ansible.yml](playbooks/core/ansible.yml) | `ansible-core` (Galaxy collections on top are a separate mechanism — see below) |
| [cloud-cli/promtool.yml](playbooks/cloud-cli/promtool.yml) | `promtool`, `amtool` (via `prometheus-alertmanager`, daemon stopped/disabled) |
| [container/podman.yml](playbooks/container/podman.yml) | `podman`, `podman-compose` |
| [misc/jsonnet.yml](playbooks/misc/jsonnet.yml) | `jsonnet` |
| [misc/plantuml.yml](playbooks/misc/plantuml.yml) | `plantuml` |

Two apt gotchas worth knowing before assuming a distro package is fine as-is: Ubuntu's `yq` is
the unrelated Python jq-wrapper, not mikefarah's Go `yq` — hence [core/yq.yml](playbooks/core/yq.yml)
below uses mechanism 3 instead. And apt installs `bat` as `batcat` (name clash with
`bacula-console`) — `modern-tools.yml` adds the `/usr/local/bin/bat` symlink.

## 2. Vendor apt repository

The vendor publishes their own repository and it's kept current; adds a `deb822_repository`
(or equivalent) plus a pinned package.

| Playbook | Repository |
| --- | --- |
| [cloud-cli/azure-cli.yml](playbooks/cloud-cli/azure-cli.yml) | `packages.microsoft.com` |
| [cloud-cli/azure-devops-cli.yml](playbooks/cloud-cli/azure-devops-cli.yml) | same Microsoft repo as azure-cli.yml, self-contained by design |
| [cloud-cli/gcloud-cli.yml](playbooks/cloud-cli/gcloud-cli.yml) | `packages.cloud.google.com` |
| [cloud-cli/github-cli.yml](playbooks/cloud-cli/github-cli.yml) | `cli.github.com` |
| [cloud-cli/opentofu.yml](playbooks/cloud-cli/opentofu.yml) | `packages.opentofu.org` |
| [cloud-cli/vault-cli.yml](playbooks/cloud-cli/vault-cli.yml) | HashiCorp apt repo |
| [container/docker.yml](playbooks/container/docker.yml) | `download.docker.com` |
| [container/helm.yml](playbooks/container/helm.yml) | Helm's own apt repo |
| [container/kubectl.yml](playbooks/container/kubectl.yml) | `pkgs.k8s.io`, plus an `/etc/apt/preferences.d` pin at priority 1001 to beat `packages.cloud.google.com`'s epoched `kubectl` package — see the file's header for why a plain version pin isn't enough |
| [core/mise.yml](playbooks/core/mise.yml) | mise's own apt repo |
| [core/nodejs.yml](playbooks/core/nodejs.yml) | NodeSource, for Node.js itself (Yarn/pnpm are installed afterward — see the mechanism-6 footnote) |
| [misc/dvc.yml](playbooks/misc/dvc.yml) | Iterative's apt repo |
| [misc/k6.yml](playbooks/misc/k6.yml) | Grafana's apt repo (amd64 only) |
| [misc/mongodb-tools.yml](playbooks/misc/mongodb-tools.yml) | MongoDB's official apt repo, for `mongodb-database-tools` only (`mongosh` is a standalone `.deb` — see mechanism 3) |
| [misc/trivy.yml](playbooks/misc/trivy.yml) | Aqua Security's apt repo |

## 3. Upstream release artifact → `/usr/local/bin` (or equivalent)

A single binary, tarball, `.deb`, or jar fetched directly from upstream (GitHub Releases, a
vendor's own CDN, or a language ecosystem's own artifact repo) and checksum- or
signature-verified, because no apt package or vendor repository exists — or the ones that do
exist are rejected for lagging upstream, being unsigned, or being CPU-incompatible with these
hosts. Most land as a single static binary; a few are structured trees where only the entry
point goes on `PATH`.

| Playbook | Artifact |
| --- | --- |
| [core/yq.yml](playbooks/core/yq.yml) | single binary — apt's `yq` is the wrong tool (see mechanism 1's gotcha) |
| [misc/gomplate.yml](playbooks/misc/gomplate.yml) | single binary |
| [misc/hadolint.yml](playbooks/misc/hadolint.yml) | single binary |
| [misc/kube-score.yml](playbooks/misc/kube-score.yml) | single binary |
| [container/kind.yml](playbooks/container/kind.yml) | single binary |
| [container/minikube.yml](playbooks/container/minikube.yml) | single binary |
| [container/kube-tools.yml](playbooks/container/kube-tools.yml) | three single binaries: kubelogin, k9s, kdash |
| [cloud-cli/databricks-cli.yml](playbooks/cloud-cli/databricks-cli.yml) | single Go binary (de-brewed) |
| [cloud-cli/gcx-cli.yml](playbooks/cloud-cli/gcx-cli.yml) | release tarball (de-brewed) |
| [cloud-cli/jira-cli.yml](playbooks/cloud-cli/jira-cli.yml) | release tarball (de-brewed) |
| [cloud-cli/influx-cli.yml](playbooks/cloud-cli/influx-cli.yml) | tarball from `dl.influxdata.com`, not GitHub — versioned directory + symlink (de-brewed) |
| [cloud-cli/loki-cli.yml](playbooks/cloud-cli/loki-cli.yml) | zip, verified against the release's `SHA256SUMS` |
| [misc/grype-syft.yml](playbooks/misc/grype-syft.yml) | each project's own `install.sh`, pinned to the release tag (not `main`), which resolves and installs the binary itself |
| [misc/maven.yml](playbooks/misc/maven.yml) | tarball from Apache (not GitHub) — versioned directory + symlink |
| [misc/zap.yml](playbooks/misc/zap.yml) | ~270 MB distribution zip from the GitHub release — versioned directory + symlink to the launcher |
| [core/pwsh.yml](playbooks/core/pwsh.yml) | tarball from Microsoft — no `powershell` package exists for Ubuntu 26.04 at all; versioned directory + symlink |
| [cloud-cli/aws-cli.yml](playbooks/cloud-cli/aws-cli.yml) | vendor's own zip + `install` program (not ansible's `unarchive`) — versioned directory + symlinks, GPG-signature verified |
| [cloud-cli/jenkins-cli.yml](playbooks/cloud-cli/jenkins-cli.yml) | single jar from `repo.jenkins-ci.org` (a Maven repository, not GitHub) |
| [cloud-cli/gitlab-cli.yml](playbooks/cloud-cli/gitlab-cli.yml) | vendor `.deb` fetched and installed with `apt: deb=` — no vendor apt repo exists |

**Footnote:** [misc/mongodb-tools.yml](playbooks/misc/mongodb-tools.yml) (mechanism 2 above,
via MongoDB's apt repo) installs `mongosh` this same `apt: deb=` way instead, inside the same
file — the one apt suite that carries `mongosh` is signed by a key MongoDB no longer publishes,
so its repository can't be trusted the way `mongodb-database-tools`' can.

## 4. Upstream git tag + install script / tree

The tool ships as a git repository rather than a packaged release.

| Playbook | Shape |
| --- | --- |
| [misc/bats.yml](playbooks/misc/bats.yml) | shallow clone pinned to a tag, then upstream's own `install.sh`; `bats-support`/`bats-assert` helper libraries cloned in full alongside it |
| [misc/testssl.yml](playbooks/misc/testssl.yml) | clone pinned to a tag **and** the commit it pointed to (no installer) — the whole tree is kept, since the script resolves its cipher data and bundled OpenSSL build relative to its own location, and only the entry-point script is symlinked onto `PATH` |

## 5. pipx as root

A Python application, installed with `PIPX_HOME=/opt/pipx` and `PIPX_BIN_DIR=/usr/local/bin`
(plus `PIPX_MAN_DIR`, to keep pipx from writing under `/root`) rather than into the
connecting account's own `~/.local`.

| Playbook | Package |
| --- | --- |
| [misc/junit2html.yml](playbooks/misc/junit2html.yml) | `junit2html` |
| [misc/certbot.yml](playbooks/misc/certbot.yml) | `certbot`, plus the Route 53 DNS plugin via `pipx inject` |

## 6. `npm install -g` with `become`

A Node.js application, installed into npm's global prefix (root-owned) rather than a
per-user path. Node.js itself is always a declared prerequisite, never installed by these
playbooks — see the prerequisite table below.

| Playbook | Package(s) |
| --- | --- |
| [core/markdownlint.yml](playbooks/core/markdownlint.yml) | `markdownlint-cli` |
| [cloud-cli/auth0-deploy-cli.yml](playbooks/cloud-cli/auth0-deploy-cli.yml) | `auth0-deploy-cli` |
| [container/devcontainers.yml](playbooks/container/devcontainers.yml) | `@devcontainers/cli` |
| [misc/mocha-chai.yml](playbooks/misc/mocha-chai.yml) | `mocha` (has a CLI) + `chai` (pure library, no CLI — needs `NODE_PATH` published for `require()` to resolve it) |
| [misc/playwright.yml](playbooks/misc/playwright.yml) | `playwright`, plus its own `playwright install --with-deps` browser downloader redirected to a shared `/opt/playwright-browsers` via `PLAYWRIGHT_BROWSERS_PATH` |

**Footnote:** [core/nodejs.yml](playbooks/core/nodejs.yml) also uses this mechanism internally,
for Yarn and pnpm — but only after `corepack disable` removes the dispatcher shims NodeSource's
`nodejs` package ships at the same paths, which otherwise silently shadow a real pinned install.

## Second-layer package managers

These install *into* a runtime the playbooks above already installed, rather than installing a
runtime themselves — how a tool, once present, gets *its own* plugins or packages onto the box,
distinct from how the tool itself got there.

| Playbook | Mechanism | Needs |
| --- | --- | --- |
| [cloud-cli/azure-pwsh.yml](playbooks/cloud-cli/azure-pwsh.yml) | `Install-Module -Scope AllUsers` from the PowerShell Gallery (8 `Az.*` modules) | [core/pwsh.yml](playbooks/core/pwsh.yml) |
| [misc/dotnet-tools.yml](playbooks/misc/dotnet-tools.yml) | `dotnet tool install --tool-path` | [core/dotnet.yml](playbooks/core/dotnet.yml) |

Two more instances of the same pattern live inside playbooks already classified above, layered
on top of their own apt package rather than a separate file:

- [core/ansible.yml](playbooks/core/ansible.yml) installs `ansible-core` via apt
  (mechanism 1), then pins five Galaxy collections with
  `ansible-galaxy collection install --force-with-deps`.
- [cloud-cli/azure-devops-cli.yml](playbooks/cloud-cli/azure-devops-cli.yml) installs `az` via
  apt (mechanism 2), then adds the `azure-devops` extension with `az extension add --system`.

## Prerequisite, not installed here

Several playbooks check for a shared runtime and fail with instructions rather than installing
it themselves — the runtime has its own playbook, which every consumer defers to instead of
carrying its own copy of the pin.

| Prerequisite | Provisioned by | Checked (not installed) by |
| --- | --- | --- |
| Node.js | [core/nodejs.yml](playbooks/core/nodejs.yml) | markdownlint.yml, auth0-deploy-cli.yml, devcontainers.yml, mocha-chai.yml, playwright.yml |
| OpenJDK | [core/openjdk.yml](playbooks/core/openjdk.yml) | jenkins-cli.yml, maven.yml, zap.yml |
| .NET SDK | [core/dotnet.yml](playbooks/core/dotnet.yml) | dotnet-tools.yml |
| PowerShell | [core/pwsh.yml](playbooks/core/pwsh.yml) | azure-pwsh.yml |

Each of these four runtimes is intentionally installed and pinned in exactly one place, so a
Java (or Node, .NET, PowerShell) version bump happens once instead of drifting across every
playbook that happens to need it.
