#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="/opt/healthcare-job-board"
SUPABASE_DIR="/opt/healthcare-supabase"
SUPABASE_NETWORK="healthcare-supabase_default"
NODE_MODULES_VOLUME="healthcare-job-board-node-modules"
NODE_IMAGE="node:22-bookworm"
BOOTSTRAP_SQL="${APP_DIR}/prisma/migrations/20260430_01_create_all_db_push_tables_for_fresh_db/migration.sql"
KNOWN_FAILED_MIGRATIONS=(
  "20260430_add_saved_candidate_tags"
  "20260501_feedback_userid_and_testimonials"
)

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: run as root."
  exit 1
fi

for bin in docker grep awk sed; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: missing dependency: $bin"; exit 1; }
done

[[ -d "${APP_DIR}/.git" ]] || { echo "ERROR: app repo not found at ${APP_DIR}"; exit 2; }
[[ -f "${SUPABASE_DIR}/.env" ]] || { echo "ERROR: Supabase .env not found at ${SUPABASE_DIR}/.env"; exit 3; }
[[ -f "${APP_DIR}/prisma/schema.prisma" ]] || { echo "ERROR: Prisma schema not found"; exit 4; }
[[ -f "${APP_DIR}/package-lock.json" ]] || { echo "ERROR: package-lock.json not found"; exit 5; }
[[ -f "${BOOTSTRAP_SQL}" ]] || { echo "ERROR: fresh-DB bootstrap SQL not found: ${BOOTSTRAP_SQL}"; exit 11; }

echo
printf '%s\n' '=== HEALTHCARE PRISMA MIGRATION ==='
printf 'Timestamp: '; date -Is 2>/dev/null || date

if ! docker ps --format '{{.Names}} {{.Status}}' | grep -Eq '^supabase-db .*\(healthy\)'; then
  echo "ERROR: supabase-db is not running healthy."
  docker ps -a --format 'table {{.Names}}\t{{.Status}}' | grep -E 'NAMES|supabase-' || true
  exit 6
fi

if ! docker network inspect "${SUPABASE_NETWORK}" >/dev/null 2>&1; then
  echo "ERROR: Docker network ${SUPABASE_NETWORK} not found."
  exit 7
fi

POSTGRES_PASSWORD="$(grep -E '^POSTGRES_PASSWORD=' "${SUPABASE_DIR}/.env" | head -n1 | cut -d= -f2-)"
if [[ -z "${POSTGRES_PASSWORD}" ]]; then
  echo "ERROR: POSTGRES_PASSWORD is empty."
  exit 8
fi

DB_URL="postgresql://postgres:${POSTGRES_PASSWORD}@supabase-db:5432/postgres"

# The upstream project historically created 18 tables via `prisma db push`.
# Later migrations assume some of those relations already exist, while the
# formal repair migration that creates them sits much later (20260611).
# Apply our idempotent bootstrap SQL first so a genuinely fresh DB matches the
# historical production preconditions before Prisma replays the chain.
echo
printf '%s\n' '--- Fresh DB db-push baseline bootstrap ---'
docker exec -i supabase-db psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "${BOOTSTRAP_SQL}" >/dev/null
echo "Bootstrap tables ensured (idempotent; no data deleted)."

# Collect unresolved failed migration names, and recover only the explicitly
# reviewed historical fresh-DB failures. Unknown failures are never skipped.
RECOVER_LIST=()
if docker exec supabase-db psql -U postgres -d postgres -tAc \
  "SELECT CASE WHEN to_regclass('public._prisma_migrations') IS NULL THEN '' ELSE COALESCE(string_agg(migration_name, ',' ORDER BY started_at), '') END FROM public._prisma_migrations WHERE finished_at IS NULL AND rolled_back_at IS NULL;" \
  >/tmp/healthcare-prisma-failures.txt 2>/dev/null; then
  UNRESOLVED="$(tr -d '[:space:]' </tmp/healthcare-prisma-failures.txt)"
else
  UNRESOLVED=""
fi
rm -f /tmp/healthcare-prisma-failures.txt

if [[ -n "${UNRESOLVED}" ]]; then
  IFS=',' read -r -a FAILED_ARRAY <<< "${UNRESOLVED}"
  for failed in "${FAILED_ARRAY[@]}"; do
    known=0
    for allowed in "${KNOWN_FAILED_MIGRATIONS[@]}"; do
      if [[ "${failed}" == "${allowed}" ]]; then
        known=1
        RECOVER_LIST+=("${failed}")
        break
      fi
    done
    if [[ "${known}" -ne 1 ]]; then
      echo "ERROR: unknown unresolved Prisma migration failure: ${failed}"
      echo "Refusing to auto-resolve it. Inspect before continuing."
      exit 12
    fi
  done
