#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="/opt/healthcare-job-board"
SUPABASE_DIR="/opt/healthcare-supabase"
SUPABASE_NETWORK="healthcare-supabase_default"
NODE_MODULES_VOLUME="healthcare-job-board-node-modules"
NODE_IMAGE="node:22-bookworm"
KNOWN_FAILED_MIGRATION="20260430_add_saved_candidate_tags"

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

echo
printf '%s\n' '=== HEALTHCARE PRISMA MIGRATION ==='
printf 'Timestamp: '; date -Is 2>/dev/null || date

# Supabase health guard.
if ! docker ps --format '{{.Names}} {{.Status}}' | grep -Eq '^supabase-db .*\(healthy\)'; then
  echo "ERROR: supabase-db is not running healthy."
  docker ps -a --format 'table {{.Names}}\t{{.Status}}' | grep -E 'NAMES|supabase-' || true
  exit 6
fi

if ! docker network inspect "${SUPABASE_NETWORK}" >/dev/null 2>&1; then
  echo "ERROR: Docker network ${SUPABASE_NETWORK} not found."
  exit 7
fi

# Read only the generated database password. Supabase's official generator
# emits POSTGRES_PASSWORD as hex, so it is URL-safe without transformation.
POSTGRES_PASSWORD="$(grep -E '^POSTGRES_PASSWORD=' "${SUPABASE_DIR}/.env" | head -n1 | cut -d= -f2-)"
if [[ -z "${POSTGRES_PASSWORD}" ]]; then
  echo "ERROR: POSTGRES_PASSWORD is empty."
  exit 8
fi

DB_URL="postgresql://postgres:${POSTGRES_PASSWORD}@supabase-db:5432/postgres"

# Prisma blocks all later migrations after any failed migration. There is one
# known historical fresh-DB failure in this upstream repo:
# 20260430_add_saved_candidate_tags assumes saved_candidates already exists,
# because that table originally reached production via `prisma db push`.
# Our earlier idempotent bootstrap migration now fixes the ordering for clean
# installs. If THIS exact failure is recorded from a previous run, mark only
# that migration rolled back so Prisma may replay the corrected chain.
RECOVER_KNOWN_FAILURE=0
if docker exec supabase-db psql -U postgres -d postgres -tAc \
  "SELECT CASE WHEN to_regclass('public._prisma_migrations') IS NOT NULL AND EXISTS (SELECT 1 FROM public._prisma_migrations WHERE migration_name='${KNOWN_FAILED_MIGRATION}' AND finished_at IS NULL AND rolled_back_at IS NULL) THEN 1 ELSE 0 END;" \
  2>/dev/null | grep -q '^1$'; then
  RECOVER_KNOWN_FAILURE=1
  echo
  echo "Detected the known failed fresh-database migration: ${KNOWN_FAILED_MIGRATION}"
  echo "It will be marked rolled back with Prisma before replaying the corrected migration chain."
fi

# Cache npm dependencies in a Docker volume. No host Node installation needed.
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
  -e RECOVER_KNOWN_FAILURE="${RECOVER_KNOWN_FAILURE}" \
  -e KNOWN_FAILED_MIGRATION="${KNOWN_FAILED_MIGRATION}" \
  "${NODE_IMAGE}" \
  bash -lc '
    set -Eeuo pipefail
    node --version
    npm --version
    npm ci --no-audit --no-fund

    if [[ "${RECOVER_KNOWN_FAILURE}" == "1" ]]; then
      echo
      echo "--- Recovering known failed migration ---"
      npx prisma migrate resolve --rolled-back "${KNOWN_FAILED_MIGRATION}"
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
