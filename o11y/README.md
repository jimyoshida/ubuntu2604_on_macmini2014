# Observability (o11y) Tools

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

Installs Mimir from the official Grafana APT repository. Mimir listens on `http://localhost:9009` (HTTP) and `9095` (gRPC), and accepts Prometheus remote-write at `/api/v1/push`.
