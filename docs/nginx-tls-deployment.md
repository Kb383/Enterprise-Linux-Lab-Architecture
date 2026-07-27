# VoidWar Nginx and TLS Deployment

This document covers deployment, validation, operation, and troubleshooting for the VoidWar Nginx reverse proxy and TLS configuration.

For the complete infrastructure design and traffic flow, see [`architecture.md`](architecture.md).

## Purpose

Nginx provides the public web entry point for the VoidWar infrastructure.

It is responsible for:

- Listening publicly on ports 80 and 443
- Redirecting HTTP traffic to HTTPS
- Serving the static `voidwar.net` landing page
- Redirecting `www.voidwar.net` to the canonical non-`www` hostname
- Terminating TLS
- Serving ACME HTTP challenge files
- Reverse-proxying `grafana.voidwar.net` to Grafana
- Forwarding the original request context to Grafana

The live deployment directory is:

```text
/opt/voidwar/nginx
```

The sanitized repository configuration is stored under:

```text
docker/nginx
```

## Repository Layout

```text
docker/nginx/
├── .gitignore
├── compose.yaml
├── conf/
│   └── default.conf.example
└── html/
    └── index.html
```

The repository does not contain:

- Private keys
- Live certificates
- ACME challenge runtime files
- Certbot account data
- Logs
- Other generated runtime data

## Container Image

The Nginx service currently uses:

```text
nginx:1.29-alpine
```

The image version is pinned to the Nginx 1.29 Alpine release series instead of using the floating `latest` tag.

Image upgrades should be tested before changing the configured tag.

## Docker Compose Configuration

The Nginx stack is defined in:

```text
docker/nginx/compose.yaml
```

The deployed container name is:

```text
voidwar-nginx
```

The service uses:

```yaml
restart: unless-stopped
network_mode: host
```

Host networking allows Nginx to:

- Bind directly to host ports 80 and 443
- Reach Grafana at `127.0.0.1:3000`
- Avoid exposing Grafana through a public Docker port mapping

Because host networking is used, no `ports:` section is required.

## Mounted Files and Directories

The Compose file mounts:

```yaml
volumes:
  - ./html:/usr/share/nginx/html:ro
  - ./conf/default.conf:/etc/nginx/conf.d/default.conf:ro
  - ./certbot:/var/www/certbot:ro
  - /etc/letsencrypt:/etc/letsencrypt:ro
```

These mounts provide:

| Host path | Container path | Purpose |
|---|---|---|
| `./html` | `/usr/share/nginx/html` | Static website content |
| `./conf/default.conf` | `/etc/nginx/conf.d/default.conf` | Nginx virtual-host configuration |
| `./certbot` | `/var/www/certbot` | ACME HTTP challenge files |
| `/etc/letsencrypt` | `/etc/letsencrypt` | TLS certificates and private keys |

All four mounts are read-only inside the container.

Nginx can read the required files but cannot modify the host copies.

## Preparing the Configuration File

The repository tracks the sanitized Nginx configuration as:

```text
conf/default.conf.example
```

The Compose file expects:

```text
conf/default.conf
```

Before deployment, create the local configuration copy:

```bash
cp conf/default.conf.example conf/default.conf
```

Review the copied file and update hostnames, certificate paths, or upstream addresses if deploying it in another environment.

The local `conf/default.conf` file should remain outside Git.

## Public Hostnames

The production configuration handles:

```text
voidwar.net
www.voidwar.net
grafana.voidwar.net
```

The verified production certificate includes all three names as subject alternative names.

## HTTP Behavior

### Primary Domain

Requests to:

```text
http://voidwar.net
```

are redirected to:

```text
https://voidwar.net
```

The original request URI is preserved.

### WWW Domain

Requests to either:

```text
http://www.voidwar.net
https://www.voidwar.net
```

are redirected to the canonical hostname:

```text
https://voidwar.net
```

The original request URI is preserved.

### Grafana Domain

Requests to:

```text
http://grafana.voidwar.net
```

are redirected to:

