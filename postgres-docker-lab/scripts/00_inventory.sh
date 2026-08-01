#!/usr/bin/env bash
# Інвентаризація середовища → results/inventory.txt
set -euo pipefail
source "$(dirname "$0")/lib.sh"
OUT="$LAB_ROOT/results/inventory.txt"
mkdir -p "$LAB_ROOT/results"

{
  echo "=== Дата ==="; date
  echo; echo "=== Апаратне забезпечення ==="
  system_profiler SPHardwareDataType 2>/dev/null | grep -E "Model Name|Model Identifier|Chip|Total Number of Cores|Memory"
  echo; echo "=== macOS ==="; sw_vers
  echo; echo "=== Файлова система (корінь) ==="
  diskutil info / | grep -E "File System Personality|Volume Name" || true
  echo; echo "=== Docker Desktop ==="
  echo "App version: $(defaults read /Applications/Docker.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo n/a)"
  docker version --format 'Engine: {{.Server.Version}} ({{.Server.Os}}/{{.Server.Arch}})'
  docker info --format 'VM resources: CPUs={{.NCPU}}, Memory={{.MemTotal}} bytes; Storage driver: {{.Driver}}; Kernel: {{.KernelVersion}}'
  echo; echo "=== PostgreSQL (native, Homebrew) ==="
  "$PGBIN/postgres" --version
  echo; echo "=== Образ postgres ==="
  docker image inspect postgres:18.4 --format 'Tag: postgres:18.4{{"\n"}}Digest: {{index .RepoDigests 0}}{{"\n"}}Arch: {{.Architecture}}'
  echo; echo "=== data_directory кожного варіанта (SHOW data_directory) ==="
  for v in HOST:$HOST_PORT LAYER:$LAYER_PORT VOLUME:$VOLUME_PORT BIND:$BIND_PORT; do
    name=${v%%:*}; port=${v##*:}
    dir=$(psql_port "$port" -tAc "SHOW data_directory" 2>/dev/null || echo "не запущено")
    echo "$name (port $port): $dir"
  done
} | tee "$OUT"
