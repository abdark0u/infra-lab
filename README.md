# infra-lab

[![CI](https://github.com/abdark0u/infra-lab/actions/workflows/ci.yml/badge.svg)](https://github.com/abdark0u/infra-lab/actions/workflows/ci.yml)

Laboratorio de infraestructura con **Docker Compose**: un proxy inverso Nginx delante de una web,
una base de datos aislada en red interna, monitorizacion con Prometheus + Grafana y un script de
backup con rotacion.

Proyecto de portfolio construido paso a paso; cada fase queda reflejada en el historial de commits.

## Arquitectura

```
                       Internet / localhost:8080
                                  |
                           +-------------+
                           |    proxy    |   Nginx: unico puerto publicado
                           +-------------+
                       /            |            \
                  "/"          "/grafana/"     :8081/stub_status
                     |              |              |
                +---------+   +-----------+   +----------------+
                |   web   |   |  grafana  |   | nginx-exporter |
                +---------+   +-----------+   +----------------+
                  |     |           |                  |
                  |     |      consultas               |
                  |     |           v                  |
                  |     +----> +------------+ <--------+
                  |  /metrics  | prometheus |
                  |            +------------+ <--------+
                  v                                    |
                +---------+   +-------------------+    |
                |   db    | <-| postgres-exporter |----+
                +---------+   +-------------------+

  Redes:  frontend   -> proxy, web, grafana, nginx-exporter
          backend    -> web, db, postgres-exporter                 (internal)
          monitoring -> prometheus, grafana, web, ambos exporters  (internal)

  backup.sh  ->  dump de db con rotacion   (fase 4)
```

| Servicio | Imagen | Redes | Puerto publicado |
|----------|--------|-------|------------------|
| `proxy` | `nginx:1.27-alpine` | frontend | `8080` -> 80 |
| `web` | build propio (`python:3.13-slim`) | frontend, backend, monitoring | ninguno |
| `db` | `postgres:17-alpine` | backend | ninguno |
| `prometheus` | `prom/prometheus:v3.5.0` | monitoring | ninguno |
| `grafana` | `grafana/grafana:12.1.1` | frontend, monitoring | ninguno (via proxy en `/grafana/`) |
| `nginx-exporter` | `nginx/nginx-prometheus-exporter:1.4.2` | frontend, monitoring | ninguno |
| `postgres-exporter` | `prometheuscommunity/postgres-exporter:v0.17.1` | backend, monitoring | ninguno |

### Decisiones de diseno

- **Una sola puerta de entrada**: solo el proxy publica un puerto; `web` y `db` no son accesibles
  desde el host.
- **Red `backend` con `internal: true`**: la base de datos no tiene salida a Internet y el proxy no
  puede verla, porque no comparten red. Solo `web` esta en las dos redes.
- **Arranque ordenado con healthchecks**: `db` (`pg_isready`) -> `web` (`/health`, que consulta la
  base de datos) -> `proxy`. Cada servicio espera a que el anterior este sano.
- **Secretos fuera del repo**: las credenciales viven en `.env` (ignorado por git); `.env.example`
  es solo la plantilla. Compose falla al arrancar si falta `POSTGRES_PASSWORD`.
- **Contenedor de la app sin root**: la imagen de `web` ejecuta Gunicorn con un usuario sin
  privilegios.
- **Monitorizacion en su propia red interna**: Prometheus solo esta en `monitoring`, asi que ni se
  publica ni lo alcanza el proxy. Grafana es lo unico de monitorizacion que se sirve hacia fuera, y
  lo hace a traves del proxy en `/grafana/`.
- **`/metrics` no se expone**: el proxy devuelve `404` en `/metrics`; Prometheus lee las metricas
  de la app directamente por la red `monitoring`.
- **Todo como codigo**: el datasource y el dashboard de Grafana se cargan por *provisioning* desde
  el repo, y las alertas de Prometheus viven en
  [`monitoring/prometheus/alerts.yml`](monitoring/prometheus/alerts.yml).

## Monitorizacion

Prometheus recoge metricas cada 15 s de cuatro fuentes:

| Job | Origen | Ejemplos de metricas |
|-----|--------|----------------------|
| `web` | `/metrics` de la app (`prometheus_client`) | `infralab_http_requests_total`, `infralab_http_request_duration_seconds`, `infralab_visits_recorded_total` |
| `nginx` | `stub_status` de Nginx via `nginx-exporter` | `nginx_http_requests_total`, `nginx_connections_active` |
| `postgres` | PostgreSQL via `postgres-exporter` | `pg_up`, `pg_database_size_bytes` |
| `prometheus` | el propio Prometheus | `up`, `prometheus_tsdb_*` |

El dashboard **infra-lab - Overview** (carpeta `infra-lab` en Grafana) muestra el estado de cada
servicio, peticiones por segundo y latencia p95 de la app, trafico de Nginx y tamano de la base
de datos.

Reglas de alerta definidas (visibles en Prometheus, pestana *Alerts*):

| Alerta | Condicion |
|--------|-----------|
| `TargetDown` | algun servicio deja de responder a Prometheus durante 1 min |
| `PostgresDown` | `postgres-exporter` no puede conectar con la base de datos durante 1 min |
| `AppHighErrorRate` | mas del 5 % de respuestas 5xx durante 5 min |
| `AppHighLatency` | latencia p95 por encima de 500 ms durante 5 min |

Para abrir la interfaz de Prometheus (no esta publicada) se puede usar un tunel temporal:

```bash
docker run --rm -it --network infra-lab-monitoring -p 9090:9090 alpine/socat TCP-LISTEN:9090,fork TCP:prometheus:9090
```

## Hoja de ruta

- [x] Fase 1: proxy inverso Nginx + web
- [x] CI: smoke test automatico en GitHub Actions
- [x] Fase 2: base de datos PostgreSQL en red interna + app con contador de visitas
- [x] Fase 3: Prometheus + Grafana con dashboard y alertas como codigo
- [ ] Fase 4: script de backup con rotacion
- [ ] Fase 5: Makefile y documentacion final

## Requisitos

- Docker y Docker Compose v2 (`docker compose version`)

## Puesta en marcha

```bash
cp .env.example .env      # y cambia las contrasenas
docker compose up -d --build --wait
```

| URL | Que es |
|-----|--------|
| <http://localhost:8080> | La web: cada visita se guarda en PostgreSQL |
| <http://localhost:8080/grafana/> | Grafana (usuario y contrasena de `.env`) |
| <http://localhost:8080/health> | Salud de la app y de su conexion a la base de datos |
| <http://localhost:8080/healthz> | Salud del propio proxy |

Parar todo (los datos se conservan en el volumen `infra-lab-db-data`):

```bash
docker compose down
```

Borrar tambien los datos:

```bash
docker compose down --volumes
```

## Integracion continua

Cada push a `main` ejecuta [`.github/workflows/ci.yml`](.github/workflows/ci.yml) en GitHub Actions,
que construye y levanta el stack en un runner limpio y comprueba que:

- `docker-compose.yml` es valido, Nginx pasa `nginx -t` y Prometheus pasa `promtool check config`
  (incluidas las reglas de alerta)
- todos los servicios llegan a estado `healthy`
- el proxy responde en `/healthz` y la app en `/health` con la base de datos accesible
- cada visita a la web se guarda en PostgreSQL
- los datos sobreviven a un `docker compose down` + `up` (volumen persistente)
- `/metrics` devuelve `404` desde fuera
- Prometheus tiene sus 4 targets en `up` y recibe metricas de la app, Nginx y PostgreSQL
- Grafana responde a traves del proxy, su datasource conecta con Prometheus y el dashboard esta
  cargado
- las redes `backend` y `monitoring` son internas y el proxy **no** puede resolver ni la base de
  datos ni Prometheus
- ningun servicio salvo el proxy publica puertos

## Estructura

```
.
├── .github/workflows/
│   └── ci.yml              # smoke test en GitHub Actions
├── docker-compose.yml
├── .env.example            # plantilla de variables (el .env real no se sube)
├── proxy/
│   └── default.conf        # configuracion del proxy inverso
├── web/
│   ├── Dockerfile          # imagen de la app (usuario sin root)
│   ├── app.py              # Flask: contador de visitas + /health + /metrics
│   └── requirements.txt
├── db/
│   └── init/
│       └── 01-schema.sql   # esquema inicial (se ejecuta solo con el volumen vacio)
└── monitoring/
    ├── prometheus/
    │   ├── prometheus.yml  # targets a monitorizar
    │   └── alerts.yml      # reglas de alerta
    └── grafana/
        ├── provisioning/   # datasource y proveedor de dashboards
        └── dashboards/
            └── infra-lab-overview.json
```
