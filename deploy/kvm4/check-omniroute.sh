#!/usr/bin/env bash
set -euo pipefail

CONTAINER="modica-omniroute"
PORT="20128"

printf '\n=== OMNIROUTE SAFE CHECK ===\n'
printf 'Timestamp: '; date -Is

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "ERROR: $CONTAINER not found"
  exit 1
fi

printf '\n--- Image metadata ---\n'
docker image inspect "$(docker inspect -f '{{.Image}}' "$CONTAINER")" \
  --format 'RepoTags={{json .RepoTags}}\nRepoDigests={{json .RepoDigests}}\nCreated={{.Created}}\nArchitecture={{.Architecture}}\nOS={{.Os}}\nLabels={{json .Config.Labels}}' 2>/dev/null || true

printf '\n--- Last container logs (before start) ---\n'
docker logs --tail 80 "$CONTAINER" 2>&1 || true

printf '\n--- Starting existing OmniRoute only ---\n'
docker start "$CONTAINER" >/dev/null

printf 'Waiting for localhost:%s ...\n' "$PORT"
ready=0
for i in $(seq 1 30); do
  if curl -fsS --max-time 2 "http://127.0.0.1:${PORT}/" >/tmp/omniroute-root.$$ 2>/dev/null; then
    ready=1
    break
  fi
  if curl -fsS --max-time 2 "http://127.0.0.1:${PORT}/health" >/tmp/omniroute-health.$$ 2>/dev/null; then
    ready=1
    break
  fi
  sleep 1
done

printf '\n--- Container state ---\n'
docker ps --filter "name=^/${CONTAINER}$" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

printf '\n--- HTTP probes (no secrets) ---\n'
for path in / /health /api/health /v1/models; do
  code=$(curl -sS -o /tmp/omniroute-probe.$$ -w '%{http_code}' --max-time 5 "http://127.0.0.1:${PORT}${path}" 2>/dev/null || true)
  printf '%-18s HTTP %s\n' "$path" "${code:-ERR}"
  if [ -s /tmp/omniroute-probe.$$ ]; then
    head -c 300 /tmp/omniroute-probe.$$ | tr '\n' ' '
    echo
  fi
done

printf '\n--- Recent logs (after start) ---\n'
docker logs --tail 120 "$CONTAINER" 2>&1 || true

printf '\n--- Resource snapshot ---\n'
docker stats --no-stream "$CONTAINER" --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}' || true

printf '\n--- Host port confirmation ---\n'
ss -lntp | grep -E ":${PORT}\\b" || true

if [ "$ready" -eq 1 ]; then
  printf '\nRESULT: OmniRoute responded on localhost:%s.\n' "$PORT"
else
  printf '\nRESULT: Container started but HTTP readiness was not confirmed. Check logs above.\n'
fi

printf '\nNOTE: This script starts ONLY modica-omniroute. It does not touch Atzeno, Modica web, databases, networks, or volumes.\n'
printf '=== END OMNIROUTE SAFE CHECK ===\n'
