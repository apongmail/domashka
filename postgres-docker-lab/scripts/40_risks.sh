#!/usr/bin/env bash
# Демонстрація ризиків конфігурації → results/risks.log
# Використовує ТІЛЬКИ тимчасові ресурси з префіксом pg-lab-, прибирає за собою.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
LOG="$LAB_ROOT/results/risks.log"
: > "$LOG"
say() { echo -e "$*" | tee -a "$LOG"; }
run() { echo "\$ $*" | tee -a "$LOG"; "$@" 2>&1 | tee -a "$LOG"; }

# Ідемпотентність: прибрати залишки попередніх запусків демо
docker rm -f -v pg-lab-wrongmount pg-lab-permdemo pg-lab-wrongpath >/dev/null 2>&1 || true
docker volume rm pg-lab-wrongmount-data >/dev/null 2>&1 || true

PGENV=(-e POSTGRES_USER=lab -e POSTGRES_DB=lab -e "POSTGRES_PASSWORD=$POSTGRES_PASSWORD")
DEMO_PORT=5436
psql_demo() { PGPASSWORD="$POSTGRES_PASSWORD" "$PGBIN/psql" -h 127.0.0.1 -p $DEMO_PORT -U lab -d lab "$@"; }
wait_demo() { wait_pg $DEMO_PORT; }

say "############################################################"
say "# Ризик 1а. Legacy mount point /var/lib/postgresql/data (звичка з PG<=17)"
say "# postgres:18 детектить це і ВІДМОВЛЯЄТЬСЯ стартувати (fail-fast)."
say "############################################################"
docker run -d --name pg-lab-wrongmount "${PGENV[@]}" \
  -p 127.0.0.1:$DEMO_PORT:5432 \
  -v pg-lab-wrongmount-data:/var/lib/postgresql/data postgres:18.4 >>"$LOG"
sleep 5
say "-- Статус контейнера:"
docker ps -a --filter name=pg-lab-wrongmount --format '{{.Status}}' | tee -a "$LOG"
say "-- Ключові рядки помилки entrypoint:"
docker logs pg-lab-wrongmount 2>&1 | grep -E "^Error|Counter to that|/var/lib/postgresql/data|single mount|pull/1259" | tee -a "$LOG"
run docker rm -f -v pg-lab-wrongmount
run docker volume rm pg-lab-wrongmount-data

say ""
say "############################################################"
say "# Ризик 1б. 'Тиха' версія тієї ж помилки: named volume на шляху,"
say "# який PGDATA не є (/var/lib/pgsql — typo). Контейнер стартує без помилок,"
say "# але БД живе в АНОНІМНОМУ volume (оголошений VOLUME образу), а не в named."
say "############################################################"
docker run -d --name pg-lab-wrongmount "${PGENV[@]}" \
  -p 127.0.0.1:$DEMO_PORT:5432 \
  -v pg-lab-wrongmount-data:/var/lib/pgsql postgres:18.4 >>"$LOG"
wait_demo
say "-- Реальний data_directory:"
psql_demo -tAc "SHOW data_directory" | tee -a "$LOG"
psql_demo -q -c "CREATE TABLE lab_marker(id int, marker uuid); INSERT INTO lab_marker VALUES (1, '$(uuidgen | tr A-Z a-z)');"
say "-- Mounts контейнера (named volume — на /var/lib/pgsql, АНОНІМНИЙ — на /var/lib/postgresql):"
docker inspect pg-lab-wrongmount --format '{{range .Mounts}}{{.Type}} {{slice .Name 0 12}} -> {{.Destination}}{{"\n"}}{{end}}' | tee -a "$LOG"
say "-- Видаляємо контейнер (rm -f -v: анонімний volume гине разом із ним) і створюємо знову з ТИМ ЖЕ named volume:"
run docker rm -f -v pg-lab-wrongmount
docker run -d --name pg-lab-wrongmount "${PGENV[@]}" \
  -p 127.0.0.1:$DEMO_PORT:5432 \
  -v pg-lab-wrongmount-data:/var/lib/pgsql postgres:18.4 >>"$LOG"
wait_demo
say "-- Чи збереглась таблиця lab_marker, попри 'підключений volume'?"
psql_demo -tAc "SELECT to_regclass('lab_marker') IS NOT NULL" | tee -a "$LOG"
say "ВИСНОВОК: дані жили в анонімному volume і втрачені, попри підключений named volume."
run docker rm -f -v pg-lab-wrongmount
run docker volume rm pg-lab-wrongmount-data

say ""
say "############################################################"
say "# Ризик 2. Права доступу на bind mount (без chmod 777)"
say "# Каталог macOS з правами r-x (555) → PostgreSQL не може писати."
say "############################################################"
PERM_DIR="$LAB_DATA_ROOT/pg-lab-perm-demo"
mkdir -p "$PERM_DIR"; chmod 555 "$PERM_DIR"
say "-- Права на каталозі: $(ls -ld "$PERM_DIR" | awk '{print $1}')"
docker run -d --name pg-lab-permdemo "${PGENV[@]}" \
  -v "$PERM_DIR":/var/lib/postgresql postgres:18.4 >>"$LOG" || true
sleep 6
say "-- Статус контейнера і останні логи:"
docker ps -a --filter name=pg-lab-permdemo --format '{{.Status}}' | tee -a "$LOG"
docker logs pg-lab-permdemo 2>&1 | tail -5 | tee -a "$LOG"
say "-- ПРАВИЛЬНЕ виправлення: chmod 700 власнику (НЕ 777):"
run docker rm -f -v pg-lab-permdemo
chmod 700 "$PERM_DIR"
docker run -d --name pg-lab-permdemo "${PGENV[@]}" \
  -v "$PERM_DIR":/var/lib/postgresql postgres:18.4 >>"$LOG"
sleep 8
say "-- Статус після виправлення прав:"
docker ps -a --filter name=pg-lab-permdemo --format '{{.Status}}' | tee -a "$LOG"
run docker rm -f -v pg-lab-permdemo
rm -rf "$PERM_DIR"

say ""
say "############################################################"
say "# Ризик 3. Bind mount прив'язаний до конкретного шляху macOS"
say "# Опечатка в шляху → Docker мовчки створює ПОРОЖНІЙ каталог,"
say "# PostgreSQL ініціалізує НОВИЙ кластер — виглядає як втрата даних."
say "############################################################"
TYPO_DIR="$LAB_DATA_ROOT/bind-pgdataTYPO"
say "-- 'Помилковий' шлях: $TYPO_DIR (не існує)"
docker run -d --name pg-lab-wrongpath "${PGENV[@]}" \
  -p 127.0.0.1:$DEMO_PORT:5432 \
  -v "$TYPO_DIR":/var/lib/postgresql postgres:18.4 >>"$LOG"
wait_demo
say "-- Кластер стартував 'з нуля'. Таблиця lab_marker з реального BIND-кластера:"
psql_demo -tAc "SELECT to_regclass('lab_marker') IS NOT NULL" | tee -a "$LOG"
say "-- Docker створив каталог сам: $(ls -ld "$TYPO_DIR" | awk '{print $1, $NF}')"
say "ВИСНОВОК: жодної помилки не було — просто порожня база. Класична пастка bind mount."
run docker rm -f -v pg-lab-wrongpath
rm -rf "$TYPO_DIR"

say ""
say "=== Демонстрації ризиків завершено, тимчасові ресурси прибрано ==="
