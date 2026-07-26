# Restore Procedure

This document explains how to restore the VoidWar Minecraft server from a compressed backup archive created by:

```text
scripts/backup_system.sh
```

The goal of this procedure is to restore the Minecraft server safely while avoiding accidental data loss, incomplete restores, or permission issues.

## Overview

The VoidWar backup strategy uses compressed `.tar.gz` archives of the Minecraft server directory.

Backups may exist in two locations:

```text
/home/blockboss/backups/daily
/home/blockboss/backups/weekly
/home/blockboss/backups/monthly
```

and on a local workstation.

The server-side backup directories provide fast access to daily, weekly, and monthly recovery points. The local workstation copy provides an additional layer of protection if the dedicated server becomes unavailable, fails, or the server-side backup directories are damaged.

## Backup Sources

### Server-Side Backups

Server-side backups are organized into Grandfather-Father-Son (GFS) retention tiers under:

```text
/home/blockboss/backups/daily
/home/blockboss/backups/weekly
/home/blockboss/backups/monthly
```

Backup files use a date-based naming format:

```text
mcserver-YYYY-MM-DD.tar.gz
```

Example:

```text
mcserver-2026-07-07.tar.gz
```

### Local Workstation Backups

Backup archives are also copied to a local workstation outside the server environment.

This protects against scenarios where the server itself is lost, corrupted, misconfigured, or inaccessible.

The exact local workstation path may vary and is intentionally not documented in this public repository.

## Restore Safety Notes

Before restoring a backup, confirm the following:

- The Minecraft server is stopped
- The selected backup archive exists
- The backup file is the correct restore point
- A pre-restore safety copy has been created
- File ownership and permissions are checked after extraction
- The server starts successfully after the restore
- Logs are reviewed after startup

Do not restore over an actively running Minecraft server.

Restoring while the server is running can cause file conflicts, world corruption, or inconsistent server state.

## Stop the Minecraft Server

Attach to the Minecraft `tmux` session:

```bash
tmux attach -t minecraft
```

In the Minecraft console, run:

```text
stop
```

Wait for the Minecraft server process to fully exit.

Detach from `tmux` if needed:

```text
Ctrl + B
D
```

Verify that the Minecraft Java process is no longer running:

```bash
pgrep -af "java.*minecraft_server|java.*paper|java.*spigot|java.*server.jar"
```

If the command returns no active Minecraft Java process, the server is stopped.

## Select a Backup Archive

List available server-side backups:

```bash
find /home/blockboss/backups \
    -type f \
    -name "mcserver-*.tar.gz" \
    -printf "%TY-%Tm-%Td %TH:%TM %p\n" | sort
```

Choose the backup archive that should be restored.

Example:

```text
/home/blockboss/backups/mcserver-2026-07-07.tar.gz
```

## Restore From a Local Workstation Backup

If the server-side backup is missing or unusable, copy a backup archive from the local workstation back to the server.

Example using `scp` from the local workstation:

```bash
scp mcserver-YYYY-MM-DD.tar.gz blockboss@server-address:/home/blockboss/backups/daily/
```

If the production SSH port is non-standard, specify the port with `-P`:

```bash
scp -P <ssh_port> mcserver-YYYY-MM-DD.tar.gz blockboss@server-address:/home/blockboss/backups/daily/
```

This repository intentionally uses placeholders for server address and SSH port.

After copying the archive, verify that it exists on the server:

```bash
ls -lh /home/blockboss/backups/daily/mcserver-YYYY-MM-DD.tar.gz
```

## Create a Pre-Restore Safety Copy

Before replacing the current Minecraft server directory, create a safety copy of the existing state.

This makes it possible to recover if the wrong backup was selected or if the restore does not behave as expected.

Example:

```bash
cd /home/blockboss
mv minecraft_server minecraft_server.pre-restore-$(date +%F-%H%M%S)
```

This preserves the current server directory instead of deleting it.

