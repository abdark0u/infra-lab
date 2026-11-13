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
                  +-----------+
                  |   proxy   |  Nginx (unico puerto publicado)
                  +-----------+
                        |            red: frontend
                  +-----------+
                  |    web    |  Python + Flask + Gunicorn
                  +-----------+
                        |            red: backend (internal: sin salida a Internet)
                  +-----------+
                  |    db     |  PostgreSQL 17 + volumen persistente
                  +-----------+

  prometheus  ->  grafana          red: monitoring   (fase 3)
  backup.sh   ->  dump de db con rotacion           (fase 4)
```

| Servicio | Imagen | Redes | Puerto publicado |
|----------|--------|-------|------------------|
| `proxy` | `nginx:1.27-alpine` | frontend | `8080` -> 80 |
| `web` | build propio (`python:3.13-slim`) | frontend, backend | ninguno |
| `db` | `postgres:17-alpine` | backend | ninguno |

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

## Hoja de ruta

- [x] Fase 1: proxy inverso Nginx + web
- [x] CI: smoke test automatico en GitHub Actions
- [x] Fase 2: base de datos PostgreSQL en red interna + app con contador de visitas
- [ ] Fase 3: Prometheus + Grafana
- [ ] Fase 4: script de backup con rotacion
- [ ] Fase 5: Makefile y documentacion final

## Requisitos

- Docker y Docker Compose v2 (`docker compose version`)

## Puesta en marcha

```bash
cp .env.example .env      # y cambia POSTGRES_PASSWORD
docker compose up -d --build --wait
```

| URL | Que es |
|-----|--------|
| <http://localhost:8080> | La web: cada visita se guarda en PostgreSQL |
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

- `docker-compose.yml` es valido y la configuracion de Nginx pasa `nginx -t`
- todos los servicios llegan a estado `healthy`
- el proxy responde en `/healthz` y la app en `/health` con la base de datos accesible
- cada visita a la web se guarda en PostgreSQL
- los datos sobreviven a un `docker compose down` + `up` (volumen persistente)
- la red `backend` es interna y el proxy **no** puede resolver la base de datos
- `web` y `db` **no** publican puertos (solo el proxy lo hace)

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
│   ├── app.py              # Flask: contador de visitas + /health
│   └── requirements.txt
└── db/
    └── init/
        └── 01-schema.sql   # esquema inicial (se ejecuta solo con el volumen vacio)
```
