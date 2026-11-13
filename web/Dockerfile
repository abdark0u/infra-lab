FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Parches de seguridad de Debian publicados despues de la imagen base
# (Trivy los detecta con `make scan`) y usuario sin privilegios para la app
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 10001 appuser

# pip solo hace falta para instalar las dependencias: se desinstala para que no
# quede en la imagen final (las librerias que lleva dentro tenian vulnerabilidades)
COPY requirements.txt .
RUN pip install -r requirements.txt \
    && pip uninstall -y pip

COPY app.py .

USER appuser

EXPOSE 8000

# Un solo proceso con varios hilos: las metricas de prometheus_client viven en memoria
# del proceso, asi /metrics siempre devuelve los totales completos.
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "1", "--worker-class", "gthread", "--threads", "4", "--access-logfile", "-", "app:app"]
