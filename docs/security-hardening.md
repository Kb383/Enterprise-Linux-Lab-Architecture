# Security Hardening

This document summarizes the baseline security hardening used for the VoidWar infrastructure environment.

The goal of this setup is to reduce unnecessary exposure on a public Linux server while keeping required administration and game server services available.

## Overview

The server uses a layered security approach:

- SSH hardening for remote administration
- UFW firewall rules for inbound traffic control
- Fail2Ban for SSH brute-force protection
- Minimal public service exposure
- Non-root administrative access

The example configuration files are stored under:

```text
config/
  ssh/
    sshd_config.example

  ufw/
    ufw-rules.example

  fail2ban/
    custom_hardening.local.example
```

These files are sanitized examples. They do not expose production ports, private IP addresses, credentials, or machine-specific details.

## SSH Hardening

SSH is used for remote server administration.

The SSH configuration disables direct root login and password-based authentication. Administrative access uses SSH key authentication through a non-root user account.

Key SSH hardening decisions include:

- Root login disabled
- Password authentication disabled
- Keyboard-interactive authentication disabled
- SSH key authentication used for remote access
- X11 forwarding disabled in the public example
- SFTP subsystem enabled for controlled file transfer
- Default cloud image users can be denied after creating a dedicated admin account

Disabling password login significantly reduces the risk of successful brute-force attacks because attackers cannot authenticate using guessed passwords.

The sanitized example is located at:

```text
config/ssh/sshd_config.example
```

## UFW Firewall Rules

UFW is used to control inbound network access.

The firewall uses a default-deny inbound policy and only allows required services.

Baseline firewall posture:

- Deny incoming traffic by default
- Allow outgoing traffic by default
- Deny routed traffic by default
- Enable low-volume logging
- Limit SSH connection attempts
- Allow required Minecraft server traffic

The public example uses standard placeholder ports instead of production-specific ports.

The sanitized example is located at:

```text
config/ufw/ufw-rules.example
```

## Fail2Ban SSH Protection

Fail2Ban is used to monitor SSH authentication activity and temporarily ban repeated failed login attempts.

The active jail configuration is managed through a custom drop-in file under:

```text
/etc/fail2ban/jail.d/
```

The example configuration enables the `sshd` jail and applies stricter default thresholds:

- 1 hour ban time
- 15 minute detection window
- 3 maximum retries
- Loopback addresses whitelisted
- SSH authentication events read from the systemd journal
- Production-specific SSH port omitted from the public example

This provides an additional layer of protection against repeated SSH login attempts.

The sanitized example is located at:

```text
config/fail2ban/custom_hardening.local.example
```

## Service Exposure

Only required services should be reachable from the public internet.

The intended exposure model is:

- SSH for administration
- Minecraft server traffic for players
- Future HTTP/HTTPS only if nginx or web services are deployed

Unused services should remain closed at the firewall level.

This reduces the attack surface of the server and makes the exposed services easier to monitor and manage.

## Production Port Sanitization

Production-specific ports are intentionally not published in this repository.

The example configuration files use generic or standard ports where appropriate. This keeps the repository useful for documentation and review without exposing exact operational details.

## Operational Notes

Security changes should be tested carefully before applying them to a remote server.

SSH changes are especially risky because an invalid configuration or overly restrictive rule can lock out remote administration access.

Recommended safety practices:

- Keep an existing SSH session open while testing SSH changes
- Validate SSH configuration before restarting the service
- Confirm firewall rules before enabling or reloading UFW
- Restart and check Fail2Ban after modifying jail files
- Review logs after security changes

Useful validation commands include:

```bash
sudo sshd -T
sudo systemctl status ssh --no-pager
sudo ufw status verbose
sudo systemctl status fail2ban --no-pager
sudo fail2ban-client status
sudo fail2ban-client status sshd
```

## Summary

The VoidWar server uses basic but important Linux security controls:

- Hardened SSH access
- Key-based authentication
- Disabled root/password login
- Default-deny firewall posture
- Limited inbound services
- Fail2Ban SSH brute-force protection
- Sanitized public documentation

This setup demonstrates practical Linux server hardening for a public-facing infrastructure environment.
