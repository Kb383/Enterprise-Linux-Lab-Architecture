# Minecraft Backup and Restart Workflow

This document explains the automated backup and recovery workflow used for the VoidWar Minecraft server.

The workflow is implemented by:

```text
scripts/backup_system.sh
```

The goal of this workflow is to create consistent, validated backups while minimizing the risk of world corruption, incomplete archives, unmanaged downtime, or accidental data loss.

## Problem

The original backup process created a compressed archive while the Minecraft server was still running.

This caused the following warning during backup creation:

```text
tar: ./world: file changed as we read it
```

This warning indicated that Minecraft world files were being modified while `tar` was reading them. Because the server was actively writing world data during the archive process, the resulting backup could be inconsistent.

For a live Minecraft server, this is not ideal. A backup should capture the server files in a stable state.

In addition, retaining only a small number of recent backups limits recovery options if data corruption or configuration problems are discovered several weeks after they occur.

## Solution

The backup workflow was redesigned to avoid creating archives while the Minecraft server is actively writing world data.

If the Minecraft server is running when the backup begins, the script:

- Detects the running server process
- Broadcasts maintenance warnings to players
- Gracefully shuts down the Minecraft server
- Waits for the Java process to fully exit
- Creates and validates a compressed backup archive
- Restores the Minecraft server to its original running state

If the Minecraft server is already stopped when the backup begins, the script creates and validates the backup without starting the server afterward.

The current workflow follows this sequence:

```text
Detect whether the Minecraft server is running
If running, broadcast maintenance warnings
If running, gracefully stop the Minecraft server
Wait for the Java process to exit completely
Create a temporary compressed backup archive
Restore the original server runtime state
Validate the temporary archive
Finalize the validated daily backup
Promote validated backups into GFS retention tiers when applicable
Enforce retention policies
```

This workflow ensures that world files are not changing during archive creation while providing multiple recovery points over time.

## Player Notifications

When the Minecraft server is running, the script sends in-game maintenance warnings using Minecraft `tellraw` commands.

Warnings are broadcast before shutdown so players have time to safely finish active tasks.

Example messages include:

```text
[Maintenance] The scheduled server restart and backup will begin in 5 minutes.
[Maintenance] The scheduled server restart and backup will begin in 1 minute. Please finish any active tasks.
[Maintenance] The scheduled server restart and backup will begin in 10 seconds.
```

`tellraw` is used instead of the `say` command because `say` automatically prefixes messages with `[Server]`. Using `tellraw` allows maintenance messages to appear with the intended `[Maintenance]` prefix.

If the Minecraft server is already stopped when the backup begins, player notifications are skipped because there are no connected players.

## Graceful Shutdown

When the Minecraft server is running, the script issues the standard Minecraft console command:

```text
stop
```

This allows the server to save world data and shut down cleanly rather than terminating the Java process abruptly.

Before sending the stop command, the script records the Minecraft server process ID. After shutdown begins, it waits until that exact Java process has exited before continuing.

This avoids relying on arbitrary delays such as:

```text
sleep 30
```

and ensures that all world data has finished writing before the archive is created.

## Process-Aware Waiting

The backup workflow continuously checks whether the captured Minecraft Java process is still running.

The backup archive is not created until the original process has completely exited.

This guarantees that the backup is taken only after all world files are no longer changing.

## Backup Creation

After the Minecraft server has stopped, or if it was already stopped before the backup began, the script creates a compressed `.tar.gz` archive of the Minecraft server directory.

Backups are organized into separate retention tiers:

```text
/home/blockboss/backups/daily
/home/blockboss/backups/weekly
/home/blockboss/backups/monthly
```

Backup files use a date-based naming convention:

```text
mcserver-YYYY-MM-DD.tar.gz
```

For example:

```text
mcserver-2026-07-17.tar.gz
```

Because the Minecraft server is not actively writing files during archive creation, the resulting backup captures a consistent snapshot of the server directory.

## Backup Validation

The backup workflow validates every newly created archive before it becomes part of the retention system.

After the temporary archive has been created and the Minecraft server has been restored to its original runtime state, validation is performed using:

