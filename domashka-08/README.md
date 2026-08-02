# pg-lab: PostgreSQL на macOS проти Docker Desktop

Лабораторна робота: як спосіб зберігання даних PostgreSQL (native macOS,
writable layer, named volume, bind mount) впливає на збереження даних при
життєвому циклі контейнера, на продуктивність і на операційні ризики.

Повний звіт: [`report_domashka-08.md`](report_domashka-08.md) ·
PDF: [`report_domashka-08.pdf`](report_domashka-08.pdf)

## Чотири конфігурації

| Варіант | Де живе PGDATA | Порт |
|---|---|---:|
| `HOST` | окремий кластер PostgreSQL 18.4 (Homebrew) у `~/pg-lab-data/host-pgdata` | 5499 |
| `LAYER` | writable layer контейнера (`PGDATA=/pgdata`, поза VOLUME образу) | 5433 |
| `VOLUME` | named volume `pg-lab-volume-data` → `/var/lib/postgresql` | 5434 |
| `BIND` | bind mount `~/pg-lab-data/bind-pgdata` → `/var/lib/postgresql` | 5435 |

Образ: `postgres:18.4`
(digest `sha256:3a82e1f56c8f0f5616a11103ac3d47e632c3938698946a7ad26da0df1334744a`, arm64).
Native: PostgreSQL 18.4 (Homebrew). Використовується однакова версія та
заводська конфігурація скрізь; `fsync`, `full_page_writes`,
`synchronous_commit` не вимикались.

## Використання

```bash
cp .env.example .env            # заповнити пароль і шлях bind-каталогу
./scripts/10_host_up.sh         # нативний лабораторний кластер (initdb + start)
docker compose up -d            # три контейнерні варіанти
./scripts/00_inventory.sh       # інвентаризація середовища → results/
./scripts/30_lifecycle.sh       # матриця збереження даних → results/lifecycle.csv
./scripts/40_risks.sh           # демонстрації ризиків → results/risks.log
./scripts/45_backup_restore.sh  # pg_dump/pg_restore HOST і VOLUME → results/
./scripts/50_benchmark.sh HOST  # pgbench одного варіанта (аналогічно LAYER/VOLUME/BIND)
python3 scripts/60_charts.py    # графіки → results/charts/*.svg
```

Скрипти ідемпотентні; всі лабораторні ресурси мають префікс `pg-lab-`
і не зачіпають інші контейнери/кластери на машині.

## Структура

```text
domashka-08/
├── compose.yaml            # три Docker-варіанти (відрізняються лише сховищем)
├── .env.example
├── scripts/                # інвентаризація, lifecycle, ризики, backup, benchmark, графіки
├── results/                # виміри: csv, логи, графіки
│   ├── benchmark.csv
│   └── charts/
├── report_domashka-08.md   # звіт українською
└── report_domashka-08.pdf
```

## Головні висновки (докладно у звіті)

- **Writable layer для БД непридатний**: будь-яке видалення контейнера
  (`docker rm`, `compose down`) знищує дані.
- **Named volume — рекомендований Docker-варіант**; гине лише від явного
  `docker compose down -v` / `docker volume rm`.
- **postgres:18 змінив розкладку**: `PGDATA=/var/lib/postgresql/18/docker`,
  монтувати треба `/var/lib/postgresql`; legacy-mount на `.../data` образ
  тепер відхиляє на старті (fail-fast).
- **На macOS клієнтський трафік до контейнера проходить крізь проксі
  Docker Desktop VM** — на 1 клієнті це коштує ~8× TPS проти native;
  на 32 клієнтах розрив звужується.
- **Volume ≠ backup**: перевірений `pg_dump` → `pg_restore` — єдиний
  спосіб мати відновлювану копію.
