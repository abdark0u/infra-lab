FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Aplico los parches de seguridad de Debian que han salido después de la imagen base
# (Trivy los detecta con `make scan`) y creo un usuario sin privilegios: la app no
# necesita root, así que no lo tiene (mínimo privilegio).
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 10001 appuser

# pip solo hace falta para instalar las dependencias, así que luego lo desinstalo:
# las librerías que lleva dentro tenían vulnerabilidades y en la imagen final sobra.
COPY requirements.txt .
RUN pip install -r requirements.txt \
    && pip uninstall -y pip

COPY app.py .

USER appuser

EXPOSE 8000

# Un solo proceso con varios hilos: las métricas de prometheus_client viven en la
# memoria del proceso, y así /metrics siempre devuelve los totales completos.
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "1", "--worker-class", "gthread", "--threads", "4", "--access-logfile", "-", "app:app"]