```bash
tar -tzf
```

Only archives that successfully pass validation are finalized as daily backups and become eligible for promotion into the weekly and monthly retention tiers.

This reduces the likelihood of retaining incomplete or corrupted backup files.

## Preserving Original Server State

The backup script preserves the Minecraft server's original runtime state.

If the Minecraft server was running when the backup began, the script:

- broadcasts maintenance warnings
- gracefully shuts down the server
- creates a temporary backup archive
- restores the server to its original running state
- validates the temporary archive
- finalizes the validated backup

If the Minecraft server was already stopped before the backup began, the script:

- skips player notifications
- skips shutdown
- creates and validates the backup
- leaves the server stopped

This prevents scheduled backups from unintentionally starting the Minecraft server during maintenance, debugging, plugin development, or intentional downtime.

## Automatic Restart

The Minecraft server is restarted only if it was running before the backup began.

When a restart is required, the script launches the existing:

```text
start.sh
```

inside the configured `tmux` session.

After issuing the restart command, the script verifies that a new Minecraft Java process appears before continuing.

If the Minecraft server was already stopped before the backup began, the script does not start it afterward.

## Grandfather-Father-Son (GFS) Retention Strategy

The backup workflow implements a Grandfather-Father-Son (GFS) retention strategy.

Backups are organized into three independent retention tiers:

```text
daily/
weekly/
monthly/
```

Current retention policy:

```text
Daily:   7 backups
Weekly:  4 backups
Monthly: 6 backups
```

Every successful backup is first written into the daily tier.

If the backup occurs on Sunday, the validated daily archive is promoted into the weekly tier.

If the backup occurs on the first day of the month, the validated daily archive is also promoted into the monthly tier.

Each retention tier is managed independently.

Older backup archives exceeding the configured retention limits are automatically removed.

Using multiple retention tiers provides significantly longer recovery windows than retaining only recent daily backups while maintaining predictable storage utilization.

## Concurrency Protection

The backup workflow prevents multiple backup processes from executing simultaneously.

A lock file is used together with `flock` to ensure that only one instance of the backup script can run at a time.

This prevents conflicts caused by accidental manual execution while a scheduled backup is already in progress.

## Cancellation Handling

The backup workflow includes cleanup logic for interrupted executions.

If the backup is cancelled before the Minecraft server shuts down, the script sends an in-game cancellation message:

```text
[Maintenance] The scheduled server restart and backup was manually cancelled. VoidWar will remain online.
```

If the backup is interrupted after the Minecraft server has already stopped, cleanup logic attempts to restore the server to its original running state.

If the Minecraft server was already stopped before the backup began, cancellation does not start the server.

These safeguards reduce the risk of accidentally leaving the Minecraft server offline after an interrupted backup operation.

## Cron Scheduling

The backup workflow is executed automatically through `cron`.

The scheduled job runs:

```text
scripts/backup_system.sh
```

Standard output and error output are appended to a dedicated backup log.

Logging backup activity simplifies troubleshooting by providing a history of:

- backup execution
- archive validation
- retention cleanup
- restart operations
- error messages

## Skills Demonstrated

This workflow demonstrates practical Linux systems administration concepts including:

- Bash scripting
- Cron-based automation
- Linux process management
- Minecraft server administration
- `tmux` session management
- Graceful application shutdown
- Process ID detection and monitoring
- Compressed archive creation using `tar`
- Archive validation
- Grandfather-Father-Son (GFS) backup strategy
- Automated retention management
- Concurrency control using `flock`
- Player-facing maintenance notifications
- Failure and cancellation handling
- Preserving original service state during automation
- Operational documentation

## Summary

The VoidWar backup workflow evolved from a simple live-file archive into a documented backup and recovery system.

The current implementation detects the Minecraft server's runtime state, gracefully notifies players when required, safely shuts down the server, waits for the original Java process to exit, creates and validates compressed backup archives, preserves the server's original runtime state, organizes backups using a Grandfather-Father-Son (GFS) retention strategy, prevents concurrent backup execution, and automatically maintains multiple long-term recovery points.
