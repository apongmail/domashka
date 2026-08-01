#!/usr/bin/env bash
# Створює таблицю lab_marker і вставляє унікальний UUID-маркер.
# Використання: 20_seed_markers.sh [HOST] [LAYER] [VOLUME] [BIND]
# Без аргументів — усі чотири. Маркери зберігаються в results/markers/<VAR>.txt
set -euo pipefail
source "$(dirname "$0")/lib.sh"
mkdir -p "$LAB_ROOT/results/markers"

DDL="CREATE TABLE IF NOT EXISTS lab_marker (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  storage_type text NOT NULL,
  marker uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);"

port_of() { case "$1" in HOST) echo "$HOST_PORT";; LAYER) echo "$LAYER_PORT";; VOLUME) echo "$VOLUME_PORT";; BIND) echo "$BIND_PORT";; esac; }

VARS=("$@"); [ ${#VARS[@]} -eq 0 ] && VARS=(HOST LAYER VOLUME BIND)

for VAR in "${VARS[@]}"; do
  port=$(port_of "$VAR")
  # для HOST база lab вже створена 10_host_up.sh
  marker=$(uuidgen | tr '[:upper:]' '[:lower:]')
  psql_port "$port" -q -c "$DDL" \
    -c "INSERT INTO lab_marker (storage_type, marker) VALUES ('$VAR', '$marker');"
  echo "$marker" > "$LAB_ROOT/results/markers/$VAR.txt"
  echo "$VAR (port $port): marker=$marker"
done
