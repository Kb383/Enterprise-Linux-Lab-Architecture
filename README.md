# VoidWar Infrastructure

Linux server administration, security hardening, backup automation, containerized web services, TLS, and observability for **VoidWar**, a self-hosted multiplayer Minecraft server.

VoidWar runs on a live remote bare-metal server rather than a temporary local lab. This repository contains sanitized production configuration, Bash automation, recovery procedures, architecture documentation, and operational runbooks based on the deployed environment.

## What This Project Demonstrates

- Linux server administration
- SSH, UFW, and Fail2Ban hardening
- Bash automation
- Backup and disaster-recovery planning
- Docker and Docker Compose
- Nginx reverse proxying
- HTTPS with Let's Encrypt
- Automated certificate renewal
- Prometheus and Node Exporter
- Grafana provisioning and dashboards
- Infrastructure validation and troubleshooting
- Technical and operational documentation

## Architecture

VoidWar combines a native Linux application workload with containerized supporting infrastructure.

```text
                         Public Internet
                               |
                        TCP 80 and 443
                               |
                               v
                    +---------------------+
                    |   Nginx Container   |
                    |   Host Networking   |
                    +---------------------+
                      |                 |
              Static website       Reverse proxy
                voidwar.net    grafana.voidwar.net
                                        |
                                        v
                             +---------------------+
                             |  Grafana Container  |
                             | 127.0.0.1:3000      |
                             +---------------------+
                                        |
                                        v
                             +---------------------+
                             | Prometheus Container|
                             | 127.0.0.1:9090      |
                             +---------------------+
                                 |             |
                         Self-monitoring       |
                                               v
                                    +---------------------+
                                    | Node Exporter       |
                                    | 127.0.0.1:9100      |
                                    +---------------------+
                                               |
                                               v
                                         Ubuntu Host

                    +---------------------------+
                    | Native Minecraft Workload |
                    | tmux + Bash automation    |
                    +---------------------------+
```

See [`docs/architecture.md`](docs/architecture.md) for the complete design.

## Environment

VoidWar is hosted on a dedicated OVHcloud bare-metal server running Ubuntu Server 22.04 LTS.

### Hardware

- Intel Xeon E3-1230 v6
- 4 cores / 8 threads
- 16 GB ECC RAM
- Dual 450 GB NVMe SSDs
- Software RAID 0
- 1 Gbps network connection

The environment uses older dedicated-server hardware to provide persistent compute, memory, and NVMe storage for approximately $22 per month.

This creates a realistic remote Linux administration environment at substantially lower cost than many newer dedicated-server or public-cloud alternatives.

## Deployment Model

The Minecraft server runs directly on Ubuntu as a native Linux workload managed through:

- Java
- Bash
- `tmux`
- Cron
- Standard Linux users, groups, ownership, and permissions

Supporting infrastructure runs in Docker:

- Nginx
- Prometheus
- Node Exporter
- Grafana

The live deployment is organized under:

```text
/opt/voidwar/nginx
/opt/voidwar/monitoring
```

Sanitized repository configuration is published under:

```text
docker/nginx
docker/monitoring
```

Runtime data, credentials, certificates, metrics storage, logs, and generated application state are excluded from Git.

## Public Web Infrastructure

Nginx runs in Docker with host networking and serves as the public HTTP and HTTPS entry point.

It handles:

```text
voidwar.net
www.voidwar.net
grafana.voidwar.net
```

Implemented behavior includes:

- HTTP-to-HTTPS redirection
- Static content at `voidwar.net`
- Canonical redirect from `www.voidwar.net`
- TLS termination
- ACME HTTP challenge handling
- Reverse proxying to Grafana
- Forwarded client and protocol headers
- HTTP upgrade support

TLS certificates are issued by Let's Encrypt and mounted read-only from:

```text
/etc/letsencrypt
```

Certificate renewal is automated through `certbot.timer`.

After a successful renewal, a deploy hook validates and gracefully reloads the Nginx container.

See [`docs/nginx-tls-deployment.md`](docs/nginx-tls-deployment.md).

## Monitoring and Observability

The monitoring pipeline is:

```text
Node Exporter -> Prometheus -> Grafana
```

### Node Exporter

Node Exporter collects Linux host metrics such as:

- CPU utilization
- Memory usage
- Filesystem capacity
- Disk activity
- Network activity
- System load

It listens only on:

```text
127.0.0.1:9100
```

### Prometheus

Prometheus scrapes:

```text
127.0.0.1:9090
127.0.0.1:9100
```

These targets provide Prometheus self-monitoring and Node Exporter host metrics.

The deployment uses:

- 15-second scrape interval
- 15-second evaluation interval
- 30-day retention
- Persistent Docker volume storage

Prometheus listens only on:

```text
127.0.0.1:9090
```

### Grafana

Grafana queries Prometheus and displays the collected metrics through dashboards.

It listens only on:

```text
127.0.0.1:3000
```

Public access is provided through Nginx at:

```text
https://grafana.voidwar.net
```

The Prometheus data source is provisioned automatically.

The live environment currently uses the community-maintained Node Exporter Full dashboard. The dashboard itself is not represented as original work created by this project.

See [`docs/monitoring-stack.md`](docs/monitoring-stack.md).

## Service Exposure

| Service | Listening address | Publicly reachable |
|---|---|---|
| Nginx HTTP | Public port 80 | Yes |
| Nginx HTTPS | Public port 443 | Yes |
| Grafana | `127.0.0.1:3000` | Through Nginx only |
| Prometheus | `127.0.0.1:9090` | No |
| Node Exporter | `127.0.0.1:9100` | No |

The monitoring containers use host networking, so internal services are explicitly bound to the loopback interface.