fi

if [[ "${#RECOVER_LIST[@]}" -gt 0 ]]; then
  echo
  echo "Detected reviewed historical fresh-database failure(s):"
  printf ' - %s\n' "${RECOVER_LIST[@]}"
  echo "Only these will be marked rolled back before replaying the corrected chain."
fi

RECOVER_CSV=""
if [[ "${#RECOVER_LIST[@]}" -gt 0 ]]; then
  RECOVER_CSV="$(IFS=,; echo "${RECOVER_LIST[*]}")"
fi

docker volume inspect "${NODE_MODULES_VOLUME}" >/dev/null 2>&1 || docker volume create "${NODE_MODULES_VOLUME}" >/dev/null

echo
printf '%s\n' '--- Installing locked Node dependencies in isolated build volume ---'
echo "Node image: ${NODE_IMAGE}"
echo "Database target: supabase-db:5432/postgres (Docker-internal only)"

docker run --rm \
  --name healthcare-prisma-migrate \
  --network "${SUPABASE_NETWORK}" \
  -v "${APP_DIR}:/app" \
  -v "${NODE_MODULES_VOLUME}:/app/node_modules" \
  -w /app \
  -e NODE_ENV=development \
  -e DATABASE_URL="${DB_URL}" \
  -e DIRECT_URL="${DB_URL}" \
  -e RECOVER_CSV="${RECOVER_CSV}" \
  "${NODE_IMAGE}" \
  bash -lc '
    set -Eeuo pipefail
    node --version
    npm --version
    npm ci --no-audit --no-fund

    if [[ -n "${RECOVER_CSV}" ]]; then
      IFS="," read -r -a recover <<< "${RECOVER_CSV}"
      for migration in "${recover[@]}"; do
        echo
        echo "--- Recovering reviewed failed migration: ${migration} ---"
        npx prisma migrate resolve --rolled-back "${migration}"
      done
    fi

    echo
    echo "--- Prisma migrate deploy ---"
    npx prisma migrate deploy
    echo
    echo "--- Prisma generate ---"
    npx prisma generate
    echo
    echo "--- Prisma migration status ---"
    npx prisma migrate status
  '

echo
printf '%s\n' '--- Database verification ---'
PUBLIC_TABLES="$(docker exec supabase-db psql -U postgres -d postgres -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" | tr -d '[:space:]')"
MIGRATION_ROWS="$(docker exec supabase-db psql -U postgres -d postgres -tAc "SELECT CASE WHEN to_regclass('public._prisma_migrations') IS NULL THEN 0 ELSE (SELECT count(*) FROM public._prisma_migrations WHERE finished_at IS NOT NULL AND rolled_back_at IS NULL) END;" | tr -d '[:space:]')"
FAILED_ROWS="$(docker exec supabase-db psql -U postgres -d postgres -tAc "SELECT CASE WHEN to_regclass('public._prisma_migrations') IS NULL THEN 0 ELSE (SELECT count(*) FROM public._prisma_migrations WHERE finished_at IS NULL AND rolled_back_at IS NULL) END;" | tr -d '[:space:]')"

echo "Public schema tables: ${PUBLIC_TABLES:-unknown}"
echo "Successfully applied Prisma migrations: ${MIGRATION_ROWS:-unknown}"
echo "Unresolved failed Prisma migrations: ${FAILED_ROWS:-unknown}"

if [[ "${FAILED_ROWS:-1}" != "0" ]]; then
  echo "ERROR: unresolved Prisma migration failures remain."
  exit 10
fi

echo
printf '%s\n' '--- Supabase ports remain localhost-only ---'
ss -lntp 2>/dev/null | grep -E '127\.0\.0\.1:(8000|5432|6543)\b' || true

if ss -lnt 2>/dev/null | grep -E '0\.0\.0\.0:(8000|5432|6543)\b|\[::\]:(8000|5432|6543)\b' >/dev/null; then
  echo "ERROR: Supabase port exposure changed unexpectedly."
  exit 9
fi

echo
echo "RESULT: Prisma schema/migrations were applied to Healthcare Supabase PostgreSQL."
echo "No public web port was opened by this step."
printf '%s\n' '=== END HEALTHCARE PRISMA MIGRATION ==='
