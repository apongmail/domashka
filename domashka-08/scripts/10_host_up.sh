#!/usr/bin/env bash
# Створює (за потреби) і запускає ОКРЕМИЙ лабораторний кластер PostgreSQL 18
# на macOS: власний PGDATA, нестандартний порт 5499, лише 127.0.0.1,
# без brew services (звичайний локальний процес, не переживає reboot).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [ ! -f "$HOST_PGDATA/PG_VERSION" ]; then
  mkdir -p "$HOST_PGDATA"
  # trust-автентифікація прийнятна ТІЛЬКИ для лабораторії: кластер слухає
  # виключно 127.0.0.1 і живе до кінця експерименту.
  "$PGBIN/initdb" -D "$HOST_PGDATA" --encoding=UTF8 \
    --auth-local=trust --auth-host=trust >/dev/null
  echo "initdb: created $HOST_PGDATA"
fi

if ! "$PGBIN/pg_ctl" -D "$HOST_PGDATA" status >/dev/null 2>&1; then
  "$PGBIN/pg_ctl" -D "$HOST_PGDATA" -l "$LAB_DATA_ROOT/host-postgres.log" \
    -o "-p $HOST_PORT -c listen_addresses=127.0.0.1" start
fi
wait_pg "$HOST_PORT"

# Паритет із контейнерами: роль lab і база lab
psql_host -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='lab'" | grep -q 1 \
  || psql_host -d postgres -c "CREATE ROLE lab LOGIN" >/dev/null
psql_host -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='lab'" | grep -q 1 \
  || psql_host -d postgres -c "CREATE DATABASE lab OWNER lab" >/dev/null

echo "HOST cluster ready on 127.0.0.1:$HOST_PORT (PGDATA=$HOST_PGDATA)"