```text
https://grafana.voidwar.net
```

## Static Website

The primary HTTPS virtual host serves the static website from:

```text
/usr/share/nginx/html
```

The repository includes:

```text
html/index.html
```

The current page confirms that the Nginx container is operating successfully.

The location block uses:

```nginx
try_files $uri $uri/ =404;
```

Nginx serves an existing file or directory and otherwise returns HTTP 404.

## TLS Certificate Paths

The Nginx configuration references:

```text
/etc/letsencrypt/live/voidwar.net/fullchain.pem
/etc/letsencrypt/live/voidwar.net/privkey.pem
```

The certificate contains:

```text
voidwar.net
www.voidwar.net
grafana.voidwar.net
```

The repository contains only references to these paths.

It does not contain the certificate files or private key.

## Certificate Requirement

The referenced certificate files must exist on the host before Nginx starts with the full HTTPS configuration.

If the files do not exist, Nginx configuration validation and container startup will fail.

Certificate issuance can be bootstrapped using an ACME client and either:

- A temporary HTTP-only Nginx configuration
- An ACME standalone listener
- Another controlled certificate-issuance process

The exact certificate issuance and renewal scheduler used by the production host is not defined by this repository and should be documented separately if automated.

After certificate issuance, confirm that the files exist:

```bash
sudo ls -l /etc/letsencrypt/live/voidwar.net/
```

Never display or copy the contents of:

```text
privkey.pem
```

## Certificate Inspection

Certificate metadata can be inspected safely with:

```bash
sudo openssl x509 \
  -in /etc/letsencrypt/live/voidwar.net/fullchain.pem \
  -noout \
  -subject \
  -issuer \
  -dates \
  -ext subjectAltName
```

This displays:

- Certificate subject
- Issuing certificate authority
- Validity period
- Subject alternative names

It does not display the private key.

## ACME HTTP Challenge

The HTTP virtual hosts expose:

```text
/.well-known/acme-challenge/
```

Challenge files are served from:

```text
/var/www/certbot
```

The corresponding host directory is:

```text
./certbot
```

Create it before deployment:

```bash
mkdir -p certbot
```

ACME challenge files are generated runtime content and are excluded from Git.

## TLS Protocols

