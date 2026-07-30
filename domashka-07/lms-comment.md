# Коментар для LMS — ДЗ 7

Застосунок — лічильник візитів на Flask + PostgreSQL (~40 рядків Python):
кожен GET додає рядок у таблицю і повертає номер візиту, час запису
(проставляє сам Postgres) і скільки секунд минуло з попереднього візиту.

## Dockerfile

```dockerfile
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8000

CMD ["python", "app.py"]
```

Exec-форма CMD (сигнали доходять до PID 1, `docker stop` миттєвий),
залежності копіюються окремо від коду, `.dockerignore` ріже контекст
збірки до 1.50 кБ.

## compose.yaml

```yaml
services:
  app:
    build: ./app
    ports:
      - "8007:8000"
    environment:
      DB_HOST: db          # звернення за іменем сервіса
      DB_NAME: visits
      DB_USER: app
      DB_PASSWORD: secret
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:17-alpine
    environment:
      POSTGRES_DB: visits
      POSTGRES_USER: app
      POSTGRES_PASSWORD: secret
    volumes:
      - db-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app -d visits"]
      interval: 2s
      timeout: 2s
      retries: 10

volumes:
  db-data:
```

Том перевірено: після `docker compose down && up` лічильник продовжує
з того ж числа.

## Час збірок (ефект кешу)

- **1-ша збірка:** 5.61 с (з них `pip install` — 4.3 с)
- **2-га збірка** (змінено один символ у `app.py`): **0.84 с** — шари до
  `pip install` включно взяті з кешу (CACHED), перевиконано лише
  `COPY app.py`

Різниця — бо Docker кешує пошарово: `requirements.txt` не змінився, тому
найдорожчий шар із залежностями перевикористано. Якби код копіювався
одним `COPY . .` до `pip install`, один символ інвалідовував би й
установку залежностей.

## Що зламалось у пункті 4 й чому

Прибрав healthcheck — вийшло два сценарії. Якщо лишити
`condition: service_healthy`, compose взагалі відмовляється стартувати
app: `dependency failed to start: container ... has no healthcheck
configured` — умова нездійсненна. Якщо спростити до `depends_on: [db]`,
поломка підступніша: compose гарантує лише порядок **запуску** контейнерів,
а не готовність Postgres усередині, тому на чистому томі (initdb триває
кілька секунд) app падає з `Connection refused` — контейнер бази вже
«Up», а сам сервер ще не слухає порт. Найгірше, що це гонка: на
прогрітому томі та сама конфігурація «іноді працює». Healthcheck з
`pg_isready` перетворює її на детермінований порядок — після повернення
app стартує після `db … Healthy` і підключається з першої спроби.

Окремо опублікував порт бази (`5432:5432`): з хоста одразу заходить
`psql` з паролем зі compose-файла. Робити так не варто — єдиний клієнт
бази (app) ходить у неї внутрішньою мережею compose за іменем сервіса,
а публікація лише відкриває базу хостові й локальній мережі повз усю
логіку застосунку, плюс провокує конфлікти портів (8000 на моєму хості
вже був зайнятий — довелось публікувати app на 8007).

**Повний звіт:**
https://github.com/apongmail/domashka/blob/main/domashka-07/report_domashka-07.md

**PDF:**
https://github.com/apongmail/domashka/blob/main/domashka-07/report_domashka-07.pdf

Код, compose-файли та повні логи експериментів — у `domashka-07/`
(`app/`, `compose.yaml`, `compose.broken.yaml`, `docs/`).
