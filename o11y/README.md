# Observability (o11y) Tools

#### node_exporter.yml

Install Prometheus Node Exporter (host metrics collector)

```bash
ansible-playbook o11y/node_exporter.yml
```

Installs `prometheus-node-exporter` from the Ubuntu apt repository. Node Exporter exposes host metrics (CPU, memory, disk, network) at `http://localhost:9100/metrics`.

#### prometheus.yml

Install Prometheus (metrics scraper and Mimir forwarder)

```bash
ansible-playbook o11y/prometheus.yml
```

Installs Prometheus from the Ubuntu apt repository and configures it to scrape Node Exporter (`localhost:9100`) every 15 seconds and remote-write metrics to Mimir (`http://localhost:9009/api/v1/push`) with the required `X-Scope-OrgID: anonymous` header.

#### grafana.yml

Install Grafana

```bash
ansible-playbook o11y/grafana.yml
```

Installs Grafana from the official Grafana APT repository. After installation, Grafana is available at `http://localhost:3000` (default credentials: `admin` / `admin`).

#### loki.yml

Install Grafana Loki (log aggregation)

```bash
ansible-playbook o11y/loki.yml
```

Installs Loki from the official Grafana APT repository. Loki listens on `http://localhost:3100` (HTTP) and `9096` (gRPC). Add it as a data source in Grafana using the HTTP URL.

#### tempo.yml

Install Grafana Tempo (distributed tracing)

```bash
ansible-playbook o11y/tempo.yml
```

Installs Tempo from the official Grafana APT repository. Tempo listens on `http://localhost:3200` (HTTP) and `9097` (gRPC), and accepts traces via OTLP on ports `4317` (gRPC) and `4318` (HTTP).

> **Note:** The playbook sets `grpc_listen_port: 9097` in `/etc/tempo/config.yml` to avoid conflicts with Mimir (`9095`) and Loki (`9096`).

#### mimir.yml

Install Grafana Mimir (metrics backend)

```bash
ansible-playbook o11y/mimir.yml
```

Installs Mimir from the official Grafana APT repository and configures it for single-node deployment (`replication_factor: 1`). Mimir listens on `http://localhost:9009` (HTTP) and `9095` (gRPC), and accepts Prometheus remote-write at `/api/v1/push`.

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
