#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="/opt/healthcare-job-board"
SUPABASE_DIR="/opt/healthcare-supabase"
RUNTIME_DIR="/opt/healthcare-job-board-runtime"
APP_ENV="${RUNTIME_DIR}/app.env"
SUPABASE_NETWORK="healthcare-supabase_default"
NODE_MODULES_VOLUME="healthcare-job-board-node-modules"
NODE_IMAGE="node:22-bookworm"
APP_CONTAINER="healthcare-job-board-app"
APP_PORT="3100"

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: run as root."
  exit 1
fi

for bin in docker grep openssl curl ss; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: missing dependency: $bin"; exit 1; }
done

[[ -d "${APP_DIR}/.git" ]] || { echo "ERROR: app repo not found at ${APP_DIR}"; exit 2; }
[[ -f "${SUPABASE_DIR}/.env" ]] || { echo "ERROR: Supabase .env not found"; exit 3; }

echo
printf '%s\n' '=== HEALTHCARE NEXT.JS LOCAL BUILD + START ==='
printf 'Timestamp: '; date -Is 2>/dev/null || date

if ! docker ps --format '{{.Names}} {{.Status}}' | grep -Eq '^supabase-db .*\(healthy\)'; then
  echo "ERROR: supabase-db is not healthy."
  exit 4
fi

if ! docker network inspect "${SUPABASE_NETWORK}" >/dev/null 2>&1; then
  echo "ERROR: Docker network ${SUPABASE_NETWORK} not found."
  exit 5
fi

# Refuse to steal an unrelated process's port.
if ss -lnt 2>/dev/null | grep -Eq "127\.0\.0\.1:${APP_PORT}\b|0\.0\.0\.0:${APP_PORT}\b|\[::\]:${APP_PORT}\b"; then
  if ! docker ps --format '{{.Names}} {{.Ports}}' | grep -Eq "^${APP_CONTAINER} .*${APP_PORT}"; then
    echo "ERROR: port ${APP_PORT} is already in use by something other than ${APP_CONTAINER}."
    ss -lntp 2>/dev/null | grep -E ":${APP_PORT}\b" || true
    exit 6
  fi
fi

read_env() {
  local key="$1"
  grep -E "^${key}=" "${SUPABASE_DIR}/.env" | head -n1 | cut -d= -f2-
}

POSTGRES_PASSWORD="$(read_env POSTGRES_PASSWORD)"
ANON_KEY="$(read_env ANON_KEY)"
SERVICE_ROLE_KEY="$(read_env SERVICE_ROLE_KEY)"

for pair in "POSTGRES_PASSWORD:${POSTGRES_PASSWORD}" "ANON_KEY:${ANON_KEY}" "SERVICE_ROLE_KEY:${SERVICE_ROLE_KEY}"; do
  key="${pair%%:*}"
  value="${pair#*:}"
  [[ -n "$value" ]] || { echo "ERROR: ${key} is empty in Supabase env."; exit 7; }
done

mkdir -p "${RUNTIME_DIR}"
chmod 700 "${RUNTIME_DIR}"

# Preserve stable application secrets across reruns.
if [[ -f "${APP_ENV}" ]]; then
  CRON_SECRET="$(grep -E '^CRON_SECRET=' "${APP_ENV}" | head -n1 | cut -d= -f2- || true)"
  EMAIL_HASH_SALT="$(grep -E '^EMAIL_HASH_SALT=' "${APP_ENV}" | head -n1 | cut -d= -f2- || true)"
  SHORTLINK_HASH_SECRET="$(grep -E '^SHORTLINK_HASH_SECRET=' "${APP_ENV}" | head -n1 | cut -d= -f2- || true)"
  NEXTAUTH_SECRET="$(grep -E '^NEXTAUTH_SECRET=' "${APP_ENV}" | head -n1 | cut -d= -f2- || true)"
else
  CRON_SECRET=""
  EMAIL_HASH_SALT=""
  SHORTLINK_HASH_SECRET=""
  NEXTAUTH_SECRET=""
fi

[[ -n "${CRON_SECRET}" ]] || CRON_SECRET="$(openssl rand -hex 32)"
[[ -n "${EMAIL_HASH_SALT}" ]] || EMAIL_HASH_SALT="$(openssl rand -hex 32)"
[[ -n "${SHORTLINK_HASH_SECRET}" ]] || SHORTLINK_HASH_SECRET="$(openssl rand -hex 32)"
[[ -n "${NEXTAUTH_SECRET}" ]] || NEXTAUTH_SECRET="$(openssl rand -hex 32)"

DB_URL="postgresql://postgres:${POSTGRES_PASSWORD}@supabase-db:5432/postgres"

