# LoadRunner FMS DB 인프라 및 배포 설명서 (`lr_configs/db`)

이 디렉토리는 현장 설치 및 배포 시 `lr_configs` 패키지와 함께 전달되는 **PostgreSQL / TimescaleDB 컨테이너 실행 설정, 스키마 마이그레이션 SQL, 자동 배포 스크립트**를 관리합니다.

---

## 1. 디렉토리 및 파일별 역할

```text
lr_configs/db/
├── docker-compose.yml                         # TimescaleDB 컨테이너 정의 (소켓 및 영속 볼륨 설정)
├── README.md                                  # 본 파일 (구성 파일 역할 및 실행 매뉴얼)
├── migrations/                                # golang-migrate 버전 관리 DDL 스크립트
│   ├── 000001_init_extensions.up.sql          # TimescaleDB 확장 활성화
│   ├── 000001_init_extensions.down.sql        # TimescaleDB 확장 제거 (롤백용)
│   ├── 000002_create_graph_versions.up.sql    # 1차 PoC 맵 버전 관리 테이블(fms_graph_versions) 생성
│   └── 000002_create_graph_versions.down.sql  # fms_graph_versions 테이블 제거 (롤백용)
└── scripts/                                   # 현장 자동 배포 및 스키마 적용 쉘 스크립트
    ├── deploy_db.sh                           # 컨테이너 기동 + 헬스체크 + 마이그레이션 원클릭 실행
    └── run_migration.sh                       # golang-migrate CLI 래퍼 (up / down / version)
```

### 각 파일의 상세 역할

1. **`docker-compose.yml`**
   * **역할:** `timescale/timescaledb:latest-pg16` 공식 이미지를 `fms_postgres` 컨테이너로 띄우는 Docker Compose 명세 파일입니다.
   * **주요 설정:**
     * `/var/lib/loadrunner/pgdata:/var/lib/postgresql/data`: DB 실제 데이터를 `lr_configs` 바깥의 호스트 경로에 영속 저장합니다. 따라서 [`send_this_configs_file.sh`](../send_this_configs_file.sh) 실행 시 운영 데이터가 설정 압축 파일에 섞이지 않습니다.
     * `/var/run/postgresql:/var/run/postgresql`: 호스트와 소켓 디렉토리를 공유 마운트하여 `app_fms`가 TCP/IP 오버헤드 없이 Unix Domain Socket으로 고속 통신할 수 있게 합니다.
     * `healthcheck`: `pg_isready`로 DB가 실제 쿼리를 받을 수 있는 상태인지 5초 간격으로 확인합니다.

2. **`migrations/000001_init_extensions.{up,down}.sql`**
   * **역할:** PostgreSQL 내부에 시계열 데이터 관리용 `timescaledb` 확장을 활성화(`.up.sql`)하거나 제거(`.down.sql`)합니다.
   * **실행 순서:** 모든 테이블 생성보다 앞서 가장 먼저 1번 버전으로 적용됩니다.

3. **`migrations/000002_create_graph_versions.{up,down}.sql`**
   * **역할:** 1차 PoC 대상인 **맵 업로드 / 다운로드 기능**을 위한 `fms_graph_versions` 테이블과 활성 맵 조회용 복합 인덱스(`idx_graph_versions_site_active`)를 생성합니다.
   * **주요 컬럼:** `version_id` (PK), `site_name`, `map_name`, `content_hash`, `node_count`, `link_count`, `snapshot_payload` (`JSONB` 전체 노드/링크 스냅샷), `is_active`, `created_by`, `created_at`.

4. **`scripts/run_migration.sh`**
   * **역할:** 스키마 버전 관리 도구인 `golang-migrate`를 호출하여 `migrations/` 폴더의 SQL 파일을 순서대로 DB에 반영합니다.
   * **참고:** Go(Golang) 언어를 설치할 필요는 없습니다. 호스트에 단일 바이너리 `migrate`가 있으면 바로 사용하고, 없으면 `migrate/migrate:latest` Docker 이미지를 자동으로 내려받아 실행한 뒤 즉시 종료(`--rm`)합니다.
   * **지원 인자:**
     * `./run_migration.sh` (또는 `./run_migration.sh up`): 최신 버전까지 스키마 적용
     * `./run_migration.sh down 1`: 직전 1단계 마이그레이션 롤백
     * `./run_migration.sh version`: 현재 DB에 적용된 스키마 버전 번호 확인

5. **`scripts/deploy_db.sh`**
   * **역할:** 현장 IPC에 설치된 뒤 단 한 번의 실행으로 DB 인프라를 기동하고 스키마까지 적용하는 **통합 배포 엔트리포인트**입니다.
   * **내부 4단계:**
     1. `/var/run/postgresql`(권한 `1777`) 및 `/var/lib/loadrunner/pgdata` 호스트 디렉토리 준비
     2. `docker compose up -d`로 컨테이너 백그라운드 실행
     3. `fms_postgres`가 `healthy` 상태가 될 때까지 최대 60초 대기 (실패 시 로그 출력 후 종료)
     4. `run_migration.sh up` 자동 실행

---

## 2. 실행 방법 (Ubuntu IPC 현장 기준)

```bash
# 1. 실행 권한 부여 (최초 1회)
chmod +x ./scripts/deploy_db.sh ./scripts/run_migration.sh

# 2. 원클릭 배포 실행 (컨테이너 기동 + 스키마 적용)
./scripts/deploy_db.sh

# 3. 정상 동작 확인 (소켓 파일 및 테이블 생성 여부)
ls -l /var/run/postgresql/.s.PGSQL.5432
docker exec -it fms_postgres psql -U lr -d loadrunner_fms -c "\dt"
```

---

## 3. 환경 변수 커스터마이징

기본값 외에 사이트별 계정이나 포트를 변경해야 할 경우 스크립트 실행 전 환경 변수를 지정하면 됩니다.

| 환경 변수 | 기본값 | 설명 |
| :--- | :--- | :--- |
| `LR_DB_USER` | `lr` | PostgreSQL 접속 계정 |
| `LR_DB_PASSWORD` | `lr1234` | PostgreSQL 비밀번호 |
| `LR_DB_NAME` | `loadrunner_fms` | 생성 및 접속 대상 데이터베이스 이름 |
| `LR_DB_HOST` | `127.0.0.1` | 마이그레이션 CLI 접속 호스트 |
| `LR_DB_PORT` | `5432` | PostgreSQL 노출 포트 |
| `LR_PGDATA_DIR` | `/var/lib/loadrunner/pgdata` | 호스트 DB 데이터 영속 경로 |
