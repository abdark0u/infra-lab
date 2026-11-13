"""App web de infra-lab: guarda cada visita en PostgreSQL y enseña el total.

Es sencilla a propósito: lo interesante del proyecto es la infraestructura de
alrededor (proxy, redes internas, monitorización y backups).
"""

import logging
import os
import time

import psycopg
from flask import Flask, Response, g, jsonify, render_template_string, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
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
  <p>Recorrido de esta petición: <code>proxy</code> (Nginx) &rarr; <code>web</code> (Flask) &rarr; <code>db</code> (PostgreSQL, red interna).</p>
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


HTTP_REQUESTS = Counter(
    "infralab_http_requests_total",
    "Peticiones HTTP atendidas por la app",
    ["method", "endpoint", "status"],
)
HTTP_LATENCY = Histogram(
    "infralab_http_request_duration_seconds",
    "Duracion de las peticiones HTTP",
    ["endpoint"],
)
VISITS_RECORDED = Counter(
    "infralab_visits_recorded_total",
    "Visitas guardadas en PostgreSQL desde que arranco el proceso",
)

pool = ConnectionPool(_build_conninfo(), min_size=1, max_size=5, open=True)
app = Flask(__name__)


@app.before_request
def _start_timer() -> None:
    g.request_started = time.perf_counter()


@app.after_request
def _record_metrics(response: Response) -> Response:
    endpoint = request.url_rule.rule if request.url_rule else "unmatched"
    if endpoint == "/metrics":
        return response
    HTTP_REQUESTS.labels(request.method, endpoint, str(response.status_code)).inc()
    started = g.get("request_started")
    if started is not None:
        HTTP_LATENCY.labels(endpoint).observe(time.perf_counter() - started)
    return response


@app.get("/")
def index() -> str:
    with pool.connection() as conn:
        conn.execute("INSERT INTO visits DEFAULT VALUES")
        visits = conn.execute("SELECT count(*) FROM visits").fetchone()[0]
    VISITS_RECORDED.inc()
    return render_template_string(PAGE, visits=visits)


@app.get("/metrics")
def metrics() -> Response:
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


@app.get("/health")
def health():
    try:
        with pool.connection(timeout=3) as conn:
            conn.execute("SELECT 1")
    except psycopg.Error:
        logger.exception("Healthcheck: no se puede conectar con la base de datos")
        return jsonify(status="error", database="unreachable"), 503
    return jsonify(status="ok", database="ok")


@app.errorhandler(psycopg.Error)
def database_error(error: psycopg.Error):
    logger.error("Error de la base de datos: %s", error)
    return jsonify(status="error", detail="database unavailable"), 503