The primary and `www` HTTPS virtual hosts explicitly allow:

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
```

This disables obsolete TLS protocol versions for those virtual hosts.

TLS configuration should be revalidated after Nginx image upgrades or material configuration changes.

## Grafana Reverse Proxy

Requests to:

```text
https://grafana.voidwar.net
```

are forwarded to:

```text
http://127.0.0.1:3000
```

The relevant directive is:

```nginx
proxy_pass http://127.0.0.1:3000;
```

Grafana must therefore:

- Be running on the same host
- Listen on `127.0.0.1`
- Use port 3000

Grafana does not need to listen on a public interface.

## Forwarded Headers

Nginx forwards the original request context through:

```nginx
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
```

These headers provide Grafana with:

- The original hostname
- The connecting client address
- The forwarded client-address chain
- The original request protocol

The Grafana root URL is configured separately as:

```text
https://grafana.voidwar.net
```

## HTTP Upgrade Support

The Grafana proxy uses HTTP/1.1 and forwards upgrade headers:

```nginx
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
```

This supports Grafana functionality that may require upgraded connections.

## Fresh Deployment

Move into the Nginx directory:

```bash
cd docker/nginx
```

Create the local Nginx configuration:

```bash
cp conf/default.conf.example conf/default.conf
```

Create the ACME challenge directory:

```bash
mkdir -p certbot
```

Confirm the required certificate files already exist:

```bash
sudo test -r /etc/letsencrypt/live/voidwar.net/fullchain.pem
sudo test -r /etc/letsencrypt/live/voidwar.net/privkey.pem
```

Validate the Compose configuration:

```bash
docker compose config
```

Start the container:

```bash
docker compose up -d
```

The repository copy should not be started on the production host while the live container is already running from `/opt/voidwar/nginx`.

Doing so would create a container-name conflict and compete for ports 80 and 443.

## Container Status

Check the Compose service:

```bash
docker compose ps
```

Or inspect the named container:

```bash
docker ps --filter name=voidwar-nginx
```

The expected container name is:

```text
voidwar-nginx
```

## Validate the Compose File

Render and validate the Compose configuration:

```bash
docker compose config
```

This detects Compose syntax and path interpolation issues.

It does not fully validate Nginx configuration syntax.

## Validate Nginx Configuration

Validate the running container configuration:

```bash
docker exec voidwar-nginx nginx -t
```

Expected output includes:

```text
syntax is ok
test is successful
```

Configuration changes should not be applied unless this test passes.

## Verify Listening Ports

Check ports 80 and 443:

```bash
sudo ss -lntp | grep -E ':(80|443)\b'
```

Nginx should listen publicly on both ports.

Because host networking is used, the listener appears directly on the host rather than through a Docker port-forwarding process.

## Verify Public Endpoints

Check the primary HTTP redirect:

```bash
curl -I http://voidwar.net
```

Expected destination:

```text
https://voidwar.net/
```

Check the primary HTTPS site:

```bash
curl -I https://voidwar.net
```

Expected status:

```text
200 OK
```

Check the `www` redirects:

```bash
curl -I http://www.voidwar.net
curl -I https://www.voidwar.net
```

Expected destination:

```text
https://voidwar.net/
```

Check the Grafana HTTP redirect:

```bash
curl -I http://grafana.voidwar.net
```

Expected destination:

```text
https://grafana.voidwar.net/
```

Check the Grafana HTTPS endpoint:

```bash
curl -I https://grafana.voidwar.net
```

An unauthenticated request normally returns a redirect to:

```text
/login
```

## Applying Configuration Changes

Edit the host-side Nginx configuration, then validate it inside the running container:

```bash
docker exec voidwar-nginx nginx -t
```

If validation succeeds, reload Nginx:

```bash
docker exec voidwar-nginx nginx -s reload
```

Alternatively, recreate the container:

```bash
docker compose up -d nginx
```

A reload is generally preferable for a configuration-only change because it avoids unnecessarily replacing the container.

## Automated Certificate Renewal

Let's Encrypt certificate renewal is fully automated through the host's Certbot systemd timer.

The timer runs Certbot twice daily and is enabled by default:

```bash
systemctl status certbot.timer
```

The active timer triggers:

```text
certbot.service
```

Certificate renewal uses the webroot method with:

```text
/opt/voidwar/nginx/certbot
```

as the ACME challenge directory.

The managed certificate currently covers:

```text
voidwar.net
www.voidwar.net
grafana.voidwar.net
```

Renewal can be safely tested without modifying the live certificate:

```bash
sudo certbot renew --dry-run
```

A successful dry run confirms that the current certificate can be renewed using the configured challenge method.

## Automatic Nginx Reload

After a successful certificate renewal, Certbot executes a deploy hook that validates and reloads the running Nginx container.

The deploy hook is located at:

```text
/etc/letsencrypt/renewal-hooks/deploy/reload-voidwar-nginx.sh
```

The hook executes:

```bash
/usr/bin/docker exec voidwar-nginx nginx -t
/usr/bin/docker exec voidwar-nginx nginx -s reload
```

The first command validates the Nginx configuration.

If validation succeeds, the second command performs a graceful reload so the renewed certificate is used immediately without restarting the container.

The deploy hook only runs after a successful certificate renewal.

## Renewal Verification

Check the Certbot timer:

```bash
systemctl list-timers --all | grep -i certbot
```

Inspect the managed certificate:

```bash
sudo certbot certificates
```

Perform a simulated renewal:

```bash
sudo certbot renew --dry-run
```

Inspect the deploy hook:

```bash
sudo sed -n '1,120p' \
  /etc/letsencrypt/renewal-hooks/deploy/reload-voidwar-nginx.sh
```

Verify the active certificate validity period:

```bash
sudo openssl x509 \
  -in /etc/letsencrypt/live/voidwar.net/fullchain.pem \
  -noout \
  -dates
