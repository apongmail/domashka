import os

import psycopg
from flask import Flask

DSN = (
    f"host={os.environ.get('DB_HOST', 'db')} "
    f"dbname={os.environ.get('DB_NAME', 'visits')} "
    f"user={os.environ.get('DB_USER', 'app')} "
    f"password={os.environ.get('DB_PASSWORD', 'secret')}"
)

app = Flask(__name__)

# Підключення на старті навмисно без retry: якщо база ще не готова,
# контейнер має впасти — саме це демонструє цінність healthcheck у compose.
with psycopg.connect(DSN) as conn:
    conn.execute("CREATE TABLE IF NOT EXISTS visits (id serial PRIMARY KEY, ts timestamptz DEFAULT now())")


@app.get("/")
def index():
    with psycopg.connect(DSN) as conn:
        conn.execute("INSERT INTO visits DEFAULT VALUES")
        total = conn.execute("SELECT count(*) FROM visits").fetchone()[0]
    return f"Привіт!! Це візит номер {total}.\n"


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
