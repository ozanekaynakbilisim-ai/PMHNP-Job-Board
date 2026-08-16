#!/usr/bin/env bash
set -Eeuo pipefail

RUNTIME_DIR="/opt/healthcare-supabase"
TMP_SRC=""

cleanup() {
  if [[ -n "${TMP_SRC}" && -d "${TMP_SRC}" ]]; then
    rm -rf "${TMP_SRC}"
  fi
}
trap cleanup EXIT

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: run as root."
  exit 1
fi

for bin in git docker openssl curl sed grep awk; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: missing dependency: $bin"; exit 1; }
done

echo
printf '%s\n' '=== HEALTHCARE SUPABASE LOCAL INSTALL ==='
printf 'Timestamp: '; date -Is 2>/dev/null || date

if docker ps -a --format '{{.Names}}' | grep -Eq '^supabase-(db|auth|storage|studio|envoy|pooler)$'; then
  echo "ERROR: Supabase-named containers already exist. Refusing to overwrite/reuse them automatically."
  docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E 'NAMES|supabase-' || true
  exit 2
fi

if [[ -f "${RUNTIME_DIR}/.healthcare-supabase-initialized" ]]; then
  echo "Existing Healthcare Supabase installation detected at ${RUNTIME_DIR}."
  echo "No files will be regenerated. Showing current status only."
  cd "${RUNTIME_DIR}"
  docker compose ps || true
  echo
  ss -lntp 2>/dev/null | grep -E ':(8000|5432|6543)\b' || true
  exit 0
fi

if [[ -e "${RUNTIME_DIR}" ]]; then
  echo "ERROR: ${RUNTIME_DIR} already exists but is not marked as an installation."
  echo "Inspect it manually; refusing to delete or overwrite it."
  exit 3
fi

mkdir -p "${RUNTIME_DIR}"
TMP_SRC="$(mktemp -d /opt/supabase-src.XXXXXX)"

echo
printf '%s\n' '--- Fetching official Supabase Docker configuration ---'
git clone --depth 1 --filter=blob:none --sparse https://github.com/supabase/supabase.git "${TMP_SRC}"
git -C "${TMP_SRC}" sparse-checkout set docker
cp -a "${TMP_SRC}/docker/." "${RUNTIME_DIR}/"

cd "${RUNTIME_DIR}"
cp .env.example .env

# Give this stack its own Compose project/network name.
sed -i '0,/^name: supabase$/s//name: healthcare-supabase/' docker-compose.yml

# Generate all self-hosted secrets using Supabase's official scripts.
echo
printf '%s\n' '--- Generating secure Supabase secrets ---'
sh utils/generate-keys.sh --update-env >/dev/null
sh utils/add-new-auth-keys.sh --update-env >/dev/null

set_env() {
  local key="$1"
  local value="$2"
  if grep -qE "^${key}=" .env; then
    # Values used here do not contain the delimiter.
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    printf '%s=%s\n' "$key" "$value" >> .env
  fi
}

# Stage 2A is intentionally localhost-only. Public URLs are replaced with
# HTTPS domains in Stage 2B before candidate/employer traffic is enabled.
set_env SUPABASE_PUBLIC_URL "http://127.0.0.1:8000"
set_env API_EXTERNAL_URL "http://127.0.0.1:8000/auth/v1"
set_env SITE_URL "http://127.0.0.1:3100"
set_env ADDITIONAL_REDIRECT_URLS "http://127.0.0.1:3100/**"
set_env STUDIO_DEFAULT_ORGANIZATION "HealthcareJobs"
set_env STUDIO_DEFAULT_PROJECT "HealthcareJobs"
set_env ENABLE_EMAIL_AUTOCONFIRM "true"

# Keep the base compose plus a strict localhost-publishing override.
set_env COMPOSE_FILE "docker-compose.yml:docker-compose.localhost.yml"

cat > docker-compose.localhost.yml <<'YAML'
services:
  api-gw:
    ports: !override
      - "127.0.0.1:8000:8000"
  supavisor:
    ports: !override
      - "127.0.0.1:5432:5432"
      - "127.0.0.1:6543:6543"
YAML

chmod 600 .env

echo
printf '%s\n' '--- Pulling official Supabase images ---'
docker compose pull

echo
printf '%s\n' '--- Starting Healthcare Supabase stack ---'
docker compose up -d

touch .healthcare-supabase-initialized

printf '%s\n' 'Waiting for the API gateway on 127.0.0.1:8000 ...'
ready=0
for _ in $(seq 1 90); do
  if curl -fsS --max-time 2 http://127.0.0.1:8000/ >/dev/null 2>&1; then
    ready=1
    break
  fi
  # A protected/redirect response also proves the gateway is listening.
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 2 http://127.0.0.1:8000/ 2>/dev/null || true)"
  if [[ "$code" =~ ^(200|301|302|307|308|401|403|404)$ ]]; then
    ready=1
    break
  fi
  sleep 2
done

echo
printf '%s\n' '--- Supabase containers ---'
docker compose ps

echo
printf '%s\n' '--- Local-only port confirmation ---'
ss -lntp 2>/dev/null | grep -E '127\.0\.0\.1:(8000|5432|6543)\b' || true

# Ensure we did not accidentally publish DB/API on every interface.
if ss -lnt 2>/dev/null | grep -E '0\.0\.0\.0:(8000|5432|6543)\b|\[::\]:(8000|5432|6543)\b' >/dev/null; then
  echo
  echo "ERROR: one or more Supabase ports appear publicly bound."
  echo "Stopping this newly-created stack for safety. Data is preserved."
  docker compose stop
  exit 4
fi

echo
printf '%s\n' '--- Resource snapshot ---'
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}' \
  $(docker compose ps -q) 2>/dev/null || true

if [[ "$ready" -eq 1 ]]; then
  echo
  echo "RESULT: Healthcare Supabase is running and its API/DB ports are localhost-only."
else
  echo
  echo "RESULT: Containers started, but API gateway did not become ready within the wait window."
  echo "Run: cd ${RUNTIME_DIR} && docker compose ps && docker compose logs --tail=120"
  exit 5
fi

echo
printf '%s\n' 'IMPORTANT: Email autoconfirm is TEMPORARILY enabled for local setup only.'
printf '%s\n' 'It will be disabled when SMTP + HTTPS/domain are configured for production.'
printf '%s\n' '=== END HEALTHCARE SUPABASE LOCAL INSTALL ==='
