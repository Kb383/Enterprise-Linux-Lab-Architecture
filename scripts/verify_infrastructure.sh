#!/usr/bin/env bash

# Verify the health and security posture of the VoidWar infrastructure.
#
# This script checks:
#   - Docker daemon availability
#   - Required container status
#   - Nginx configuration validity
#   - Internal service health
#   - Prometheus scrape targets
#   - Loopback-only monitoring listeners
#   - Public HTTP/HTTPS behavior
#   - TLS certificate coverage and expiration
#   - Certbot renewal automation
#   - Fail2Ban SSH jail status
#
# Exit codes:
#   0 = all required checks passed
#   1 = one or more infrastructure checks failed
#   2 = the script could not run because a dependency was missing

set -uo pipefail

readonly BASE_DOMAIN="voidwar.net"
readonly WWW_DOMAIN="www.voidwar.net"
readonly GRAFANA_DOMAIN="grafana.voidwar.net"

readonly CERT_PATH="/etc/letsencrypt/live/${BASE_DOMAIN}/fullchain.pem"
readonly CERTBOT_TIMER="certbot.timer"
readonly CERTBOT_DEPLOY_HOOK="/etc/letsencrypt/renewal-hooks/deploy/reload-voidwar-nginx.sh"
readonly FAIL2BAN_JAIL="sshd"

readonly CERT_WARNING_DAYS=30
readonly CERT_FAILURE_DAYS=7

readonly -a REQUIRED_CONTAINERS=(
    "voidwar-nginx"
    "voidwar-node-exporter"
    "voidwar-prometheus"
    "voidwar-grafana"
)

readonly -a REQUIRED_COMMANDS=(
    "awk"
    "curl"
    "date"
    "docker"
    "fail2ban-client"
    "grep"
    "mktemp"
    "openssl"
    "python3"
    "ss"
    "systemctl"
)

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

if [[ -t 1 ]]; then
    readonly GREEN=$'\033[0;32m'
    readonly YELLOW=$'\033[0;33m'
    readonly RED=$'\033[0;31m'
    readonly BLUE=$'\033[0;34m'
    readonly BOLD=$'\033[1m'
    readonly RESET=$'\033[0m'
else
    readonly GREEN=""
    readonly YELLOW=""
    readonly RED=""
    readonly BLUE=""
    readonly BOLD=""
    readonly RESET=""
fi

TMP_DIR=""

if (( EUID == 0 )); then
    SUDO=()
else
    SUDO=(sudo)
fi

section() {
    printf '\n%s%s== %s ==%s\n' "$BLUE" "$BOLD" "$1" "$RESET"
}

ok() {
    printf '%s[ OK ]%s %s\n' "$GREEN" "$RESET" "$1"
    ((PASS_COUNT += 1))
}

warn() {
    printf '%s[WARN]%s %s\n' "$YELLOW" "$RESET" "$1"
    ((WARN_COUNT += 1))
}

fail() {
    printf '%s[FAIL]%s %s\n' "$RED" "$RESET" "$1"
    ((FAIL_COUNT += 1))
}

cleanup() {
    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR"
    fi
}

trap cleanup EXIT

require_commands() {
    local command_name
    local missing=0

    for command_name in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            printf '%s[FAIL]%s Required command not found: %s\n' \
                "$RED" "$RESET" "$command_name"
            missing=1
        fi
    done

    if (( EUID != 0 )) && ! command -v sudo >/dev/null 2>&1; then
        printf '%s[FAIL]%s This script requires root access or sudo.\n' \
            "$RED" "$RESET"
        missing=1
    fi

    if (( missing != 0 )); then
        exit 2
    fi
}

initialize_privileges() {
    if (( EUID != 0 )); then
        if ! sudo -v; then
            printf '%s[FAIL]%s Unable to obtain sudo privileges.\n' \
                "$RED" "$RESET"
            exit 2
        fi
    fi
}

