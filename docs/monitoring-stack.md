# VoidWar Monitoring Stack

This document covers deployment, validation, operation, and troubleshooting for the VoidWar monitoring stack.

For the full system design and traffic flow, see [`architecture.md`](architecture.md).

## Components

The monitoring stack contains:

- Node Exporter for Linux host metrics
- Prometheus for metrics collection and storage
- Grafana for dashboards and visualization

The services run through Docker Compose.

The live deployment directory is:

```text
/opt/voidwar/monitoring
```

The sanitized repository configuration is stored under:

```text
docker/monitoring
```

## Repository Layout

```text
docker/monitoring/
├── .env.example
├── .gitignore
├── compose.yaml
├── grafana/
│   └── provisioning/
│       └── datasources/
│           └── prometheus.yml
└── prometheus/
    └── prometheus.yml
```

Runtime data is intentionally excluded from Git.

## Container Images

The stack currently uses:

```text
quay.io/prometheus/node-exporter:v1.12.1
prom/prometheus:v3.5.2
grafana/grafana-oss:12.1.1
```

Image versions are pinned rather than using floating `latest` tags.

## Service Bindings

All monitoring services use Docker host networking and bind only to the host loopback interface.

| Service | Address |
|---|---|
| Grafana | `127.0.0.1:3000` |
| Prometheus | `127.0.0.1:9090` |
| Node Exporter | `127.0.0.1:9100` |

Grafana is exposed publicly only through the Nginx reverse proxy at:

```text
https://grafana.voidwar.net
```

Prometheus and Node Exporter are not publicly exposed.

## Node Exporter

Node Exporter runs with access to the host PID namespace and a read-only mount of the host filesystem.

Relevant Compose settings:

```yaml
network_mode: host
pid: host

command:
  - --path.rootfs=/host
  - --web.listen-address=127.0.0.1:9100

volumes:
  - /:/host:ro,rslave
```

The `--path.rootfs=/host` option allows the containerized exporter to report host metrics.

The `--web.listen-address` option restricts the metrics endpoint to loopback.

## Prometheus

Prometheus is configured through:

```text
docker/monitoring/prometheus/prometheus.yml
```

The current scrape interval is:

```text
15 seconds
```

Prometheus scrapes:

```text
127.0.0.1:9090
127.0.0.1:9100
```

These targets represent:

- Prometheus self-monitoring
- Node Exporter host metrics

Prometheus listens only on:

```text
127.0.0.1:9090
```

Metrics are retained for:

```text
30 days
```

Prometheus data is stored in the Docker named volume:

```text
monitoring_prometheus-data
```

## Grafana

Grafana listens only on:

```text
127.0.0.1:3000
```

Its public root URL is:

```text
https://grafana.voidwar.net
```

Grafana runtime state is stored under:

```text
/opt/voidwar/monitoring/grafana/data
```

This directory contains application-generated data such as:

- `grafana.db`
- User accounts
- Dashboard state
- Installed plugins
- Application settings

This directory is excluded from Git.

## Grafana Data Source Provisioning

The Prometheus data source is provisioned through:

```text
docker/monitoring/grafana/provisioning/datasources/prometheus.yml
```

It uses:

```text
http://127.0.0.1:9090
```

as the Prometheus URL.

Because both services use host networking, Grafana can access Prometheus through the host loopback interface.

## Grafana Administrator Credentials

The repository Compose file reads the initial Grafana administrator credentials from environment variables:

```yaml
GF_SECURITY_ADMIN_USER: ${GRAFANA_ADMIN_USER:-admin}
GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD:?Set GRAFANA_ADMIN_PASSWORD in .env}
```

Create a local environment file before a fresh deployment:

```bash
cp .env.example .env
```

Then replace the placeholder password in `.env` with a strong unique value.

The real `.env` file is excluded from Git.

These values are primarily used when Grafana initializes a new database. Changing them later does not necessarily replace credentials already stored in an existing `grafana.db`.

## Fresh Deployment

Move into the monitoring directory:

```bash
cd docker/monitoring
```

Create the environment file:

```bash
cp .env.example .env
```

Edit the credentials:

```bash
nano .env
```

Validate the Compose configuration:

```bash
docker compose config
```

Start the stack:

```bash
docker compose up -d
```

Do not start the repository copy on the production host while the live stack is already running from `/opt/voidwar/monitoring`.

Doing so would cause container-name, port, and volume conflicts.

## Container Status

Check the stack:

```bash
docker compose ps
```

Or inspect the named containers:

```bash
docker ps \
  --filter name=voidwar-node-exporter \
  --filter name=voidwar-prometheus \
  --filter name=voidwar-grafana
```

Expected container names:

```text
voidwar-node-exporter
voidwar-prometheus
voidwar-grafana
```

## Validate the Compose File

Run:

```bash
docker compose config
```

This renders the effective configuration and detects syntax or environment-variable errors.

## Verify Listening Addresses

Run:

```bash
sudo ss -lntp | grep -E ':(3000|9090|9100)\b'
```

Expected listeners:

```text
127.0.0.1:3000
127.0.0.1:9090
127.0.0.1:9100
```

A listener on `0.0.0.0`, `[::]`, or `*` should be investigated.

## Verify Grafana

Check Grafana health:

```bash
curl -fsS http://127.0.0.1:3000/api/health
```

A healthy response should include:

