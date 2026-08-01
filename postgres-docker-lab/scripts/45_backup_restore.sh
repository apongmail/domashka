#!/usr/bin/env bash
# Backup (pg_dump -Fc) + restore (pg_restore) у НОВИЙ порожній кластер
# для варіантів HOST і VOLUME. Результати: results/backup_restore.csv + .log
set -euo pipefail
source "$(dirname "$0")/lib.sh"
LOG="$LAB_ROOT/results/backup_restore.log"
CSV="$LAB_ROOT/results/backup_restore.csv"
TMP="$LAB_ROOT/results/tmp"; mkdir -p "$TMP"
: > "$LOG"
echo "variant,dump_seconds,restore_seconds,rows_source,rows_restored,marker_ok,dump_size_mb" > "$CSV"
say() { echo -e "$*" | tee -a "$LOG"; }
now_s() { perl -MTime::HiRes=time -e 'printf "%.2f", time'; }

RESTORE_HOST_PORT=5498
RESTORE_VOL_PORT=5437

seed_testdata() { # $1 = port
  psql_port "$1" -q -c "DROP TABLE IF EXISTS backup_test;" \
    -c "CREATE TABLE backup_test AS SELECT g AS id, md5(g::text) AS payload FROM generate_series(1, 2000000) g;" \
    -c "ALTER TABLE backup_test ADD PRIMARY KEY (id);"
}

verify() { # $1=port  $2=marker  → друкує rows|marker_ok
  local rows ok
  rows=$(psql_port "$1" -tAc "SELECT count(*) FROM backup_test")
  ok=$(psql_port "$1" -tAc "SELECT count(*) FROM lab_marker WHERE marker='$2'")
  echo "$rows|$([ "$ok" -ge 1 ] && echo yes || echo no)"
}

# ---------------- HOST ----------------
say "=== HOST: тестові дані (2 млн рядків) ==="
seed_testdata "$HOST_PORT"
SRC_ROWS=$(psql_port "$HOST_PORT" -tAc "SELECT count(*) FROM backup_test")
MARKER=$(cat "$LAB_ROOT/results/markers/HOST.txt")

say "=== HOST: pg_dump -Fc ==="
t0=$(now_s)
"$PGBIN/pg_dump" -h 127.0.0.1 -p "$HOST_PORT" -U "$(whoami)" -d lab -Fc -f "$TMP/host.dump"
t1=$(now_s)
DUMP_S=$(echo "$t1 $t0" | awk '{printf "%.1f", $1-$2}')
DUMP_MB=$(du -m "$TMP/host.dump" | cut -f1)

say "=== HOST: новий порожній кластер (initdb, port $RESTORE_HOST_PORT) + pg_restore ==="
RESTORE_PGDATA="$LAB_DATA_ROOT/host-restore-pgdata"
# Ідемпотентність: коректно зупинити кластер із попереднього запуску, якщо він живий
"$PGBIN/pg_ctl" -D "$RESTORE_PGDATA" stop -m fast >/dev/null 2>&1 || true
rm -rf "$RESTORE_PGDATA"
"$PGBIN/initdb" -D "$RESTORE_PGDATA" --encoding=UTF8 --auth-local=trust --auth-host=trust >/dev/null
"$PGBIN/pg_ctl" -D "$RESTORE_PGDATA" -l "$LAB_DATA_ROOT/host-restore.log" \
  -o "-p $RESTORE_HOST_PORT -c listen_addresses=127.0.0.1" start >>"$LOG" 2>&1
wait_pg "$RESTORE_HOST_PORT"
"$PGBIN/psql" -h 127.0.0.1 -p "$RESTORE_HOST_PORT" -d postgres -q \
  -c "CREATE ROLE lab LOGIN" -c "CREATE DATABASE lab OWNER lab"
t0=$(now_s)
"$PGBIN/pg_restore" -h 127.0.0.1 -p "$RESTORE_HOST_PORT" -U "$(whoami)" -d lab "$TMP/host.dump" >>"$LOG" 2>&1
t1=$(now_s)
REST_S=$(echo "$t1 $t0" | awk '{printf "%.1f", $1-$2}')
RES=$("$PGBIN/psql" -h 127.0.0.1 -p "$RESTORE_HOST_PORT" -U "$(whoami)" -d lab -tAc \
  "SELECT count(*) FROM backup_test") ; MOK=$("$PGBIN/psql" -h 127.0.0.1 -p "$RESTORE_HOST_PORT" -U "$(whoami)" -d lab -tAc \
  "SELECT count(*) FROM lab_marker WHERE marker='$MARKER'")
