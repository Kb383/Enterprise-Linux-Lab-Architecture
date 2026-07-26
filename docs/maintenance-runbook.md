# Maintenance Runbook

This document describes common operational tasks used to administer the VoidWar infrastructure environment.

The procedures in this runbook are intended for routine maintenance, monitoring, troubleshooting, and service management.

## Environment

Primary services include:

- Ubuntu Server
- Paper Minecraft Server
- SSH
- tmux
- UFW
- Fail2Ban
- cron

## tmux Aliases

The server uses shell aliases for common `tmux` operations.

```bash
tms
```

Creates a new `tmux` session.

```bash
tma
```

Attaches to the existing `minecraft` tmux session.

```bash
tml
```

Lists all active `tmux` sessions.

## Attach to the Minecraft Console

Attach to the Minecraft console:

```bash
tma
```

Detach without stopping the server:

```text
Ctrl + B
D
```

## Verify Server Status

Determine whether the Paper Minecraft server is currently running:

```bash
pgrep -af 'java.*-jar paper-.*\.jar.*nogui'
```

No output indicates that the Minecraft server is currently stopped.

## Start the Minecraft Server

If the Minecraft server is not currently running:

1. Attach to the existing `minecraft` tmux session.

```bash
tma
```

2. Navigate to the server directory.

```bash
cd /home/blockboss/minecraft_server
```

3. Start the server.

```bash
./start.sh
```

## Stop the Minecraft Server

Attach to the Minecraft console:

```bash
tma
```

Issue a graceful shutdown:

```text
stop
```

Wait until the Java process exits before performing maintenance.

## Restart the Minecraft Server

Restarting should always use a graceful shutdown.

1. Attach to the Minecraft console.

```bash
tma
```

2. Execute:

```text
stop
```

3. Wait until the Paper server exits.

4. Navigate to the server directory.

```bash
cd /home/blockboss/minecraft_server
```

5. Restart the server.

```bash
./start.sh
```

## Review Recent Logs

View the latest Minecraft log:

```bash
tail -100 /home/blockboss/minecraft_server/logs/latest.log
```

Follow the log in real time:

```bash
tail -f /home/blockboss/minecraft_server/logs/latest.log
```

## Review Backup Archives

List available backups in each retention tier:

```bash
ls -lh /home/blockboss/backups/daily
ls -lh /home/blockboss/backups/weekly
ls -lh /home/blockboss/backups/monthly
```

Locate all backups by date across every retention tier:

```bash
find /home/blockboss/backups -type f -name "mcserver-*.tar.gz" -printf "%TY-%Tm-%Td %TH:%TM %p\n" | sort
```

## Review Backup Logs

The backup workflow implemented by `scripts/backup_system.sh` writes output to a dedicated log file.

```bash
tail -100 /home/blockboss/backups/backup.log
```

Follow the backup log in real time:

```bash
tail -f /home/blockboss/backups/backup.log
```

## Check Disk Usage

Display filesystem usage:

```bash
df -h
```

Display directory sizes:

```bash
du -sh /home/blockboss/*
```

## Check Memory Usage

Display memory statistics:

```bash
free -h
```

## Check System Uptime

Display system uptime:

```bash
uptime
```

## Check UFW Status

Display active firewall rules:

```bash
sudo ufw status verbose
```

## Check Fail2Ban Status

Display overall Fail2Ban status:

```bash
sudo fail2ban-client status
```

Display the SSH jail status:

```bash
sudo fail2ban-client status sshd
```

## Check SSH Service

Verify that the SSH service is running:

```bash
sudo systemctl status ssh --no-pager
```

Validate the active SSH daemon configuration:

```bash
sudo sshd -T
```

## Update the System

Refresh package indexes:

```bash
sudo apt update
```

Install available package updates:

```bash
sudo apt upgrade
```

If a new Linux kernel is installed, gracefully stop the Minecraft server before rebooting.

Reboot the server:

```bash
sudo reboot
```

After reconnecting, verify that the expected kernel is running:

```bash
uname -r
```

## Common Troubleshooting

If the Minecraft server fails to start:

- Verify Java is installed.
- Review the latest server log.
- Confirm the server directory exists.
- Verify `start.sh` is executable.

If a new SSH connection fails but an existing SSH session is still open:

- Keep the existing session open.
- Confirm the SSH service is running.
- Verify firewall rules.
- Validate the SSH daemon configuration.
- Review authentication logs.
- Test a second SSH connection before closing the working session.

If all SSH access is lost:

- Use OVHcloud's management panel, remote console, or rescue environment.
- Verify that the server is online and reachable.
- Inspect the SSH configuration and firewall rules from the recovery environment.
- Correct the configuration before rebooting into the normal system.

If backups fail:

- Confirm the backup destination exists.
- Verify available disk space.
- Review the backup log.
- Confirm the Minecraft server stopped gracefully before the backup began.

## Related Documentation

Additional documentation is available in:

```text
README.md
docs/backup-workflow.md
docs/restore-procedure.md
docs/security-hardening.md
```

## Skills Demonstrated

This runbook demonstrates practical Linux systems administration concepts including:

- Routine server administration
- Service lifecycle management
- Log inspection
- Process monitoring
- Storage management
- Firewall administration
- SSH administration
- Fail2Ban management
- Backup verification
- Operational documentation

## Summary

This runbook provides a centralized reference for routine administration of the VoidWar infrastructure environment.

The documented procedures support consistent operation, troubleshooting, maintenance, and recovery of the Linux server and Minecraft services.