```json
{
  "database": "ok"
}
```

Check the public endpoint:

```bash
curl -I https://grafana.voidwar.net
```

The expected response is a redirect to:

```text
/login
```

## Verify Prometheus

Check Prometheus health:

```bash
curl -fsS http://127.0.0.1:9090/-/healthy
```

Expected response:

```text
Prometheus Server is Healthy.
```

Check active scrape targets:

```bash
curl -fsS http://127.0.0.1:9090/api/v1/targets
```

Expected jobs:

```text
prometheus
node-exporter
```

Both should report:

```text
health: up
```

## Verify Node Exporter

Check the metrics endpoint:

```bash
curl -fsS http://127.0.0.1:9100/metrics | sed -n '1,20p'
```

A healthy response contains Prometheus-formatted metrics.

Using `sed` instead of `head` avoids closing the connection early and producing harmless broken-pipe log messages.

## View Logs

Node Exporter:

```bash
docker logs --tail 100 voidwar-node-exporter
```

Prometheus:

```bash
docker logs --tail 100 voidwar-prometheus
```

Grafana:

```bash
docker logs --tail 100 voidwar-grafana
```

Follow a log in real time:

```bash
docker logs -f voidwar-prometheus
```

## Apply Configuration Changes

Validate the Compose file before applying changes:

```bash
docker compose config
```

Recreate a single service:

```bash
docker compose up -d node-exporter
docker compose up -d prometheus
docker compose up -d grafana
```

Recreate the full stack:

```bash
docker compose up -d
```

Persistent Prometheus and Grafana data should survive normal container recreation.

## Reload Prometheus Configuration

Prometheus runs with:

```text
--web.enable-lifecycle
```

After changing `prometheus.yml`, reload the configuration:

```bash
curl -X POST http://127.0.0.1:9090/-/reload
```

Then verify target status:

```bash
curl -fsS http://127.0.0.1:9090/api/v1/targets
```

Prometheus can also be recreated:

```bash
docker compose up -d prometheus
```

## Stop the Stack

Stop containers without removing them:

```bash
docker compose stop
```

Stop and remove the containers:

```bash
docker compose down
```

Do not use:

```bash
docker compose down -v
```

unless deleting the Prometheus metrics volume is intentional.

## Troubleshooting Grafana

If Grafana is unavailable publicly, test it locally:

```bash
curl -I http://127.0.0.1:3000
```

If the local request works, investigate:

- Nginx container status
- Nginx reverse-proxy configuration
- DNS resolution
- TLS certificate validity
- Firewall rules

Check Grafana logs:

```bash
docker logs --tail 100 voidwar-grafana
```

## Troubleshooting Missing Dashboard Data

If Grafana loads but displays no metrics, verify:

```bash
curl -fsS http://127.0.0.1:9090/-/healthy
curl -fsS http://127.0.0.1:9090/api/v1/targets
```

Confirm that the Grafana data source uses:

```text
http://127.0.0.1:9090
```

Check Grafana logs for data-source errors.

## Troubleshooting Node Exporter

If Prometheus reports Node Exporter as down:

```bash
docker ps --filter name=voidwar-node-exporter
sudo ss -lntp | grep ':9100\b'
curl -fsS http://127.0.0.1:9100/metrics
docker logs --tail 100 voidwar-node-exporter
```

Confirm the expected options remain present:

```text
--path.rootfs=/host
--web.listen-address=127.0.0.1:9100
```

Confirm the host mount remains:

```text
/:/host:ro,rslave
```

## Troubleshooting Prometheus

If Prometheus is unhealthy:

```bash
sudo ss -lntp | grep ':9090\b'
curl -fsS http://127.0.0.1:9090/-/healthy
docker logs --tail 100 voidwar-prometheus
```

Validate its mounted configuration:

```bash
docker exec voidwar-prometheus \
  promtool check config /etc/prometheus/prometheus.yml
```

## Runtime Data and Secret Exclusions

The repository excludes:

```text
grafana/data/
grafana.db
grafana-data/
prometheus-data/
data/
.env
.env.*
```

The following must never be committed:

- Real `.env` files
- Grafana administrator passwords
- Grafana databases
- Prometheus time-series data
- Prometheus write-ahead logs
- User sessions
- API tokens
- Installed plugin runtime files

The safe template remains trackable through:

```text
!.env.example
```

## Operational Checklist

After deployment or maintenance, verify:

- [ ] All three containers are running
- [ ] Grafana listens on `127.0.0.1:3000`
- [ ] Prometheus listens on `127.0.0.1:9090`
- [ ] Node Exporter listens on `127.0.0.1:9100`
- [ ] Grafana reports `database: ok`
- [ ] Prometheus reports healthy
- [ ] Node Exporter returns metrics
- [ ] Both Prometheus targets report `up`
- [ ] Grafana can query Prometheus
- [ ] The public Grafana URL reaches the login page
- [ ] No runtime data or real `.env` file is staged in Git

## Summary

The VoidWar monitoring stack uses Node Exporter, Prometheus, and Grafana to provide host-level visibility.

All monitoring services are restricted to the host loopback interface. Grafana is exposed externally only through the Nginx HTTPS reverse proxy, while Prometheus and Node Exporter remain private.

The repository contains the sanitized deployment configuration and provisioning files while excluding credentials, databases, metrics storage, and other runtime data.