```

## View Logs

View recent Nginx logs:

```bash
docker logs --tail 100 voidwar-nginx
```

Follow logs in real time:

```bash
docker logs -f voidwar-nginx
```

Container logs may include ordinary automated internet scanning and requests for unrelated application paths.

Unexpected requests do not by themselves indicate compromise.

## Troubleshooting Container Startup

If the container fails to start, inspect:

```bash
docker compose ps
docker logs --tail 100 voidwar-nginx
docker compose config
```

Common causes include:

- Missing certificate files
- An invalid Nginx directive
- A missing bind-mounted file
- Another process already using port 80 or 443
- Incorrect file permissions
- An invalid certificate path

Check port conflicts:

```bash
sudo ss -lntp | grep -E ':(80|443)\b'
```

## Troubleshooting TLS

Inspect the certificate:

```bash
sudo openssl x509 \
  -in /etc/letsencrypt/live/voidwar.net/fullchain.pem \
  -noout \
  -dates \
  -ext subjectAltName
```

Verify:

- The certificate has not expired
- The requested hostname is included
- Nginx can read the certificate files
- DNS resolves to the correct server
- Port 443 is reachable
- Nginx configuration passes validation

Check the public TLS endpoint:

```bash
curl -Iv https://voidwar.net
```

## Troubleshooting Grafana Proxying

First test Grafana locally:

```bash
curl -I http://127.0.0.1:3000
```

If Grafana does not respond locally, troubleshoot the Grafana container before Nginx.

If Grafana responds locally but fails publicly, inspect:

- The `grafana.voidwar.net` server block
- The `proxy_pass` target
- Nginx logs
- DNS
- TLS certificate coverage
- Grafana root URL settings
- Firewall rules

Validate Nginx:

```bash
docker exec voidwar-nginx nginx -t
```

Check both containers:

```bash
docker ps \
  --filter name=voidwar-nginx \
  --filter name=voidwar-grafana
```

## Troubleshooting ACME Challenges

Confirm the host challenge directory exists:

```bash
ls -ld certbot
```

Confirm the challenge path is present in the HTTP virtual host:

```text
/.well-known/acme-challenge/
```

A temporary test file can be created under the challenge directory and requested over HTTP.

Remove the test file immediately afterward.

Do not place private keys, account credentials, or unrelated files in the challenge directory.

## Runtime and Secret Exclusions

The Nginx-specific ignore rules exclude:

```text
certbot/
.well-known/
letsencrypt/
*.key
*.pem
*.crt
```

The following must never be committed:

- `/etc/letsencrypt`
- Private keys
- Live certificates
- Certbot account credentials
- ACME challenge runtime files
- Real environment files
- Logs containing sensitive information

The repository contains only sanitized configuration and static content.

## Operational Checklist

After deployment or maintenance, verify:

- [ ] The Nginx container is running
- [ ] `docker compose config` succeeds
- [ ] `nginx -t` succeeds
- [ ] Nginx listens on ports 80 and 443
- [ ] HTTP redirects to HTTPS
- [ ] `www.voidwar.net` redirects to `voidwar.net`
- [ ] `https://voidwar.net` returns the static site
- [ ] `https://grafana.voidwar.net` reaches Grafana
- [ ] The certificate covers all three hostnames
- [ ] The certificate is not near expiration
- [ ] Grafana remains bound to `127.0.0.1:3000`
- [ ] No certificate or private-key files are staged in Git
- [ ] No ACME challenge runtime files are staged in Git

## Summary

The VoidWar Nginx deployment provides the public HTTP and HTTPS entry point for the infrastructure.

Nginx serves the primary static site, redirects the `www` hostname, terminates TLS using Let's Encrypt certificate files mounted read-only from the host, serves ACME HTTP challenge files, and reverse-proxies the Grafana hostname to a loopback-only Grafana service.

The repository contains the sanitized Compose file, Nginx configuration example, and static site while excluding certificates, private keys, and runtime data.