check_docker_daemon() {
    section "Docker"

    if "${SUDO[@]}" docker info >/dev/null 2>&1; then
        ok "Docker daemon is available"
    else
        fail "Docker daemon is unavailable"
        return
    fi

    local container
    local running_state

    for container in "${REQUIRED_CONTAINERS[@]}"; do
        running_state="$(
            "${SUDO[@]}" docker inspect \
                --format '{{.State.Running}}' \
                "$container" 2>/dev/null || true
        )"

        if [[ "$running_state" == "true" ]]; then
            ok "Container is running: $container"
        elif [[ -z "$running_state" ]]; then
            fail "Container does not exist: $container"
        else
            fail "Container is not running: $container"
        fi
    done
}

check_nginx_configuration() {
    section "Nginx"

    local output

    if output="$(
        "${SUDO[@]}" docker exec voidwar-nginx nginx -t 2>&1
    )"; then
        ok "Nginx configuration test passed"
    else
        fail "Nginx configuration test failed"
        printf '%s\n' "$output" | sed 's/^/       /'
    fi
}

check_grafana_health() {
    section "Local Service Health"

    local response

    if ! response="$(
        curl -fsS \
            --connect-timeout 5 \
            --max-time 10 \
            http://127.0.0.1:3000/api/health
    )"; then
        fail "Grafana health endpoint is unavailable"
    elif grep -Eq \
        '"database"[[:space:]]*:[[:space:]]*"ok"' \
        <<<"$response"; then
        ok "Grafana database health is OK"
    else
        fail "Grafana returned an unhealthy database status"
    fi
}

check_prometheus_health() {
    local response

    if ! response="$(
        curl -fsS \
            --connect-timeout 5 \
            --max-time 10 \
            http://127.0.0.1:9090/-/healthy
    )"; then
        fail "Prometheus health endpoint is unavailable"
    elif grep -q "Prometheus Server is Healthy" <<<"$response"; then
        ok "Prometheus reports healthy"
    else
        fail "Prometheus returned an unexpected health response"
    fi
}

check_node_exporter_health() {
    local metrics_file="${TMP_DIR}/node-exporter-metrics.txt"

    if ! curl -fsS \
        --connect-timeout 5 \
        --max-time 20 \
        --output "$metrics_file" \
        http://127.0.0.1:9100/metrics; then
        fail "Node Exporter metrics endpoint is unavailable"
    elif grep -q '^node_exporter_build_info' "$metrics_file"; then
        ok "Node Exporter is returning host metrics"
    else
        fail "Node Exporter response did not contain expected metrics"
    fi
}

check_prometheus_targets() {
    section "Prometheus Targets"

    local targets_file="${TMP_DIR}/prometheus-targets.json"
    local parser_output

    if ! curl -fsS \
        --connect-timeout 5 \
        --max-time 10 \
        --output "$targets_file" \
        http://127.0.0.1:9090/api/v1/targets; then
        fail "Unable to retrieve Prometheus target status"
        return
    fi

    if parser_output="$(
        python3 - "$targets_file" <<'PY'
import json
import sys

path = sys.argv[1]
expected_jobs = {"prometheus", "node-exporter"}

try:
    with open(path, "r", encoding="utf-8") as handle:
        payload = json.load(handle)
except (OSError, json.JSONDecodeError) as exc:
    print(f"Unable to parse target response: {exc}")
    sys.exit(1)

if payload.get("status") != "success":
    print("Prometheus API did not return a success status")
    sys.exit(1)

targets = payload.get("data", {}).get("activeTargets", [])
targets_by_job = {}

for target in targets:
    labels = target.get("labels", {})
    job = labels.get("job")

    if job:
        targets_by_job.setdefault(job, []).append(target)

problems = []

for job in sorted(expected_jobs):
    job_targets = targets_by_job.get(job, [])

    if not job_targets:
        problems.append(f"{job}: missing")
        continue

    healthy = any(
        target.get("health") == "up"
        and not target.get("lastError")
        for target in job_targets
    )

    if not healthy:
        errors = [
            target.get("lastError") or target.get("health", "unknown")
            for target in job_targets
        ]
        problems.append(f"{job}: unhealthy ({'; '.join(errors)})")

if problems:
    print(", ".join(problems))
    sys.exit(1)

print("prometheus=up, node-exporter=up")
PY
    )"; then
        ok "Prometheus targets are healthy: $parser_output"
    else
        fail "Prometheus target validation failed: $parser_output"
    fi
}

