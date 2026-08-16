#!/usr/bin/env bash
set -u

printf '\n=== KVM4 HEALTHCARE PLATFORM PREFLIGHT ===\n'
printf 'Timestamp: '; date -Is 2>/dev/null || date
printf '\n--- OS ---\n'
cat /etc/os-release 2>/dev/null | sed -n '1,8p' || true
printf '\n--- Kernel / arch ---\n'
uname -a || true
printf '\n--- CPU ---\n'
nproc 2>/dev/null || true
lscpu 2>/dev/null | grep -E 'Model name|CPU\(s\)|Architecture' | head -n 6 || true
printf '\n--- Memory ---\n'
free -h || true
printf '\n--- Disk ---\n'
df -h / /var/lib/docker 2>/dev/null || df -h / || true
printf '\n--- Docker ---\n'
docker --version 2>/dev/null || echo 'Docker not found'
docker compose version 2>/dev/null || echo 'Docker Compose plugin not found'
printf '\n--- Running/stopped containers (names, status, published ports) ---\n'
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true
printf '\n--- Docker networks ---\n'
docker network ls 2>/dev/null || true
printf '\n--- Docker volumes ---\n'
docker volume ls 2>/dev/null || true
printf '\n--- Listening TCP ports ---\n'
ss -lntp 2>/dev/null | sed -n '1,120p' || true
printf '\n--- Firewall ---\n'
ufw status 2>/dev/null || true
printf '\n--- Docker disk usage ---\n'
docker system df 2>/dev/null || true
printf '\n=== END PREFLIGHT ===\n'