## Recreate the Minecraft Server Directory

Create a fresh target directory:

```bash
mkdir -p /home/blockboss/minecraft_server
```

## Extract the Backup Archive

Extract the selected backup archive into the Minecraft server directory.

Example:

```bash
tar -xzf /home/blockboss/backups/mcserver-YYYY-MM-DD.tar.gz -C /home/blockboss/minecraft_server
```

Replace `mcserver-YYYY-MM-DD.tar.gz` with the actual backup file being restored.

## Fix Ownership and Permissions

After extraction, verify ownership and permissions.

Example:

```bash
sudo chown -R blockboss:blockboss /home/blockboss/minecraft_server
```

Ensure the server start script is executable:

```bash
chmod +x /home/blockboss/minecraft_server/start.sh
```

## Start the Minecraft Server

Start or reattach to the Minecraft `tmux` session.

If the `minecraft` tmux session already exists:

```bash
tmux attach -t minecraft
```

Then run:

```bash
cd /home/blockboss/minecraft_server && ./start.sh
```

If the `minecraft` tmux session does not exist, create a new one:

```bash
tmux new-session -d -s minecraft "cd /home/blockboss/minecraft_server && ./start.sh"
```

Attach to the session if needed:

```bash
tmux attach -t minecraft
```

## Validate the Restore

After starting the server, validate that the restore succeeded.

Check that the Minecraft process is running:

```bash
pgrep -af "java.*minecraft_server|java.*paper|java.*spigot|java.*server.jar"
```

Check the server console through `tmux`:

```bash
tmux attach -t minecraft
```

Review recent logs:

```bash
tail -100 /home/blockboss/minecraft_server/logs/latest.log
```

Confirm the following:

- Server starts without major errors
- World loads successfully
- Plugins load as expected
- Players can connect
- Restored files match the intended backup date
- No unexpected permission errors appear in logs

## Rollback Option

If the restore fails or the wrong backup was selected, stop the Minecraft server again and restore the pre-restore safety copy.

Stop the server from the Minecraft console:

```text
stop
```

Move the failed restored directory aside:

```bash
cd /home/blockboss
mv minecraft_server minecraft_server.failed-restore-$(date +%F-%H%M%S)
```

Move the pre-restore copy back into place:

```bash
mv minecraft_server.pre-restore-YYYY-MM-DD-HHMMSS minecraft_server
```

Then restart the server:

```bash
tmux new-session -d -s minecraft "cd /home/blockboss/minecraft_server && ./start.sh"
```

Replace the timestamped directory name with the actual pre-restore directory that was created.

## Disaster Recovery Notes

If the server is lost completely, the local workstation backup can be used to rebuild the Minecraft server directory on a fresh Linux server.

A full recovery would require:

- Fresh Linux server provisioned
- Java installed
- Required firewall rules configured
- SSH access configured
- Minecraft server directory restored from backup
- Ownership and permissions corrected
- `tmux` session recreated
- Server started with `start.sh`
- Logs reviewed after startup

The local workstation backup protects against total server-side backup loss.

## Skills Demonstrated

This restore process demonstrates practical Linux administration and disaster recovery concepts, including:

- Backup archive restoration
- Server-side and off-server backup strategy
- Safe restore workflow
- Pre-restore safety copies
- `tar` archive extraction
- Ownership and permission correction
- `tmux` process management
- Minecraft server recovery
- Log-based validation
- Rollback planning
- Basic disaster recovery thinking

## Summary

The VoidWar restore process is designed to recover the Minecraft server from compressed backup archives while minimizing the risk of additional data loss.

Backups are kept both on the server and on a local workstation. Server-side backups allow quick restores, while local workstation backups provide protection if the server environment itself becomes unavailable.

The restore process stops the server, selects a backup archive, preserves the current server state, extracts the backup, fixes permissions, restarts the server, validates logs, and keeps rollback options available.
