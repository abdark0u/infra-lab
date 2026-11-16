FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Parches de Debian posteriores a la imagen base (los marca Trivy) y usuario sin root
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 10001 appuser

# pip solo hace falta para instalar y sus librerías tenían vulnerabilidades: fuera
COPY requirements.txt .
RUN pip install -r requirements.txt \
    && pip uninstall -y pip

COPY app.py .

USER appuser

EXPOSE 8000

# Un solo proceso con hilos: las métricas viven en su memoria y así salen completas
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "1", "--worker-class", "gthread", "--threads", "4", "--access-logfile", "-", "app:app"]
