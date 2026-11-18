#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PGDATA_HOST_DIR="${LR_PGDATA_DIR:-/var/lib/loadrunner/pgdata}"
SOCKET_HOST_DIR="/var/run/postgresql"
MAX_WAIT_SEC=60

if docker info >/dev/null 2>&1; then
    DOCKER_CMD="docker"
else
    DOCKER_CMD="sudo docker"
fi
export LR_DOCKER_CMD="${DOCKER_CMD}"

TMP_STATUS_FILE="$(mktemp)"
trap 'rm -f "${TMP_STATUS_FILE}"' EXIT

echo "=== [1/4] 호스트 소켓 및 데이터 디렉토리 준비 ==="
# Use 1777 so any container postgres UID (70 on Alpine, 999 on Debian) can bind its socket file.
sudo mkdir -p "${SOCKET_HOST_DIR}"
sudo chmod 1777 "${SOCKET_HOST_DIR}"
sudo mkdir -p "${PGDATA_HOST_DIR}"

echo "=== [2/4] Docker Compose 기반 TimescaleDB 컨테이너 기동 ==="
cd "${DB_ROOT_DIR}"
${DOCKER_CMD} compose up -d

echo "=== [3/4] 컨테이너 헬스체크 대기 (최대 ${MAX_WAIT_SEC}초) ==="
elapsed=0
while true; do
    # Avoid command substitution $(...) around sudo so non-TTY PPID-scoped sudo tickets remain valid.
    if ${DOCKER_CMD} inspect -f '{{.State.Health.Status}}' fms_postgres > "${TMP_STATUS_FILE}" 2>/dev/null; then
        status="$(<"${TMP_STATUS_FILE}")"
    else
        status="starting"
    fi

    if [ "${status}" = "healthy" ]; then
        echo "[OK] fms_postgres 컨테이너 정상 준비 완료"
        break
    fi

    if [ "${elapsed}" -ge "${MAX_WAIT_SEC}" ]; then
        echo "[ERROR] ${MAX_WAIT_SEC}초 이내에 fms_postgres가 healthy 상태에 도달하지 못했습니다 (현재: ${status})." >&2
        ${DOCKER_CMD} logs fms_postgres --tail 30 >&2 || true
        exit 1
    fi

    sleep 2
    elapsed=$((elapsed + 2))
done

echo "=== [4/4] 스키마 마이그레이션 적용 ==="
if [ "${DOCKER_CMD}" = "sudo docker" ]; then
    sudo --preserve-env=LR_DB_USER,LR_DB_PASSWORD,LR_DB_NAME,LR_DB_HOST,LR_DB_PORT "${SCRIPT_DIR}/run_migration.sh" up
else
    "${SCRIPT_DIR}/run_migration.sh" up
fi

echo "=== [DONE] DB 인프라 및 1차 맵 스키마 배포 완료 ==="
