#!/usr/bin/env bash
# Зупиняє лабораторний нативний кластер (дані в PGDATA лишаються).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
"$PGBIN/pg_ctl" -D "$HOST_PGDATA" stop -m fast
