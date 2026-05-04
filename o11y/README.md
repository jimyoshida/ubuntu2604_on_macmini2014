# Observability (o11y) Tools

## node_exporter.yml

Install Prometheus Node Exporter (host metrics collector)

```bash
ansible-playbook o11y/node_exporter.yml
```

Installs `prometheus-node-exporter` from the Ubuntu apt repository. Node Exporter exposes host metrics (CPU, memory, disk, network) at `http://localhost:9100/metrics`.

## prometheus.yml

Install Prometheus (metrics scraper and Mimir forwarder)

```bash
ansible-playbook o11y/prometheus.yml
```

Installs Prometheus from the Ubuntu apt repository and configures it to scrape Node Exporter (`localhost:9100`) every 15 seconds and remote-write metrics to Mimir (`http://localhost:9009/api/v1/push`) with the required `X-Scope-OrgID: anonymous` header. Prometheus UI/API is available at `http://localhost:9090`. Local storage retention is **15 days**.

## grafana.yml

Install Grafana

```bash
ansible-playbook o11y/grafana.yml
```

Installs Grafana from the official Grafana APT repository. After installation, Grafana is available at `http://localhost:3000` (default credentials: `admin` / `admin`).

## loki.yml

Install Grafana Loki (log aggregation)

```bash
ansible-playbook o11y/loki.yml
```

Installs Loki from the official Grafana APT repository. Loki listens on `http://localhost:3100` (HTTP) and `9096` (gRPC). Add it as a data source in Grafana using the HTTP URL.

## alloy.yml

Install Grafana Alloy (log shipper)

```bash
ansible-playbook o11y/alloy.yml
```

Installs Alloy from the official Grafana APT repository and configures it to ship system logs to Loki (`http://localhost:3100`). Config is written to `/etc/alloy/config.alloy`. The Alloy UI (component inspection, debugging) is available at `http://localhost:12345`.

**Pipeline**

```
loki.source.journal
  → loki.relabel   (promote __journal_* fields to labels)
  → loki.process   (drop debug logs)
  → loki.write     (http://localhost:3100)
```

The source is the systemd journal only. File sources (`/var/log/syslog`, `auth.log`, `kern.log`) are not used because `ForwardToSyslog=yes` in journald makes them duplicates of the journal.

**Labels set on each log entry**

| Label | Source field | Example |
|---|---|---|
| `job` | static | `journal` |
| `unit` | `_SYSTEMD_UNIT` | `sshd.service` |
| `transport` | `_TRANSPORT` | `journal`, `stdout`, `syslog`, `kernel` |
| `service_name` | auto-detected by Loki from `SYSLOG_IDENTIFIER` | `sshd` |

**Filters**

- Drops entries where `service_name="journal"` and `detected_level="debug"`
- Drops entries containing `level=debug` in the log line

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

Installs Mimir from the official Grafana APT repository and configures it for single-node deployment (`replication_factor: 1`). Mimir listens on `http://localhost:9009` (HTTP) and `9095` (gRPC), and accepts Prometheus remote-write at `/api/v1/push`. Metrics retention is **30 days**.

---

## Ports & Retention Reference

| Service | Port | Protocol | Purpose | Retention |
|---------|------|----------|---------|-----------|
| Grafana | 3000 | HTTP | UI | — |
| Loki | 3100 | HTTP | API / log push | — |
| Tempo | 3200 | HTTP | API | — |
| Alloy | 12345 | HTTP | UI / debug API | — |
| Prometheus | 9090 | HTTP | UI / API | 15 days (local) |
| Mimir | 9009 | HTTP | API / remote-write | 30 days |
| Mimir | 9095 | gRPC | internal | — |
| Loki | 9096 | gRPC | internal | — |
| Tempo | 9097 | gRPC | internal | — |
| Node Exporter | 9100 | HTTP | metrics endpoint | — |

---

## Viewing Host Metrics in Grafana

Run the playbooks in order:

```bash
ansible-playbook o11y/grafana.yml
ansible-playbook o11y/mimir.yml
ansible-playbook o11y/node_exporter.yml
ansible-playbook o11y/prometheus.yml
```

**1. Add Mimir as a data source**

1. Open Grafana at `http://localhost:3000` (default credentials: `admin` / `admin`)
2. Go to **Connections → Data Sources → Add new data source**
3. Select **Prometheus**
4. Set URL to `http://localhost:9009/prometheus`
5. Expand **Custom HTTP Headers**, click **Add header**:
   - **Header:** `X-Scope-OrgID`
   - **Value:** `anonymous`
6. Click **Save & test**

**2. Import the Node Exporter Full dashboard**

1. Go to **Dashboards → New → Import**
2. Enter dashboard ID `1860` and click **Load**
3. Select the Mimir data source added above
4. Click **Import**

The dashboard displays CPU usage, memory, disk I/O, filesystem, and network metrics for the host.

---

## Viewing Logs in Grafana

Run the playbooks in order:

```bash
ansible-playbook o11y/grafana.yml
ansible-playbook o11y/loki.yml
ansible-playbook o11y/alloy.yml
```

**1. Add Loki as a data source**

1. Open Grafana at `http://localhost:3000`
2. Go to **Connections → Data Sources → Add new data source**
3. Select **Loki**
4. Set URL to `http://localhost:3100`
5. Click **Save & test**

**2. Explore logs**

1. Go to **Explore** and select the Loki data source
2. Use the label browser to filter by `unit`, `transport`, or `service_name`
