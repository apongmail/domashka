#!/usr/bin/env bash
# Lifecycle-тести збереження даних для 4 конфігурацій.
# Результат: results/lifecycle.csv (+ детальний лог results/lifecycle.log).
#
# УВАГА: "Restart Docker Desktop" свідомо НЕ виконується (зачепив би сторонні
# контейнери на цій машині) — у матриці позначається "пропущено".
#
# docker compose down -v виконується ТІЛЬКИ для проєкту pg-lab після
# виведення точного списку його ресурсів у лог.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$LAB_ROOT"

CSV="$LAB_ROOT/results/lifecycle.csv"
LOG="$LAB_ROOT/results/lifecycle.log"
mkdir -p "$LAB_ROOT/results"
: > "$LOG"
echo "action,HOST,LAYER,VOLUME,BIND" > "$CSV"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }
row() { echo "$1,$2,$3,$4,$5" >> "$CSV"; }

port_of() { case "$1" in HOST) echo "$HOST_PORT";; LAYER) echo "$LAYER_PORT";; VOLUME) echo "$VOLUME_PORT";; BIND) echo "$BIND_PORT";; esac; }

# Маркер живий? Порівнюємо з останнім засіяним у results/markers/<VAR>.txt
check() {
  local VAR=$1 port m
  port=$(port_of "$VAR")
  m=$(cat "$LAB_ROOT/results/markers/$VAR.txt")
  if psql_port "$port" -tAc "SELECT 1 FROM lab_marker WHERE marker='$m'" 2>>"$LOG" | grep -q 1; then
    echo "збережено"
  else
    echo "втрачено"
  fi
}

wait_all_containers() {
  for p in "$LAYER_PORT" "$VOLUME_PORT" "$BIND_PORT"; do wait_pg "$p"; done
}

log "=== 0. Посів маркерів в усі 4 конфігурації ==="
"$LAB_ROOT/scripts/20_seed_markers.sh" | tee -a "$LOG"

log "=== 1. Restart PostgreSQL (pg_ctl restart / docker restart) ==="
"$PGBIN/pg_ctl" -D "$HOST_PGDATA" -l "$LAB_DATA_ROOT/host-postgres.log" \
  -o "-p $HOST_PORT -c listen_addresses=127.0.0.1" restart >>"$LOG" 2>&1
docker restart pg-lab-layer pg-lab-volume pg-lab-bind >>"$LOG" 2>&1
wait_pg "$HOST_PORT"; wait_all_containers
row "Restart" "$(check HOST)" "$(check LAYER)" "$(check VOLUME)" "$(check BIND)"

log "=== 2. Stop / start ==="
"$PGBIN/pg_ctl" -D "$HOST_PGDATA" stop -m fast >>"$LOG" 2>&1
docker stop pg-lab-layer pg-lab-volume pg-lab-bind >>"$LOG" 2>&1
sleep 2
"$PGBIN/pg_ctl" -D "$HOST_PGDATA" -l "$LAB_DATA_ROOT/host-postgres.log" \
  -o "-p $HOST_PORT -c listen_addresses=127.0.0.1" start >>"$LOG" 2>&1
docker start pg-lab-layer pg-lab-volume pg-lab-bind >>"$LOG" 2>&1
wait_pg "$HOST_PORT"; wait_all_containers
row "Stop/start" "$(check HOST)" "$(check LAYER)" "$(check VOLUME)" "$(check BIND)"

log "=== 3. Restart Docker Desktop — ПРОПУЩЕНО (сторонні контейнери на машині) ==="
row "Restart Docker Desktop" "n/a" "пропущено" "пропущено" "пропущено"

log "=== 4. Видалення контейнерів (docker rm -f, БЕЗ -v) ==="
# Фіксуємо анонімний volume LAYER-контейнера, щоб потім прибрати саме його
ANON_VOL=$(docker inspect pg-lab-layer --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{end}}{{end}}')
log "Анонімний volume pg-lab-layer (буде осиротілим після rm): $ANON_VOL"
docker rm -f pg-lab-layer pg-lab-volume pg-lab-bind >>"$LOG" 2>&1
# Після видалення: чи існує ще сховище даних?
vol_alive=$(docker volume inspect pg-lab-volume-data >/dev/null 2>&1 && echo "збережено" || echo "втрачено")
bind_alive=$([ -f "$BIND_DIR/18/docker/PG_VERSION" ] && echo "збережено" || echo "втрачено")
row "Видалення контейнера" "n/a" "втрачено (шар знищено)" "$vol_alive" "$bind_alive"
echo "$ANON_VOL" > "$LAB_ROOT/results/markers/layer-orphan-volume.txt"

log "=== 5. Повторне створення (docker compose up -d) ==="
docker compose up -d >>"$LOG" 2>&1
wait_all_containers
row "Повторне створення" "n/a" "$(check LAYER)" "$(check VOLUME)" "$(check BIND)"

log "Пересіюємо маркер LAYER (дані втрачено на кроці 4-5)"
"$LAB_ROOT/scripts/20_seed_markers.sh" LAYER | tee -a "$LOG"

log "=== 6. docker compose down (без -v) → up ==="
docker compose down >>"$LOG" 2>&1
docker compose up -d >>"$LOG" 2>&1
wait_all_containers
row "compose down" "n/a" "$(check LAYER)" "$(check VOLUME)" "$(check BIND)"

log "Пересіюємо маркер LAYER"
"$LAB_ROOT/scripts/20_seed_markers.sh" LAYER | tee -a "$LOG"

log "=== 7. docker compose down -v (ТІЛЬКИ проєкт pg-lab) → up ==="
log "Ресурси проєкту pg-lab, які буде видалено:"
docker compose ps -a --format '{{.Name}}' | tee -a "$LOG"
docker volume ls --filter label=com.docker.compose.project=pg-lab --format '{{.Name}}' | tee -a "$LOG"
docker compose down -v >>"$LOG" 2>&1
docker compose up -d >>"$LOG" 2>&1
wait_all_containers
row "compose down -v" "n/a" "$(check LAYER)" "$(check VOLUME)" "$(check BIND)"

log "=== Готово. Матриця: ==="
column -s, -t "$CSV" | tee -a "$LOG"
