# infra-lab

[![CI](https://github.com/abdark0u/infra-lab/actions/workflows/ci.yml/badge.svg)](https://github.com/abdark0u/infra-lab/actions/workflows/ci.yml)

Laboratorio de infraestructura con **Docker Compose**: un proxy inverso Nginx delante de una web,
una base de datos aislada en red interna, monitorizacion con Prometheus + Grafana y un script de
backup con rotacion.

Proyecto de portfolio construido paso a paso; cada fase queda reflejada en el historial de commits.

## Arquitectura (objetivo)

```
             Internet / localhost:8080
                        |
                  +-----------+
                  |   proxy   |  Nginx (unico puerto publicado)
                  +-----------+
                        |            red: frontend
                  +-----------+
                  |    web    |
                  +-----------+
                        |            red: backend (internal: sin salida a Internet)
                  +-----------+
                  |    db     |
                  +-----------+

  prometheus  ->  grafana          red: monitoring
  backup.sh   ->  dump de db con rotacion
```

## Hoja de ruta

- [x] Fase 1: proxy inverso Nginx + web estatica
- [ ] Fase 2: base de datos en red interna
- [ ] Fase 3: Prometheus + Grafana
- [ ] Fase 4: script de backup con rotacion
- [x] CI: smoke test automatico en GitHub Actions
- [ ] Fase 5: healthchecks, Makefile y documentacion final

## Requisitos

- Docker y Docker Compose v2 (`docker compose version`)

## Puesta en marcha

```bash
cp .env.example .env
docker compose up -d
```

Abre <http://localhost:8080>. Comprobacion de salud del proxy: <http://localhost:8080/healthz>.

Parar todo:

```bash
docker compose down
```

## Integracion continua

Cada push a `main` ejecuta [`.github/workflows/ci.yml`](.github/workflows/ci.yml) en GitHub Actions,
que levanta el stack en un runner limpio y comprueba que:

- `docker-compose.yml` es valido
- la configuracion de Nginx pasa `nginx -t`
- el proxy responde en `/healthz`
- la web llega a traves del proxy
- la web **no** publica puertos al exterior (solo el proxy lo hace)

## Estructura

```
.
├── .github/workflows/
│   └── ci.yml          # smoke test en GitHub Actions
├── docker-compose.yml
├── .env.example        # plantilla de variables (el .env real no se sube)
├── proxy/
│   └── default.conf    # configuracion del proxy inverso
└── web/
    └── html/
        └── index.html
```