echo "HOST,$DUMP_S,$REST_S,$SRC_ROWS,$RES,$([ "$MOK" -ge 1 ] && echo yes || echo no),$DUMP_MB" >> "$CSV"
say "HOST: dump=${DUMP_S}s restore=${REST_S}s rows=${SRC_ROWS}→${RES} marker_ok=$MOK dump=${DUMP_MB}MB"
"$PGBIN/pg_ctl" -D "$RESTORE_PGDATA" stop -m fast >>"$LOG" 2>&1
rm -rf "$RESTORE_PGDATA"

# ---------------- VOLUME ----------------
say "=== VOLUME: тестові дані (2 млн рядків) ==="
docker start pg-lab-volume >/dev/null 2>&1 || true
wait_pg "$VOLUME_PORT"
# Після lifecycle down -v кластер новий — пересіємо маркер, якщо його нема
psql_port "$VOLUME_PORT" -tAc "SELECT 1 FROM lab_marker LIMIT 1" >/dev/null 2>&1 \
  || "$LAB_ROOT/scripts/20_seed_markers.sh" VOLUME >>"$LOG"
seed_testdata "$VOLUME_PORT"
SRC_ROWS=$(psql_port "$VOLUME_PORT" -tAc "SELECT count(*) FROM backup_test")
MARKER=$(cat "$LAB_ROOT/results/markers/VOLUME.txt")

say "=== VOLUME: pg_dump -Fc (клієнт на macOS, TCP 127.0.0.1) ==="
t0=$(now_s)
PGPASSWORD="$POSTGRES_PASSWORD" "$PGBIN/pg_dump" -h 127.0.0.1 -p "$VOLUME_PORT" -U lab -d lab -Fc -f "$TMP/volume.dump"
t1=$(now_s)
DUMP_S=$(echo "$t1 $t0" | awk '{printf "%.1f", $1-$2}')
DUMP_MB=$(du -m "$TMP/volume.dump" | cut -f1)

say "=== VOLUME: новий контейнер + новий named volume + pg_restore ==="
docker rm -f -v pg-lab-volume-restore >/dev/null 2>&1 || true
docker volume rm pg-lab-volume-restore-data >/dev/null 2>&1 || true
docker run -d --name pg-lab-volume-restore \
  -e POSTGRES_USER=lab -e POSTGRES_DB=lab -e "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" \
  -p 127.0.0.1:$RESTORE_VOL_PORT:5432 \
  -v pg-lab-volume-restore-data:/var/lib/postgresql postgres:18.4 >>"$LOG"
wait_pg "$RESTORE_VOL_PORT"
t0=$(now_s)
PGPASSWORD="$POSTGRES_PASSWORD" "$PGBIN/pg_restore" -h 127.0.0.1 -p "$RESTORE_VOL_PORT" -U lab -d lab "$TMP/volume.dump" >>"$LOG" 2>&1
t1=$(now_s)
REST_S=$(echo "$t1 $t0" | awk '{printf "%.1f", $1-$2}')
RES=$(PGPASSWORD="$POSTGRES_PASSWORD" "$PGBIN/psql" -h 127.0.0.1 -p "$RESTORE_VOL_PORT" -U lab -d lab -tAc "SELECT count(*) FROM backup_test")
MOK=$(PGPASSWORD="$POSTGRES_PASSWORD" "$PGBIN/psql" -h 127.0.0.1 -p "$RESTORE_VOL_PORT" -U lab -d lab -tAc "SELECT count(*) FROM lab_marker WHERE marker='$MARKER'")
echo "VOLUME,$DUMP_S,$REST_S,$SRC_ROWS,$RES,$([ "$MOK" -ge 1 ] && echo yes || echo no),$DUMP_MB" >> "$CSV"
say "VOLUME: dump=${DUMP_S}s restore=${REST_S}s rows=${SRC_ROWS}→${RES} marker_ok=$MOK dump=${DUMP_MB}MB"
docker rm -f -v pg-lab-volume-restore >>"$LOG"
docker volume rm pg-lab-volume-restore-data >>"$LOG"

say "=== Backup/restore завершено ==="
column -s, -t "$CSV" | tee -a "$LOG"