check_loopback_listener() {
    local service_name="$1"
    local port="$2"
    local listeners
    local address
    local invalid_addresses=()

    listeners="$(
        ss -H -lnt |
            awk -v suffix=":${port}" '$4 ~ suffix "$" {print $4}'
    )"

    if [[ -z "$listeners" ]]; then
        fail "$service_name is not listening on port $port"
        return
    fi

    while IFS= read -r address; do
        case "$address" in
            "127.0.0.1:${port}"|"[::1]:${port}")
                ;;
            *)
                invalid_addresses+=("$address")
                ;;
        esac
    done <<<"$listeners"

    if (( ${#invalid_addresses[@]} == 0 )); then
        ok "$service_name is restricted to loopback on port $port"
    else
        fail "$service_name has a non-loopback listener: ${invalid_addresses[*]}"
    fi
}

check_listening_addresses() {
    section "Listening Addresses"

    check_loopback_listener "Grafana" "3000"
    check_loopback_listener "Prometheus" "9090"
    check_loopback_listener "Node Exporter" "9100"
}

get_http_headers() {
    local url="$1"

    curl -sS \
        --connect-timeout 5 \
        --max-time 15 \
        --head \
        "$url"
}

check_redirect() {
    local url="$1"
    local expected_location="$2"
    local headers
    local status_code
    local location

    if ! headers="$(get_http_headers "$url")"; then
        fail "Unable to reach $url"
        return
    fi

    status_code="$(
        awk '
            toupper($1) ~ /^HTTP\// { code=$2 }
            END { print code }
        ' <<<"$headers"
    )"

    location="$(
        awk '
            tolower($1) == "location:" {
                value=$2
                sub(/\r$/, "", value)
                location=value
            }
            END { print location }
        ' <<<"$headers"
    )"

    if [[ "$status_code" != "301" && "$status_code" != "302" ]]; then
        fail "$url returned HTTP $status_code instead of a redirect"
    elif [[ "$location" != "$expected_location" ]]; then
        fail "$url redirected to '$location' instead of '$expected_location'"
    else
        ok "$url redirects to $expected_location"
    fi
}

check_http_status() {
    local url="$1"
    shift
    local expected_codes=("$@")
    local status_code
    local expected

    if ! status_code="$(
        curl -sS \
            --connect-timeout 5 \
            --max-time 15 \
            --output /dev/null \
            --write-out '%{http_code}' \
            "$url"
    )"; then
        fail "Unable to reach $url"
        return
    fi

    for expected in "${expected_codes[@]}"; do
        if [[ "$status_code" == "$expected" ]]; then
            ok "$url returned HTTP $status_code"
            return
        fi
    done

    fail "$url returned unexpected HTTP status $status_code"
}

check_public_endpoints() {
    section "Public Endpoints"

    check_redirect \
        "http://${BASE_DOMAIN}" \
        "https://${BASE_DOMAIN}/"

    check_http_status \
        "https://${BASE_DOMAIN}" \
        "200"

    check_redirect \
        "http://${WWW_DOMAIN}" \
        "https://${BASE_DOMAIN}/"

    check_redirect \
        "https://${WWW_DOMAIN}" \
        "https://${BASE_DOMAIN}/"

    check_redirect \
        "http://${GRAFANA_DOMAIN}" \
        "https://${GRAFANA_DOMAIN}/"

    check_http_status \
        "https://${GRAFANA_DOMAIN}" \
        "302"
}