## Security Hardening

### SSH

Remote administration uses public-key authentication.

Implemented controls include:

- Ed25519 SSH keys
- Disabled direct root login
- Disabled password authentication
- Non-root administrative account
- Custom SSH listening port
- Explicit user access controls

Example configuration:

```text
config/ssh/sshd_config.example
```

### Firewall

UFW enforces a minimal-exposure policy:

- Deny unsolicited inbound traffic by default
- Allow only required service ports
- Keep monitoring backends private
- Disable IPv6 where it is not currently required

Example rules:

```text
config/ufw/ufw-rules.example
```

### Fail2Ban

Fail2Ban monitors SSH events through the systemd journal.

The SSH jail includes:

- `systemd` backend
- Repeated-failure detection
- Temporary bans
- Custom SSH port protection
- Loopback exclusions
- Firewall-based enforcement

Example configuration:

```text
config/fail2ban/custom_hardening.local.example
```

Detailed documentation is available in [`docs/security-hardening.md`](docs/security-hardening.md).

## User and Permission Management

The server uses separate Linux accounts to limit unnecessary privilege exposure.

Implemented practices include:

- Non-root administration
- Limited collaborator permissions
- Controlled access to project directories
- Standard ownership and permission enforcement
- Shared group access where appropriate
- Symbolic links to approved workspaces

Collaborators can access specific project areas without receiving broad administrative access to the server.

## Backup Automation

The repository includes:

```text
scripts/backup_system.sh
```

The backup workflow provides:

- Timestamped compressed archives
- Player-facing maintenance warnings
- Graceful Minecraft shutdown
- Process-aware shutdown waiting
- Automatic restart when appropriate
- Preservation of an intentionally stopped state
- Error and cancellation handling
- Cron-compatible logging
- Grandfather-Father-Son retention

Retention includes:

- 7 daily backups
- 4 weekly backups
- 6 monthly backups

Additional workstation copies are maintained for disaster recovery.

Documentation:

- [`docs/backup-workflow.md`](docs/backup-workflow.md)
- [`docs/restore-procedure.md`](docs/restore-procedure.md)

## Session and Process Management

`tmux` keeps the Minecraft console available independently of individual SSH sessions.

This allows:

- The server process to survive SSH disconnects
- Administrators to reconnect to the live console
- Automation to send console commands
- Backup scripts to issue warnings and graceful shutdowns

## Container Security Controls

The Docker deployment uses:

- Pinned image versions
- `restart: unless-stopped`
- Read-only configuration mounts
- Read-only certificate mounts
- Read-only host filesystem access for Node Exporter
- Loopback-only monitoring listeners
- `no-new-privileges:true`
- Credentials supplied outside source control
- Separation of source configuration and runtime data

The Grafana deployment requires a local ignored `.env` file.

A safe template is provided at:

```text
docker/monitoring/.env.example
```

## Repository Structure

```text
.
├── config/
│   ├── fail2ban/
│   ├── ssh/
│   └── ufw/
├── docker/
│   ├── monitoring/
│   │   ├── grafana/
│   │   ├── prometheus/
│   │   ├── .env.example
│   │   └── compose.yaml
│   └── nginx/
│       ├── conf/
│       ├── html/
│       └── compose.yaml
├── docs/
│   ├── architecture.md
│   ├── backup-workflow.md
│   ├── maintenance-runbook.md
│   ├── monitoring-stack.md
│   ├── nginx-tls-deployment.md
│   ├── restore-procedure.md
│   └── security-hardening.md
├── scripts/
│   └── backup_system.sh
├── .gitignore
└── README.md
```

## Documentation

### Architecture and Services

- [`docs/architecture.md`](docs/architecture.md)
- [`docs/monitoring-stack.md`](docs/monitoring-stack.md)
- [`docs/nginx-tls-deployment.md`](docs/nginx-tls-deployment.md)

### Security and Operations

- [`docs/security-hardening.md`](docs/security-hardening.md)
- [`docs/maintenance-runbook.md`](docs/maintenance-runbook.md)

### Backup and Recovery

- [`docs/backup-workflow.md`](docs/backup-workflow.md)
- [`docs/restore-procedure.md`](docs/restore-procedure.md)

## Repository Security

This repository intentionally excludes:

- SSH private keys
- TLS private keys and certificates
- Certbot account data
- Real `.env` files
- Administrator passwords
- Grafana databases and runtime data
- Prometheus metrics storage
- ACME challenge runtime files
- Server backups
- Logs and temporary files

Configuration is sanitized before publication.

## Validation

The deployed environment has been validated through:

- Docker Compose configuration rendering
- Nginx configuration testing
- HTTP and HTTPS endpoint checks
- TLS certificate inspection
- Certbot renewal simulation
- Grafana health checks
- Prometheus health and target checks
- Node Exporter metrics retrieval
- Listening-address verification
- Container status and log inspection
- Fail2Ban journal and jail inspection
- Backup and restart workflow testing

## Planned Improvements

Potential future additions include:

- A visual architecture diagram
- Automated infrastructure verification script
- Custom Grafana dashboards
- Prometheus alerting rules
- External uptime monitoring
- Additional off-host backup automation
- Automated security-update workflow
- Expanded application-level monitoring

## Project Goal

VoidWar began as a multiplayer Minecraft server, but the infrastructure project extends beyond running the game itself.

The server serves as a practical platform for building and documenting:

- Secure Linux administration
- Production-style automation
- Containerized supporting services
- Public HTTPS infrastructure
- Monitoring and observability
- Backup and recovery procedures
- Repeatable operational workflows

The goal is to demonstrate the ability to build, secure, operate, monitor, troubleshoot, and document a persistent remote Linux environment.
