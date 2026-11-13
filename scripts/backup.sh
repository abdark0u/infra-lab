#!/usr/bin/env bash
# Backup de la base de datos PostgreSQL de infra-lab, con rotación.
#
# Hace un volcado con pg_dump (formato custom), comprueba que se puede leer,
# guarda su checksum SHA-256 y borra los backups más antiguos que sobren.
# Un backup que no has comprobado no es un backup, por eso lo verifico antes de
# darlo por bueno.
#
# Uso: scripts/backup.sh [-d DIR] [-k N] [-h]
#
# Ejemplo en cron (todos los días a las 03:00):
#   0 3 * * * /ruta/a/infra-lab/scripts/backup.sh >> /ruta/a/infra-lab/backups/backup.log 2>&1
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly SCRIPT_DIR PROJECT_DIR
readonly BACKUP_PREFIX="infralab"

backup_dir="${BACKUP_DIR:-$PROJECT_DIR/backups}"
keep="${BACKUP_KEEP:-7}"
lock_dir=""
partial_file=""

log() {
    local level=$1
    shift
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >&2
}

die() {
    log ERROR "$@"
    exit 1
}

usage() {
    cat <<EOF
Uso: $(basename "$0") [-d DIR] [-k N] [-h]

  -d DIR  Carpeta donde guardar los backups (por defecto: \$BACKUP_DIR o backups/)
  -k N    Numero de backups a conservar (por defecto: \$BACKUP_KEEP o 7)
  -h      Muestra esta ayuda
EOF
}

cleanup() {
    if [[ -n "$partial_file" ]]; then
        rm -f -- "$partial_file"
    fi
    if [[ -n "$lock_dir" ]]; then
        rmdir -- "$lock_dir" 2>/dev/null || true
    fi
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

require_running_db() {
    command -v docker >/dev/null 2>&1 || die "No se encuentra el comando docker"
    if ! docker compose ps --status running --services | grep -qx db; then
        die "El servicio db no esta en marcha (docker compose up -d)"
    fi
}

acquire_lock() {
    # mkdir es atómico: si la carpeta ya existe es que hay otro backup en marcha
    if ! mkdir -- "$backup_dir/.backup.lock" 2>/dev/null; then
        die "Ya hay un backup en curso (existe $backup_dir/.backup.lock)"
    fi
    lock_dir="$backup_dir/.backup.lock"
}

dump_database() {
    local target=$1
    # Comillas simples a propósito: las variables se expanden dentro del contenedor, no en el host
    # shellcheck disable=SC2016
    docker compose exec -T db sh -c \
        'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --no-owner' > "$target"
}

verify_dump() {
    local file=$1
    [[ -s "$file" ]] || die "El backup esta vacio: $file"
    docker compose exec -T db pg_restore --list < "$file" > /dev/null \
        || die "pg_restore no puede leer el backup: $file"
}

rotate_backups() {
    local old
    # El nombre lleva la fecha en un formato ordenable: orden alfabético = orden cronológico
    find "$backup_dir" -maxdepth 1 -type f -name "${BACKUP_PREFIX}_*.dump" \
        | sort -r \
        | tail -n "+$((keep + 1))" \
        | while IFS= read -r old; do
            rm -f -- "$old" "$old.sha256"
            log INFO "Rotacion: eliminado $(basename "$old")"
        done
}

main() {
    local opt
    while getopts ":d:k:h" opt; do
        case $opt in
            d) backup_dir=$OPTARG ;;
            k) keep=$OPTARG ;;
            h) usage; exit 0 ;;
            :) usage >&2; die "La opcion -$OPTARG necesita un valor" ;;
            *) usage >&2; die "Opcion no valida: -$OPTARG" ;;
        esac
    done

    [[ "$keep" =~ ^[1-9][0-9]*$ ]] || die "-k debe ser un entero mayor que 0 (recibido: $keep)"
    [[ "$backup_dir" == /* ]] || backup_dir="$PWD/$backup_dir"

    cd "$PROJECT_DIR"
    require_running_db

    # Los backups llevan datos de la base de datos: permisos 600, que solo los lea quien los crea
    umask 077
    mkdir -p -- "$backup_dir"
    trap cleanup EXIT
    acquire_lock

    local timestamp backup_file
    timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
    backup_file="$backup_dir/${BACKUP_PREFIX}_${timestamp}.dump"
    [[ ! -e "$backup_file" ]] || die "Ya existe un backup con ese nombre: $backup_file"

    log INFO "Creando backup $(basename "$backup_file")"
    partial_file="$backup_file.partial"
    dump_database "$partial_file"
    verify_dump "$partial_file"
    mv -- "$partial_file" "$backup_file"
    partial_file=""

    printf '%s  %s\n' "$(sha256_of "$backup_file")" "$(basename "$backup_file")" > "$backup_file.sha256"

    rotate_backups

    local size remaining
    size="$(du -h "$backup_file" | cut -f1)"
    remaining="$(find "$backup_dir" -maxdepth 1 -type f -name "${BACKUP_PREFIX}_*.dump" | wc -l | tr -d ' ')"
    log INFO "Backup completado: $backup_file ($size). Backups conservados: $remaining/$keep"
}

main "$@"
