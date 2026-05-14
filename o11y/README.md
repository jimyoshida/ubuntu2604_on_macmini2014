# Observability (o11y) Tools

## node_exporter.yml

Install Prometheus Node Exporter (host metrics collector)

```bash
ansible-playbook o11y/node_exporter.yml
```

Installs `prometheus-node-exporter` from the Ubuntu apt repository. Node Exporter exposes host metrics (CPU, memory, disk, network) at `http://localhost:9100/metrics`.

## prometheus.yml

Install Prometheus (metrics scraper and Mimir forwarder)

**⚠️ DEPENDENCY:** Run `mimir.yml` BEFORE this playbook. Prometheus is configured with remote_write to Mimir, and restarting Prometheus without Mimir running will cause the service to hang.

```bash
ansible-playbook o11y/prometheus.yml
```

Installs Prometheus from the Ubuntu apt repository and configures it to scrape Node Exporter (`localhost:9100`) every 15 seconds and remote-write metrics to Mimir (`http://localhost:9009/api/v1/push`). Prometheus UI/API is available at `http://localhost:9090`. Local storage retention is **15 days**.

> **Note:** No `X-Scope-OrgID` header is needed because Mimir runs with `multitenancy_enabled: false`.

## grafana.yml

Install Grafana

```bash
ansible-playbook o11y/grafana.yml
```

Installs Grafana from the official Grafana APT repository. After installation, Grafana is available at `http://localhost:3030` (default credentials: `admin` / `admin`).

> **Note:** Port 3030 is used instead of the default 3000 to avoid conflicts with Node.js webapp testing, which commonly uses port 3000.

## loki.yml

Install Grafana Loki (log aggregation)

```bash
ansible-playbook o11y/loki.yml
```

Installs Loki from the official Grafana APT repository. Loki listens on `http://localhost:3100` (HTTP) and `9096` (gRPC). Add it as a data source in Grafana using the HTTP URL.

## alloy.yml

Install Grafana Alloy (log shipper)

**⚠️ DEPENDENCY:** Run `loki.yml` BEFORE this playbook. Alloy is configured to ship logs to Loki.

```bash
ansible-playbook o11y/alloy.yml
```

Installs Alloy from the official Grafana APT repository and configures it to ship system logs to Loki (`http://localhost:3100`). Config is written to `/etc/alloy/config.alloy`. The Alloy UI (component inspection, debugging) is available at `http://localhost:12345`.

Alloy also listens for OTLP/HTTP on `http://localhost:4318` to receive structured logs and metrics from Claude Code, forwarding logs to Loki and metrics directly to Mimir.

**Pipeline**

```
loki.source.journal
  → loki.relabel          (promote __journal_* fields to labels)
  ├→ loki.process "system_journal"   (user_unit="",  job="journal",       drop debug)
  └→ loki.process "user_journal"     (user_unit!="", job="user_journal",  drop debug)
       └→ loki.write      (http://localhost:3100)

otelcol.receiver.otlp   (:4318 HTTP)
  ├→ otelcol.exporter.loki
  │      └→ loki.write           (http://localhost:3100)
  └→ otelcol.exporter.prometheus
         └→ prometheus.remote_write  (http://localhost:9009/api/v1/push)
```

The source is the systemd journal only. File sources (`/var/log/syslog`, `auth.log`, `kern.log`) are not used because `ForwardToSyslog=yes` in journald makes them duplicates of the journal.

**Labels set on each log entry**

| Label | Source field | Example |
|---|---|---|
| `job` | static — `"journal"` for system units, `"user_journal"` for user units | `journal` |
| `unit` | `_SYSTEMD_UNIT` | `sshd.service` |
| `user_unit` | `_SYSTEMD_USER_UNIT` | `openclaw-gateway.service` |
| `transport` | `_TRANSPORT` | `journal`, `stdout`, `syslog`, `kernel` |
| `app` | `SYSLOG_IDENTIFIER` (`__journal_syslog_identifier`) | `sshd` |
| `service_name` | auto-detected by Loki from `app` (falls back to `job`) | `sshd` |

**Filters**

- Drops entries where `detected_level="debug"` (all services)
- Drops entries containing `level=debug` in the log line

## process_exporter.yml

Install Prometheus Process Exporter (per-process metrics)

```bash
ansible-playbook o11y/process_exporter.yml
```

Installs `prometheus-process-exporter` from the Ubuntu apt repository. Process Exporter scrapes `/proc` and exposes per-process metrics (CPU, memory, I/O, threads, open file descriptors) grouped by process name at `http://localhost:9256/metrics`. The config uses `{{.Comm}}` matching, so every named process (e.g. `openclaw-gateway`, `alloy`, `loki`, `grafana-server`) is tracked automatically without explicit enumeration.

After running this playbook, re-run `prometheus.yml` to pick up the new `process` scrape job added to its config.