check_tls_certificate() {
    section "TLS Certificate"

    local expiry_text
    local expiry_epoch
    local current_epoch
    local remaining_seconds
    local remaining_days
    local san_output
    local domain
    local missing_sans=()

    if ! "${SUDO[@]}" test -r "$CERT_PATH"; then
        fail "TLS certificate is not readable: $CERT_PATH"
        return
    fi

    if ! expiry_text="$(
        "${SUDO[@]}" openssl x509 \
            -in "$CERT_PATH" \
            -noout \
            -enddate 2>/dev/null |
            cut -d= -f2-
    )"; then
        fail "Unable to read TLS certificate expiration"
        return
    fi

    if ! expiry_epoch="$(date -d "$expiry_text" +%s 2>/dev/null)"; then
        fail "Unable to parse TLS certificate expiration: $expiry_text"
        return
    fi

    current_epoch="$(date +%s)"
    remaining_seconds=$((expiry_epoch - current_epoch))
    remaining_days=$((remaining_seconds / 86400))

    if (( remaining_seconds <= 0 )); then
        fail "TLS certificate has expired"
    elif (( remaining_days < CERT_FAILURE_DAYS )); then
        fail "TLS certificate expires in $remaining_days days"
    elif (( remaining_days < CERT_WARNING_DAYS )); then
        warn "TLS certificate expires in $remaining_days days"
    else
        ok "TLS certificate is valid for approximately $remaining_days more days"
    fi

    if ! san_output="$(
        "${SUDO[@]}" openssl x509 \
            -in "$CERT_PATH" \
            -noout \
            -ext subjectAltName 2>/dev/null
    )"; then
        fail "Unable to inspect TLS certificate subject alternative names"
        return
    fi

    for domain in "$BASE_DOMAIN" "$WWW_DOMAIN" "$GRAFANA_DOMAIN"; do
        if ! grep -q "DNS:${domain}" <<<"$san_output"; then
            missing_sans+=("$domain")
        fi
    done

    if (( ${#missing_sans[@]} == 0 )); then
        ok "TLS certificate covers all required hostnames"
    else
        fail "TLS certificate is missing hostnames: ${missing_sans[*]}"
    fi
}

check_certbot_automation() {
    section "Certificate Renewal Automation"

    if systemctl is-enabled --quiet "$CERTBOT_TIMER"; then
        ok "$CERTBOT_TIMER is enabled"
    else
        fail "$CERTBOT_TIMER is not enabled"
    fi

    if systemctl is-active --quiet "$CERTBOT_TIMER"; then
        ok "$CERTBOT_TIMER is active"
    else
        fail "$CERTBOT_TIMER is not active"
    fi

    if "${SUDO[@]}" test -x "$CERTBOT_DEPLOY_HOOK"; then
        ok "Certbot deploy hook exists and is executable"
    else
        fail "Certbot deploy hook is missing or not executable"
    fi
}

check_fail2ban() {
    section "Fail2Ban"

    local status_file="${TMP_DIR}/fail2ban-status.txt"
    local currently_banned

    if ! "${SUDO[@]}" fail2ban-client status "$FAIL2BAN_JAIL" \
        >"$status_file" 2>&1; then
        fail "Fail2Ban jail is unavailable: $FAIL2BAN_JAIL"
        return
    fi

    currently_banned="$(
        awk -F: '
            /Currently banned/ {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
                print $2
            }
        ' "$status_file"
    )"

    if [[ -n "$currently_banned" ]]; then
        ok "Fail2Ban jail '$FAIL2BAN_JAIL' is active ($currently_banned currently banned)"
    else
        ok "Fail2Ban jail '$FAIL2BAN_JAIL' is active"
    fi
}

print_summary() {
    printf '\n%s%s== Verification Summary ==%s\n' \
        "$BLUE" "$BOLD" "$RESET"

    printf 'Passed:   %d\n' "$PASS_COUNT"
    printf 'Warnings: %d\n' "$WARN_COUNT"
    printf 'Failed:   %d\n' "$FAIL_COUNT"

    if (( FAIL_COUNT > 0 )); then
        printf '\n%sInfrastructure verification failed.%s\n' \
            "$RED" "$RESET"
        return 1
    fi

    if (( WARN_COUNT > 0 )); then
        printf '\n%sInfrastructure verification completed with warnings.%s\n' \
            "$YELLOW" "$RESET"
    else
        printf '\n%sInfrastructure verification completed successfully.%s\n' \
            "$GREEN" "$RESET"
    fi

    return 0
}

main() {
    require_commands
    initialize_privileges

    TMP_DIR="$(mktemp -d)"

    printf '%s%sVoidWar Infrastructure Verification%s\n' \
        "$BOLD" "$BLUE" "$RESET"
    printf 'Host: %s\n' "$(hostname)"
    printf 'Time: %s\n' "$(date --iso-8601=seconds)"

    check_docker_daemon
    check_nginx_configuration

    check_grafana_health
    check_prometheus_health
    check_node_exporter_health

    check_prometheus_targets
    check_listening_addresses
    check_public_endpoints
    check_tls_certificate
    check_certbot_automation
    check_fail2ban

    print_summary
}

main "$@"
