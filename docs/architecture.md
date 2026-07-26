# VoidWar Infrastructure Architecture

This document describes the architecture of the VoidWar infrastructure environment, including public traffic flow, containerized services, monitoring data flow, service exposure, persistent storage, and operational design decisions.

VoidWar runs on a dedicated Ubuntu Server 22.04 LTS host. The Minecraft server operates as a native Linux workload, while Nginx and the monitoring services run in Docker containers managed with Docker Compose.

## Architecture Overview

```text
                                  Public Internet
                                        |
                               TCP 80 and TCP 443
                                        |
                                        v
                             +---------------------+
                             |   Nginx Container   |
                             |   Host Networking   |
                             +---------------------+
                               |                 |
                               |                 |
                    Static web content      Reverse proxy
                       voidwar.net       grafana.voidwar.net
                                                 |
                                                 | HTTP over loopback
                                                 v
                                      +---------------------+
                                      |  Grafana Container  |
                                      |  127.0.0.1:3000     |
                                      +---------------------+
                                                 |
                                                 | Queries Prometheus
                                                 v
                                      +---------------------+
                                      | Prometheus Container|
                                      | 127.0.0.1:9090      |
                                      +---------------------+
                                          |             |
                                          |             |
                                Scrapes itself      Scrapes host metrics
                                  :9090                    |
                                                           v
                                                +---------------------+
                                                | Node Exporter       |
                                                | 127.0.0.1:9100      |
                                                +---------------------+
```

## Deployment Model

The environment combines native Linux service administration with containerized supporting infrastructure.

The Minecraft application runs directly on Ubuntu and is managed through shell scripts and a persistent `tmux` session.

The following supporting services run in Docker:

- Nginx
- Prometheus
- Node Exporter
- Grafana

Docker Compose defines each service, its image version, restart policy, networking mode, mounted configuration, persistent storage, and security options.

The live deployment is organized under:

```text
/opt/voidwar/nginx
/opt/voidwar/monitoring
```

Sanitized source configuration is published in this repository under:

```text
docker/nginx
docker/monitoring
```

Runtime data, certificate material, credentials, logs, and generated application state are intentionally excluded from Git.

## Public Traffic Flow

Nginx is the only containerized web service exposed directly to the public internet.

It listens on:

```text
TCP 80
TCP 443
```

Nginx handles three public hostnames:

```text
voidwar.net
www.voidwar.net
grafana.voidwar.net
```

Requests to `http://voidwar.net` are redirected to:

```text
https://voidwar.net
```

Requests to the `www` hostname are redirected to the canonical non-`www` hostname:

```text
https://voidwar.net
```

The primary `voidwar.net` hostname serves a static HTML page from a read-only bind mount.

Requests to:

```text
https://grafana.voidwar.net
```

are reverse-proxied by Nginx to:

```text
http://127.0.0.1:3000
```

Grafana is therefore publicly reachable only through the Nginx reverse proxy.

## TLS Termination

Nginx terminates TLS for the public web endpoints.

The production certificate is issued by Let's Encrypt and includes the following subject alternative names:

```text
voidwar.net
www.voidwar.net
grafana.voidwar.net
```

The certificate directory is mounted read-only into the Nginx container:

```text
/etc/letsencrypt:/etc/letsencrypt:ro
```

Private keys and live certificate files are never committed to this repository.

The public Nginx configuration references the expected certificate paths but contains no private certificate material.

HTTP requests are redirected to HTTPS, and the configuration permits:

```text
TLSv1.2
TLSv1.3
```

## ACME Challenge Handling

Nginx exposes the standard ACME HTTP challenge path:

```text
/.well-known/acme-challenge/
```

Challenge files are served from:

```text
/var/www/certbot
```

The host directory used for ACME challenge files is mounted read-only into the Nginx container.

ACME challenge contents are temporary runtime data and are excluded from Git.

## Nginx Reverse Proxy

