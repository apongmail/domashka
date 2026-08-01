# Спільні змінні лабораторії. Підключається через: source "$(dirname "$0")/lib.sh"
PGBIN=/opt/homebrew/opt/postgresql@18/bin
LAB_DATA_ROOT="$HOME/pg-lab-data"
HOST_PGDATA="$LAB_DATA_ROOT/host-pgdata"
BIND_DIR="$LAB_DATA_ROOT/bind-pgdata"

HOST_PORT=5499
LAYER_PORT=5433
VOLUME_PORT=5434
BIND_PORT=5435

# Підключення: HOST — trust для локального лабораторного кластера;
# контейнери — користувач lab із паролем з .env.
LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$LAB_ROOT/.env" ] && set -a && . "$LAB_ROOT/.env" && set +a

psql_host()   { "$PGBIN/psql" -h 127.0.0.1 -p "$HOST_PORT"   -U "$(whoami)" "$@"; }
psql_layer()  { PGPASSWORD="$POSTGRES_PASSWORD" "$PGBIN/psql" -h 127.0.0.1 -p "$LAYER_PORT"  -U lab -d lab "$@"; }
psql_volume() { PGPASSWORD="$POSTGRES_PASSWORD" "$PGBIN/psql" -h 127.0.0.1 -p "$VOLUME_PORT" -U lab -d lab "$@"; }
psql_bind()   { PGPASSWORD="$POSTGRES_PASSWORD" "$PGBIN/psql" -h 127.0.0.1 -p "$BIND_PORT"   -U lab -d lab "$@"; }

# psql до довільного порту: psql_port 5434 -c "..."
psql_port() {
  local port=$1; shift
  if [ "$port" = "$HOST_PORT" ]; then
    "$PGBIN/psql" -h 127.0.0.1 -p "$port" -U "$(whoami)" -d lab "$@"
  else
    PGPASSWORD="$POSTGRES_PASSWORD" "$PGBIN/psql" -h 127.0.0.1 -p "$port" -U lab -d lab "$@"
  fi
}

# Чекати готовності PostgreSQL на порту (до 60 с)
wait_pg() {
  local port=$1 i=0
  until "$PGBIN/pg_isready" -h 127.0.0.1 -p "$port" -q; do
    i=$((i+1)); [ $i -gt 120 ] && echo "ERROR: PostgreSQL on :$port not ready" >&2 && return 1
    sleep 0.5
  done
}
