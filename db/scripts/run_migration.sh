#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATIONS_DIR="$(cd "${SCRIPT_DIR}/../migrations" && pwd)"

DB_USER="${LR_DB_USER:-lr}"
DB_PASS="${LR_DB_PASSWORD:-lr1234}"
DB_NAME="${LR_DB_NAME:-loadrunner_fms}"
DB_HOST="${LR_DB_HOST:-127.0.0.1}"
DB_PORT="${LR_DB_PORT:-5432}"
ACTION="${1:-up}"

if [ -n "${LR_DOCKER_CMD:-}" ]; then
    DOCKER_CMD="${LR_DOCKER_CMD}"
elif [ "$(id -u)" -eq 0 ] || docker info >/dev/null 2>&1; then
    DOCKER_CMD="docker"
else
    DOCKER_CMD="sudo docker"
fi

echo "=========================================================="
echo " [FMS DB Migration] 스키마 마이그레이션 실행"
echo "  - Target DB : ${DB_HOST}:${DB_PORT}/${DB_NAME} (User: ${DB_USER})"
echo "  - SQL Path  : ${MIGRATIONS_DIR}"
echo "  - Action    : ${ACTION}"
echo "=========================================================="

DB_URL="postgres://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=disable"

run_migrate() {
    if command -v migrate &> /dev/null; then
        migrate -path "${MIGRATIONS_DIR}" -database "${DB_URL}" "$@"
    else
        # Fallback to the official migrate container so neither Go nor a host migrate binary is required.
        ${DOCKER_CMD} run --rm --network host \
            -v "${MIGRATIONS_DIR}:/migrations:ro" \
            migrate/migrate:latest \
            -path=/migrations -database "${DB_URL}" "$@"
    fi
}

case "${ACTION}" in
    up)
        run_migrate up
        ;;
    down)
        STEPS="${2:-1}"
        run_migrate down "${STEPS}"
        ;;
    version)
        run_migrate version
        ;;
    *)
        echo "[ERROR] 지원하지 않는 명령입니다: ${ACTION} (사용 가능: up | down [N] | version)" >&2
        exit 1
        ;;
esac

echo "[OK] 스키마 마이그레이션 작업 완료 (Action: ${ACTION})"