Nginx forwards requests for `grafana.voidwar.net` to the Grafana service over the host loopback interface.

The reverse proxy forwards the original request context using headers including:

```text
Host
X-Real-IP
X-Forwarded-For
X-Forwarded-Proto
```

HTTP/1.1 and upgrade headers are also configured to support Grafana features that may use upgraded connections.

Grafana is not exposed directly on a public interface.

## Monitoring Data Flow

The monitoring stack follows this data path:

```text
Node Exporter -> Prometheus -> Grafana
```

Node Exporter collects host-level Linux metrics.

Prometheus scrapes Node Exporter every 15 seconds and stores the resulting time-series data.

Grafana queries Prometheus and visualizes the collected metrics.

Prometheus also scrapes its own metrics endpoint for self-monitoring.

## Node Exporter

Node Exporter runs in a Docker container with:

```text
network_mode: host
pid: host
```

The host root filesystem is mounted into the container as:

```text
/:/host:ro,rslave
```

Node Exporter is started with:

```text
--path.rootfs=/host
--web.listen-address=127.0.0.1:9100
```

This allows the containerized exporter to report metrics for the host system rather than only the container filesystem.

The mount is read-only, and the container uses:

```text
no-new-privileges:true
```

Node Exporter listens only on:

```text
127.0.0.1:9100
```

This prevents direct public access to the metrics endpoint. Prometheus accesses it locally over the loopback interface.

## Prometheus

Prometheus runs with host networking and listens only on:

```text
127.0.0.1:9090
```

Its current scrape configuration includes:

```text
127.0.0.1:9090
127.0.0.1:9100
```

These targets represent:

- Prometheus self-monitoring
- Node Exporter host metrics

The global scrape and evaluation intervals are both configured for 15 seconds.

Prometheus retains time-series data for:

```text
30 days
```

Persistent Prometheus data is stored in a Docker-managed named volume.

The Prometheus configuration file is mounted read-only into the container.

The Prometheus web interface and API are not exposed publicly.

## Grafana

Grafana runs with host networking and listens only on:

```text
127.0.0.1:3000
```

Its configured public root URL is:

```text
https://grafana.voidwar.net
```

The service is reachable externally only through Nginx.

Grafana uses a bind-mounted data directory for persistent runtime state. This directory contains generated data such as:

- Grafana's SQLite database
- Installed plugins
- User and dashboard state
- Application-generated files

This runtime directory is excluded from Git.

Grafana provisioning files are mounted read-only.

The Prometheus data source is provisioned automatically with:

```text
http://127.0.0.1:9090
```

as its URL.

The public Compose example requires a Grafana administrator password to be supplied through an ignored `.env` file before initial deployment.

The live Grafana instance uses the community-maintained Node Exporter Full dashboard to visualize system metrics. The dashboard itself is not represented as original work created by this project.

## Host Networking

The Nginx and monitoring containers use Docker host networking.

This design was selected because the services all run on a single dedicated Linux host and communicate through explicit loopback bindings.

Host networking allows:

- Nginx to proxy directly to `127.0.0.1:3000`
- Grafana to access Prometheus at `127.0.0.1:9090`
- Prometheus to scrape Node Exporter at `127.0.0.1:9100`
- Nginx to listen directly on the host's ports 80 and 443

This avoids Docker bridge-address discovery and the earlier unreliable use of `host.docker.internal`.

The tradeoff is that host-networked containers do not receive network isolation from a Docker bridge network. For that reason, each internal service explicitly binds to the loopback interface.

The security boundary is created through both service-level binding and the host firewall.

## Service Exposure

The intended containerized service exposure is:

| Service | Listening address | Publicly reachable |
|---|---|---|
| Nginx HTTP | `0.0.0.0:80` | Yes |
| Nginx HTTPS | `0.0.0.0:443` | Yes |
| Grafana | `127.0.0.1:3000` | Only through Nginx |
| Prometheus | `127.0.0.1:9090` | No |
| Node Exporter | `127.0.0.1:9100` | No |

