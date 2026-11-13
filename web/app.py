"""Web app de infra-lab: registra cada visita en PostgreSQL y muestra el total."""

import logging
import os

import psycopg
from flask import Flask, jsonify, render_template_string
from psycopg.conninfo import make_conninfo
from psycopg_pool import ConnectionPool

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
logger = logging.getLogger("infra-lab-web")

PAGE = """<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>infra-lab</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 40rem; margin: 4rem auto; padding: 0 1rem; line-height: 1.6; color: #1f2933; background: #f7f9fb; }
    code { background: #e4e7eb; padding: 0.1rem 0.3rem; border-radius: 4px; }
    .visits { font-size: 2.5rem; font-weight: 700; }
  </style>
</head>
<body>
  <h1>infra-lab funciona</h1>
  <p>Visitas registradas en PostgreSQL:</p>
  <p class="visits" id="visits">{{ visits }}</p>
  <p>Recorrido de esta peticion: <code>proxy</code> (Nginx) &rarr; <code>web</code> (Flask) &rarr; <code>db</code> (PostgreSQL, red interna).</p>
</body>
</html>
"""


def _build_conninfo() -> str:
    return make_conninfo(
        host=os.environ.get("DB_HOST", "db"),
        port=os.environ.get("DB_PORT", "5432"),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        connect_timeout=3,
    )


pool = ConnectionPool(_build_conninfo(), min_size=1, max_size=5, open=True)
app = Flask(__name__)


@app.get("/")
def index() -> str:
    with pool.connection() as conn:
        conn.execute("INSERT INTO visits DEFAULT VALUES")
        visits = conn.execute("SELECT count(*) FROM visits").fetchone()[0]
    return render_template_string(PAGE, visits=visits)


@app.get("/health")
def health():
    try:
        with pool.connection(timeout=3) as conn:
            conn.execute("SELECT 1")
    except psycopg.Error:
        logger.exception("Health check: database unreachable")
        return jsonify(status="error", database="unreachable"), 503
    return jsonify(status="ok", database="ok")


@app.errorhandler(psycopg.Error)
def database_error(error: psycopg.Error):
    logger.error("Database error: %s", error)
    return jsonify(status="error", detail="database unavailable"), 503