cat > "${APP_ENV}" <<EOF
NODE_ENV=production
DATABASE_URL=${DB_URL}
DIRECT_URL=${DB_URL}
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:8000
SUPABASE_INTERNAL_URL=http://api-gw:8000
NEXT_PUBLIC_SUPABASE_ANON_KEY=${ANON_KEY}
SUPABASE_SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}
NEXT_PUBLIC_APP_URL=http://127.0.0.1:${APP_PORT}
NEXT_PUBLIC_BASE_URL=http://127.0.0.1:${APP_PORT}
CRON_SECRET=${CRON_SECRET}
EMAIL_HASH_SALT=${EMAIL_HASH_SALT}
SHORTLINK_HASH_SECRET=${SHORTLINK_HASH_SECRET}
NEXTAUTH_SECRET=${NEXTAUTH_SECRET}
ENABLE_PAID_POSTING=false
KILL_AI_CANDIDATE_COVER_LETTER=true
KILL_AI_CANDIDATE_RESUME_PARSER=true
VIRUS_SCAN_FAIL_OPEN=true
LOG_LEVEL=info
EOF
chmod 600 "${APP_ENV}"

# Reuse the dependency volume created during migration.
docker volume inspect "${NODE_MODULES_VOLUME}" >/dev/null 2>&1 || docker volume create "${NODE_MODULES_VOLUME}" >/dev/null

echo
echo '--- Building Next.js in an isolated Node container ---'
echo "Public preview URL: http://127.0.0.1:${APP_PORT}"
echo 'Supabase browser URL: http://127.0.0.1:8000'
echo 'Supabase server URL:  http://api-gw:8000 (Docker private network)'
echo 'Paid posting: disabled'
echo 'AI candidate features: disabled until OmniRoute providers are connected'

docker rm -f healthcare-next-build >/dev/null 2>&1 || true

docker run --rm \
  --name healthcare-next-build \
  --network "${SUPABASE_NETWORK}" \
  --env-file "${APP_ENV}" \
  -e NODE_OPTIONS=--max-old-space-size=4096 \
  -v "${APP_DIR}:/app" \
  -v "${NODE_MODULES_VOLUME}:/app/node_modules" \
  -w /app \
  "${NODE_IMAGE}" \
  bash -lc '
    set -Eeuo pipefail
    npm ci --no-audit --no-fund
    npm run build
  '

echo
echo '--- Starting local-only Next.js runtime container ---'
docker rm -f "${APP_CONTAINER}" >/dev/null 2>&1 || true

docker run -d \
  --name "${APP_CONTAINER}" \
  --restart unless-stopped \
  --network "${SUPABASE_NETWORK}" \
  --env-file "${APP_ENV}" \
  -e NODE_OPTIONS=--max-old-space-size=1536 \
  -p "127.0.0.1:${APP_PORT}:${APP_PORT}" \
  -v "${APP_DIR}:/app" \
  -v "${NODE_MODULES_VOLUME}:/app/node_modules" \
  -w /app \
  "${NODE_IMAGE}" \
  bash -lc "exec npx next start -H 0.0.0.0 -p ${APP_PORT}" >/dev/null

printf 'Waiting for http://127.0.0.1:%s ...\n' "${APP_PORT}"
ready=0
http_code="000"
for _ in $(seq 1 90); do
  http_code="$(curl -sS -o /tmp/healthcare-home.html -w '%{http_code}' --max-time 5 "http://127.0.0.1:${APP_PORT}/" 2>/dev/null || true)"
  if [[ "${http_code}" =~ ^(200|301|302|307|308)$ ]]; then
    ready=1
    break
  fi
  sleep 2
done

echo
echo '--- App container ---'
docker ps --filter "name=^/${APP_CONTAINER}$" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

echo
echo '--- HTTP probe ---'
echo "Homepage HTTP ${http_code}"
if [[ -f /tmp/healthcare-home.html ]]; then
  head -c 300 /tmp/healthcare-home.html | tr '\n' ' ' || true
  echo
fi

echo
echo '--- Recent app logs ---'
docker logs --tail 100 "${APP_CONTAINER}" 2>&1 || true

echo
echo '--- Local-only port confirmation ---'
ss -lntp 2>/dev/null | grep -E "127\.0\.0\.1:${APP_PORT}\b" || true

if ss -lnt 2>/dev/null | grep -E "0\.0\.0\.0:${APP_PORT}\b|\[::\]:${APP_PORT}\b" >/dev/null; then
  echo "ERROR: app port ${APP_PORT} appears publicly bound. Stopping app container for safety."
  docker stop "${APP_CONTAINER}" >/dev/null || true
  exit 8
fi

if [[ "${ready}" -ne 1 ]]; then
  echo
  echo "RESULT: Build completed, but the homepage did not become healthy."
  echo "The app container was left running for log inspection."
  exit 9
fi

echo
echo "RESULT: Healthcare Job Board is running locally on 127.0.0.1:${APP_PORT}."
echo 'No public web port was opened by this stage.'
echo 'Next step: SSH preview, then domain/Caddy/HTTPS and production Supabase URL.'
printf '%s\n' '=== END HEALTHCARE NEXT.JS LOCAL BUILD + START ==='
