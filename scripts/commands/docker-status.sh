#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "${COMMAND_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/common.sh"

REPORT_DIRECTORY="${REPORT_ROOT}/docker"
REPORT_FILE="${REPORT_DIRECTORY}/docker-$(file_timestamp).txt"
LATEST_LINK="${REPORT_DIRECTORY}/latest.txt"

ensure_directory "${REPORT_DIRECTORY}"
ensure_directory "${LOG_ROOT}"

print_section() {
    local title="$1"

    printf '\n'
    printf '========================================\n'
    printf '%s\n' "${title}"
    printf '========================================\n\n'
}

docker_available() {
    command_exists docker
}

docker_daemon_available() {
    docker info >/dev/null 2>&1
}

print_service_status() {
    print_section "Docker Service"

    if command_exists systemctl; then
        printf 'Service status: '

        systemctl is-active docker 2>/dev/null || printf 'unknown\n'

        printf 'Enabled at boot: '

        systemctl is-enabled docker 2>/dev/null || printf 'unknown\n'
    else
        printf 'systemctl: unavailable\n'
    fi
}

print_versions() {
    print_section "Docker Version"

    if ! docker_available; then
        printf 'Docker CLI is not installed.\n'
        return
    fi

    docker version 2>&1 || true

    print_section "Docker Compose Version"

    if docker compose version >/dev/null 2>&1; then
        docker compose version 2>&1 || true
    else
        printf 'Docker Compose plugin is unavailable.\n'
    fi
}

print_containers() {
    print_section "All Containers"

    docker ps -a \
        --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' \
        2>&1 || true

    print_section "Running Containers"

    docker ps \
        --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' \
        2>&1 || true

    print_section "Container Health"

    docker ps -a \
        --format '{{.Names}}|{{.Status}}' \
        2>/dev/null |
    awk -F'|' '
        BEGIN {
            printf "%-32s %-15s %s\n", "NAME", "HEALTH", "STATUS"
        }
        {
            health = "not-configured"

            if ($2 ~ /\(healthy\)/) {
                health = "healthy"
            } else if ($2 ~ /\(unhealthy\)/) {
                health = "unhealthy"
            } else if ($2 ~ /\(health: starting\)/) {
                health = "starting"
            }

            printf "%-32s %-15s %s\n", $1, health, $2
        }
    ' || true
}

print_restart_policies() {
    print_section "Restart Policies"

    local container_ids

    container_ids="$(docker ps -aq 2>/dev/null || true)"

    if [[ -z "${container_ids}" ]]; then
        printf 'No containers found.\n'
        return
    fi

    printf '%-32s %-20s\n' "NAME" "RESTART POLICY"

    while IFS= read -r container_id; do
        [[ -n "${container_id}" ]] || continue

        docker inspect \
            --format '{{.Name}}|{{.HostConfig.RestartPolicy.Name}}' \
            "${container_id}" \
            2>/dev/null |
        sed 's#^/##' |
        awk -F'|' '{
            policy = $2

            if (policy == "") {
                policy = "no"
            }

            printf "%-32s %-20s\n", $1, policy
        }'
    done <<< "${container_ids}"
}

print_compose_projects() {
    print_section "Docker Compose Projects"

    if docker compose version >/dev/null 2>&1; then
        docker compose ls 2>&1 || true
    else
        printf 'Docker Compose plugin is unavailable.\n'
    fi
}

print_images() {
    print_section "Docker Images"

    docker images \
        --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}' \
        2>&1 || true
}

print_networks() {
    print_section "Docker Networks"

    docker network ls 2>&1 || true
}

print_volumes() {
    print_section "Docker Volumes"

    docker volume ls 2>&1 || true
}

print_disk_usage() {
    print_section "Docker Disk Usage"

    docker system df 2>&1 || true
}

main() {
    ensure_directory "${REPORT_DIRECTORY}"

    {
        printf '# AI Home Datacenter Docker Status\n\n'
        printf 'Generated: %s\n' "$(date --iso-8601=seconds)"
        printf 'Hostname: %s\n' "$(hostname)"

        print_service_status

        if ! docker_available; then
            print_section "Docker Error"
            printf 'Docker CLI is not installed or is not in PATH.\n'
            exit 0
        fi

        if ! docker_daemon_available; then
            print_versions
            print_section "Docker Error"
            printf 'Docker daemon is unavailable or permission was denied.\n'
            printf 'Current user: %s\n' "$(id -un)"
            printf 'Docker groups: %s\n' "$(id -Gn)"
            exit 0
        fi

        print_versions
        print_containers
        print_restart_policies
        print_compose_projects
        print_images
        print_networks
        print_volumes
        print_disk_usage
    } | tee "${REPORT_FILE}"

    write_latest_link "${REPORT_FILE}" "${LATEST_LINK}"

    log_info "Docker 상태 리포트 생성 완료: ${REPORT_FILE}"
}

main "$@"
