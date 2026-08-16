#!/usr/bin/env bash
set -u

printf '\n=== KVM4 EXISTING SERVICE INSPECTION ===\n'
printf 'Timestamp: '; date -Is 2>/dev/null || date

printf '\n--- Port 3000 owner ---\n'
PID="$(ss -lntp 2>/dev/null | awk '/\*:3000|0\.0\.0\.0:3000|\[::\]:3000/ {match($0,/pid=([0-9]+)/,m); if (m[1]) {print m[1]; exit}}')"
if [ -n "${PID:-}" ]; then
  ps -fp "$PID" || true
  printf '\nCommand line:\n'
  tr '\0' ' ' < "/proc/$PID/cmdline" 2>/dev/null || true
  printf '\n\nWorking directory:\n'
  readlink -f "/proc/$PID/cwd" 2>/dev/null || true
else
  echo 'No listener found on port 3000.'
fi

printf '\n--- Existing modica-omniroute container ---\n'
if docker inspect modica-omniroute >/dev/null 2>&1; then
  docker inspect modica-omniroute --format 'Name={{.Name}}\nImage={{.Config.Image}}\nStatus={{.State.Status}}\nRestartPolicy={{.HostConfig.RestartPolicy.Name}}\nNetworkMode={{.HostConfig.NetworkMode}}\nPorts={{json .HostConfig.PortBindings}}\nMounts={{json .Mounts}}\nNetworks={{json .NetworkSettings.Networks}}' || true
  printf '\nEnvironment variable NAMES only (values hidden):\n'
  docker inspect modica-omniroute --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
    | sed 's/=.*$/=<redacted>/' \
    | sort || true
else
  echo 'modica-omniroute container not found.'
fi

printf '\n--- Existing Ollama ---\n'
if command -v curl >/dev/null 2>&1; then
  curl -fsS --max-time 3 http://172.16.0.1:11434/api/tags 2>/dev/null \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print("Models:"); [print(" - "+m.get("name","?")) for m in d.get("models",[])]' 2>/dev/null \
    || echo 'Ollama endpoint exists but model list could not be read.'
else
  echo 'curl not available.'
fi

printf '\n--- Compose labels for existing containers ---\n'
for c in atzeno-frontend atzeno-backend atzeno-mongodb modica-web modica-n8n modica-omniroute modica-postgres; do
  if docker inspect "$c" >/dev/null 2>&1; then
    printf '\n[%s]\n' "$c"
    docker inspect "$c" --format 'project={{index .Config.Labels "com.docker.compose.project"}} working_dir={{index .Config.Labels "com.docker.compose.project.working_dir"}} config_files={{index .Config.Labels "com.docker.compose.project.config_files"}}' 2>/dev/null || true
  fi
done

printf '\n--- Ports 80/443/20128/3000/3100/5432/6379/8000 ---\n'
ss -lntp 2>/dev/null | grep -E ':(80|443|20128|3000|3100|5432|6379|8000)\b' || true

printf '\n=== END INSPECTION ===\n'