Only Nginx requires public firewall rules for the web stack.

Ports 3000, 9090, and 9100 do not require public UFW allow rules.

## Container Security Controls

The containerized services use several baseline controls:

- Explicit container image versions
- `restart: unless-stopped`
- Read-only configuration mounts
- Read-only certificate mounts
- Read-only host filesystem mount for Node Exporter
- Loopback-only internal services
- `no-new-privileges:true`
- Credentials supplied outside source control
- Runtime data excluded from Git

Image versions are pinned rather than using floating `latest` tags.

## Persistence

Prometheus stores metrics in a Docker named volume:

```text
monitoring_prometheus-data
```

Grafana stores runtime state in a host bind-mounted directory:

```text
/opt/voidwar/monitoring/grafana/data
```

Nginx configuration and static content are stored as host files and mounted read-only.

The repository contains source configuration and deployment examples, not live runtime data.

## Service Lifecycle

Each container uses:

```text
restart: unless-stopped
```

This allows Docker to restart the services after daemon restarts or host reboots unless an administrator deliberately stopped them.

Docker Compose is used to create, recreate, stop, inspect, and validate the service stacks.

The Nginx and monitoring stacks are maintained separately:

```text
docker/nginx
docker/monitoring
```

This separation allows the public reverse proxy and the internal observability services to be managed independently.

## Configuration Validation

Nginx configuration can be validated inside the running container with:

```bash
docker exec voidwar-nginx nginx -t
```

Docker Compose files can be rendered and validated with:

```bash
docker compose config
```

Prometheus health can be checked with:

```bash
curl -fsS http://127.0.0.1:9090/-/healthy
```

Grafana health can be checked with:

```bash
curl -fsS http://127.0.0.1:3000/api/health
```

Node Exporter metrics can be checked with:

```bash
curl -fsS http://127.0.0.1:9100/metrics
```

Prometheus target health can be checked through:

```bash
curl -fsS http://127.0.0.1:9090/api/v1/targets
```

Expected Prometheus targets are:

```text
prometheus
node-exporter
```

Both should report:

```text
health: up
```

Listening addresses can be verified with:

```bash
sudo ss -lntp | grep -E ':(3000|9090|9100)\b'
```

## Failure Isolation and Troubleshooting

If Grafana is unavailable publicly but responds on `127.0.0.1:3000`, the likely problem is in Nginx, TLS, DNS, or the reverse-proxy configuration.

If Grafana is reachable but displays no metrics, verify:

- The Prometheus data source
- Prometheus health
- Prometheus target status
- The Node Exporter metrics endpoint

If Prometheus reports Node Exporter as down, verify:

- The Node Exporter container is running
- Port 9100 is listening on loopback
- The Prometheus target remains `127.0.0.1:9100`
- The exporter can read the mounted host filesystem
- Container logs contain no startup errors

If Nginx configuration changes fail validation, the existing running configuration should remain in place until the corrected configuration passes `nginx -t`.

## Repository Publication Model

The repository contains sanitized copies of the live configuration.

It intentionally excludes:

- Let's Encrypt private keys
- Live certificate files
- Grafana databases
- Grafana runtime data
- Installed plugin files
- Prometheus time-series data
- Real `.env` files
- Administrator passwords
- ACME challenge runtime files
- Logs
- Backups

The public files are intended to demonstrate and document the implementation. They should be reviewed and adapted before use in another environment.

## Summary

The VoidWar infrastructure uses Nginx as the only public web entry point and TLS termination layer.

Grafana, Prometheus, and Node Exporter are containerized but restricted to the host loopback interface. Prometheus collects host metrics from Node Exporter, and Grafana queries Prometheus to visualize those metrics.

This design provides public HTTPS access to Grafana without directly exposing the monitoring backend, while preserving a clear and maintainable separation between public traffic handling, metrics collection, data storage, and visualization.
