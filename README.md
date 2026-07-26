# VoidWar Infrastructure

Linux server administration, security hardening, backup automation, and monitoring documentation for **VoidWar**, a self-hosted multiplayer Minecraft server project.

This repository documents the infrastructure behind the server, including system configuration, access controls, firewall rules, backup workflows, automation scripts, and future monitoring services.

The goal of this project is to demonstrate practical Linux administration and infrastructure operations in a live remote server environment.

## Current Environment

VoidWar is hosted on a dedicated OVHcloud bare-metal server running Ubuntu Server 22.04 LTS.

### Hardware

- Intel Xeon E3-1230v6
- 4 cores / 8 threads
- 16 GB ECC RAM
- Dual 450 GB NVMe SSDs
- Software RAID 0 storage configuration

### Cost-Efficient Dedicated Hosting

This environment is intentionally built on older dedicated server hardware to balance performance and cost. The server provides dedicated CPU, memory, and NVMe storage resources for approximately $22/month, making it significantly more cost-effective than many newer dedicated server or public cloud alternatives for this type of workload.

The goal is to practice real Linux server administration on dedicated hardware while keeping monthly infrastructure costs low.

### Current Deployment Model

VoidWar currently runs as a native Linux workload on Ubuntu Server. Supporting infrastructure services such as monitoring and observability are planned to be added with Docker and Docker Compose.

This approach allows the project to document both traditional Linux server administration and modern container-based service deployment.

## Infrastructure Areas

### SSH Hardening

Remote administration is performed through SSH using public-key authentication.

Implemented controls include:

- Ed25519 SSH key authentication
- Disabled root SSH login
- Disabled password-based SSH authentication
- Separate non-root administrative user
- Remote access through SSH/SFTP tools such as PuTTY and WinSCP

### Firewall Configuration

The server uses UFW as a local firewall frontend for Linux Netfilter.

Firewall configuration follows a minimal-exposure approach:

- Only required inbound service ports are allowed
- Unused inbound traffic is denied
- Firewall rules are documented for repeatability
- IPv6 is disabled where not currently needed

### Intrusion Prevention

Fail2Ban is used to monitor SSH authentication attempts and respond to repeated failed logins.

Current protections include:

- SSH log monitoring through `/var/log/auth.log`
- Temporary bans for repeated authentication failures
- Integration with local firewall rules
- Basic brute-force mitigation for public-facing SSH access

### User and Permission Management

The server uses separate Linux user accounts to reduce unnecessary privilege exposure.

Implemented practices include:

- Non-root administration
- Limited permissions for non-administrative users
- Controlled access to project directories
- Standard Linux ownership and permission management
- Shared workspace access where appropriate
- Symbolic links for simplified navigation to approved project directories

Symbolic links are used to provide convenient access to specific shared workspaces without granting broader access to the full server directory tree. For example, a collaborator who only needed access to plugin-related development files was given access to the approved plugins workspace rather than full administrative access to the server.

File ownership and permissions are still enforced through standard Linux user, group, and directory controls.

### Backup Automation

This repository includes a Bash-based backup workflow for creating compressed backups of the Minecraft server directory.

The current backup workflow is implemented by:

```text
scripts/backup_system.sh
```

Current backup behavior includes:

- Timestamped `.tar.gz` archive creation
- Configurable backup source and destination paths
- Player-facing maintenance warnings using Minecraft `tellraw`
- Graceful Minecraft shutdown before archive creation
- Process-aware waiting for the Minecraft Java process to fully exit
- Automatic server restart if the server was running when the backup began
- Preservation of original server state if the server was already stopped
- Basic error handling and cancellation cleanup
- Grandfather-Father-Son (GFS) retention with:
  - 7 daily backups
  - 4 weekly backups
  - 6 monthly backups
- Automatic retention management for each backup tier
- Backup logging through cron output redirection

Backup and restore documentation is available at:

```text
docs/backup-workflow.md
docs/restore-procedure.md
```

The backup strategy includes both server-side backups and additional local workstation copies for disaster recovery.

### Session and Process Management

`tmux` is used to manage long-running server console sessions independently of SSH connectivity.

This allows administrative sessions and server processes to remain available even if the local SSH connection drops.

## Planned Improvements

Planned infrastructure additions include:

- Docker installation and Docker Compose examples
- Nginx reverse proxy configuration
- Prometheus metrics collection
- Grafana dashboard setup
- Automated security update workflow
- Expanded backup and restore documentation
- Service monitoring and uptime checks

## Repository Structure

```text
/scripts
  Bash scripts for backups, maintenance, and automation

/config
  Example configuration files for SSH, UFW, Fail2Ban, nginx, Docker, and monitoring tools

/docs
  Setup notes, hardening documentation, recovery procedures, and operational runbooks