## disable-rsyslog.yml

Stop rsyslog from duplicating journal logs to `/var/log/syslog`

```bash
ansible-playbook o11y/disable-rsyslog.yml
```

Once `alloy.yml` is shipping the journal directly to Loki, the legacy `journald → syslog.socket → rsyslog → /var/log/syslog` path is redundant. This playbook stops and disables `rsyslog.service`, then stops and masks `syslog.socket` (which is `static`, so it cannot be `disable`d — only masking persists across reboots). After this, journald has no syslog consumer and `/var/log/syslog`, `/var/log/auth.log`, etc. stop growing. The journal itself is unaffected.

It also deletes the now-stale `/var/log/{syslog,auth.log,kern.log}*` files (including rotations). `/var/log/cloud-init.log` is left alone — it is written by cloud-init directly, not rsyslog.

To revert, unmask the socket and re-enable rsyslog:

```bash
sudo systemctl unmask syslog.socket
sudo systemctl enable --now rsyslog.service
```

## tempo.yml

Install Grafana Tempo (distributed tracing)

```bash
ansible-playbook o11y/tempo.yml
```

Installs Tempo from the official Grafana APT repository. Tempo listens on `http://localhost:3200` (HTTP) and `9097` (gRPC), and accepts traces via OTLP on ports `4317` (gRPC) and `4318` (HTTP).

> **Note:** The playbook sets `grpc_listen_port: 9097` in `/etc/tempo/config.yml` to avoid conflicts with Mimir (`9095`) and Loki (`9096`).

## mimir.yml

Install Grafana Mimir (metrics backend)

```bash
ansible-playbook o11y/mimir.yml
```

Installs Mimir from the official Grafana APT repository and configures it for single-node deployment (`target: all`, `replication_factor: 1`, `multitenancy_enabled: false`). Mimir listens on `http://localhost:9009` (HTTP) and `9095` (gRPC), and accepts Prometheus remote-write at `/api/v1/push`. Metrics retention is **30 days**.

---

## Ports & Retention Reference

| Service | Port | Protocol | Purpose | Retention |
|---------|------|----------|---------|-----------|
| Grafana | 3030 | HTTP | UI | — |
| Loki | 3100 | HTTP | API / log push | — |
| Tempo | 3200 | HTTP | API | — |
| Alloy | 4318 | HTTP | OTLP receiver (Claude Code logs) | — |
| Alloy | 12345 | HTTP | UI / debug API | — |
| Prometheus | 9090 | HTTP | UI / API | 15 days (local) |
| Mimir | 9009 | HTTP | API / remote-write | 30 days |
| Mimir | 9095 | gRPC | internal | — |
| Loki | 9096 | gRPC | internal | — |
| Tempo | 9097 | gRPC | internal | — |
| Node Exporter | 9100 | HTTP | metrics endpoint | — |
| Process Exporter | 9256 | HTTP | per-process metrics | — |

---

## Viewing Host Metrics in Grafana

Run the playbooks in order:

```bash
ansible-playbook o11y/grafana.yml
ansible-playbook o11y/mimir.yml
ansible-playbook o11y/node_exporter.yml
ansible-playbook o11y/process_exporter.yml
ansible-playbook o11y/prometheus.yml
```

**1. Add Mimir as a data source**

1. Open Grafana at `http://localhost:3030` (default credentials: `admin` / `admin`)
2. Go to **Connections → Data Sources → Add new data source**
3. Select **Prometheus**
4. Set URL to `http://localhost:9009/prometheus`
5. Click **Save & test**

**2. Import the Node Exporter Full dashboard**

1. Go to **Dashboards → New → Import**
2. Enter dashboard ID `1860` and click **Load**
3. Select the Mimir data source added above
4. Click **Import**

The dashboard displays CPU usage, memory, disk I/O, filesystem, and network metrics for the host.

**3. Import the named-processes dashboard (Process Exporter)**

Requires `process_exporter.yml` to have been run first.

1. Go to **Dashboards → New → Import**
2. Enter dashboard ID `249` and click **Load**
3. Select the Mimir data source added above
4. Click **Import**

The dashboard displays per-process CPU, memory (RSS), thread count, and open file descriptors, grouped by process name (e.g. `openclaw-gateway`, `alloy`, `loki`).

---

## Viewing Logs in Grafana

Run the playbooks in order:

```bash
ansible-playbook o11y/grafana.yml
ansible-playbook o11y/loki.yml
ansible-playbook o11y/alloy.yml
```

**1. Add Loki as a data source**

1. Open Grafana at `http://localhost:3030`
2. Go to **Connections → Data Sources → Add new data source**
3. Select **Loki**
4. Set URL to `http://localhost:3100`
5. Click **Save & test**

**2. Explore logs**

1. Go to **Explore** and select the Loki data source
2. Use the label browser to filter by `unit`, `transport`, or `service_name`
