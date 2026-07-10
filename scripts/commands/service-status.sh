#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${COMMAND_DIR}/.." && pwd)"

source "${SCRIPT_ROOT}/common.sh"

REPORT_DIRECTORY="${REPORT_ROOT}/service"
REPORT_FILE="${REPORT_DIRECTORY}/service-$(file_timestamp).txt"
LATEST_LINK="${REPORT_DIRECTORY}/latest.txt"

ensure_directory "${REPORT_DIRECTORY}"
ensure_directory "${LOG_ROOT}"

section() {
    local title="$1"

    printf '\n'
    printf '========================================\n'
    printf '%s\n' "${title}"
    printf '========================================\n\n'
}

systemd_unit_status() {
    local unit="$1"
    local label="$2"
    local active
    local enabled

    if ! command_exists systemctl; then
        printf '%-20s %-12s %-12s\n' \
            "${label}" \
            "unavailable" \
            "unavailable"
        return
    fi

    active="$(
        systemctl is-active "${unit}" 2>/dev/null ||
        true
    )"

    enabled="$(
        systemctl is-enabled "${unit}" 2>/dev/null ||
        true
    )"

    [[ -n "${active}" ]] || active="unknown"
    [[ -n "${enabled}" ]] || enabled="unknown"

    printf '%-20s %-12s %-12s\n' \
        "${label}" \
        "${active}" \
        "${enabled}"
}

print_core_services() {
    section "Core systemd Services"

    printf '%-20s %-12s %-12s\n' \
        "SERVICE" \
        "ACTIVE" \
        "ENABLED"

    printf '%-20s %-12s %-12s\n' \
        "--------------------" \
        "------------" \
        "------------"

    systemd_unit_status "docker.service" "Docker"

    if systemctl list-unit-files ssh.service \
        >/dev/null 2>&1; then
        systemd_unit_status "ssh.service" "SSH"
    else
        systemd_unit_status "sshd.service" "SSH"
    fi

    if systemctl list-unit-files cron.service \
        >/dev/null 2>&1; then
        systemd_unit_status "cron.service" "Cron"
    else
        systemd_unit_status "crond.service" "Cron"
    fi
}

print_failed_units() {
    section "Failed systemd Units"

    if ! command_exists systemctl; then
        printf 'systemctl: unavailable\n'
        return
    fi

    local failed

    failed="$(
        systemctl \
            --failed \
            --no-legend \
            --plain \
            2>/dev/null ||
        true
    )"

    if [[ -z "${failed}" ]]; then
        printf 'No failed units.\n'
    else
        printf '%s\n' "${failed}"
    fi
}

docker_available() {
    command_exists docker &&
    docker info >/dev/null 2>&1
}

print_docker_summary() {
    section "Docker Container Summary"

    if ! command_exists docker; then
        printf 'Docker CLI: not-installed\n'
        return
    fi

    if ! docker info >/dev/null 2>&1; then
        printf 'Docker daemon: unavailable or permission denied\n'
        return
    fi

    local total
    local running
    local stopped
    local unhealthy

    total="$(
        docker ps -aq 2>/dev/null |
        wc -l |
        tr -d ' '
    )"

    running="$(
        docker ps -q 2>/dev/null |
        wc -l |
        tr -d ' '
    )"

    stopped="$((total - running))"

    unhealthy="$(
        docker ps \
            --filter health=unhealthy \
            -q \
            2>/dev/null |
        wc -l |
        tr -d ' '
    )"

    printf 'Total containers: %s\n' "${total}"
    printf 'Running: %s\n' "${running}"
    printf 'Stopped: %s\n' "${stopped}"
    printf 'Unhealthy: %s\n' "${unhealthy}"
}

print_containers() {
    section "All Containers"

    if ! docker_available; then
        printf 'Docker unavailable.\n'
        return
    fi

    docker ps -a \
        --format \
        'table {{.Names}}\t{{.Status}}\t{{.Image}}' \
        2>&1 ||
    true
}

container_matches() {
    local pattern="$1"

    docker ps -a \
        --format '{{.Names}}|{{.Status}}|{{.Image}}' \
        2>/dev/null |
    grep -Ei "${pattern}" ||
    true
}

print_application_status() {
    section "Application Services"

    if ! docker_available; then
        printf 'Docker unavailable.\n'
        return
    fi

    local applications=(
        "Immich|immich"
        "Nextcloud|nextcloud"
        "Plex|plex"
        "Homepage|homepage"
        "Portainer|portainer"
    )

    local item
    local name
    local pattern
    local matches

    for item in "${applications[@]}"; do
        name="${item%%|*}"
        pattern="${item#*|}"

        matches="$(container_matches "${pattern}")"

        printf '\n[%s]\n' "${name}"

        if [[ -z "${matches}" ]]; then
            printf 'Status: not-found\n'
        else
            printf '%s\n' "${matches}"
        fi
    done
}

print_compose_projects() {
    section "Docker Compose Projects"

    if ! docker_available; then
        printf 'Docker unavailable.\n'
        return
    fi

    if docker compose version >/dev/null 2>&1; then
        docker compose ls 2>&1 || true
    else
        printf 'Docker Compose plugin: unavailable\n'
    fi
}

print_health_warnings() {
    section "Health Warnings"

    if ! docker_available; then
        printf 'Docker unavailable.\n'
        return
    fi

    local warnings

    warnings="$(
        docker ps -a \
            --format '{{.Names}}|{{.Status}}' \
            2>/dev/null |
        awk -F'|' '
            $2 ~ /unhealthy/ ||
            $2 ~ /^Exited/ ||
            $2 ~ /^Dead/ ||
            $2 ~ /^Restarting/ {
                print
            }
        '
    )"

    if [[ -z "${warnings}" ]]; then
        printf 'No container health warnings.\n'
    else
        printf '%s\n' "${warnings}"
    fi
}

main() {
    {
        printf '# AI Home Datacenter Service Status\n\n'
        printf 'Generated: %s\n' "$(date --iso-8601=seconds)"
        printf 'Hostname: %s\n' "$(hostname)"

        print_core_services
        print_failed_units
        print_docker_summary
        print_application_status
        print_health_warnings
        print_containers
        print_compose_projects
    } | tee "${REPORT_FILE}"

    write_latest_link \
        "${REPORT_FILE}" \
        "${LATEST_LINK}"

    log_info \
        "Service 상태 리포트 생성 완료: ${REPORT_FILE}"
}

main "$@"
