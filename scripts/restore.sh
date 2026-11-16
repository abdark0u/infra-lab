#!/usr/bin/env bash
# Restaura un backup de backup.sh en una sola transacción: si falla, la db queda como estaba.
# Ojo: el checksum detecta corrupción, no a alguien que cambie también el .sha256.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly SCRIPT_DIR PROJECT_DIR
readonly BACKUP_PREFIX="infralab"

backup_dir="${BACKUP_DIR:-$PROJECT_DIR/backups}"
assume_yes=false

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
Uso: $(basename "$0") [-y] [-d DIR] <archivo.dump | latest>

  latest  Usa el backup mas reciente de DIR
  -d DIR  Carpeta de backups para "latest" (por defecto: \$BACKUP_DIR o backups/)
  -y      No pedir confirmacion (para scripts y CI)
  -h      Muestra esta ayuda
EOF
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

latest_backup() {
    find "$backup_dir" -maxdepth 1 -type f -name "${BACKUP_PREFIX}_*.dump" | sort | tail -n 1
}

verify_checksum() {
    local file=$1 expected actual
    if [[ ! -f "$file.sha256" ]]; then
        log WARN "No hay checksum para $(basename "$file"); se restaura sin verificarlo"
        return 0
    fi
    expected="$(cut -d' ' -f1 < "$file.sha256")"
    actual="$(sha256_of "$file")"
    [[ "$expected" == "$actual" ]] || die "El checksum no coincide: el backup esta danado"
    log INFO "Checksum SHA-256 correcto"
}

confirm() {
    local answer
    if [[ "$assume_yes" == true ]]; then
        return 0
    fi
    [[ -t 0 ]] || die "Sin terminal interactiva: usa -y para confirmar la restauracion"
    printf 'Esto REEMPLAZA los datos actuales de la base de datos por los del backup.\n' >&2
    read -r -p "Escribe 'si' para continuar: " answer
    [[ "$answer" == "si" ]] || die "Restauracion cancelada"
}

restore_database() {
    local file=$1
    # Comillas simples: las variables se expanden dentro del contenedor
    # shellcheck disable=SC2016
    docker compose exec -T db sh -c \
        'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner --single-transaction' \
        < "$file"
}

main() {
    local opt
    while getopts ":yd:h" opt; do
        case $opt in
            y) assume_yes=true ;;
            d) backup_dir=$OPTARG ;;
            h) usage; exit 0 ;;
            :) usage >&2; die "La opcion -$OPTARG necesita un valor" ;;
            *) usage >&2; die "Opcion no valida: -$OPTARG" ;;
        esac
    done
    shift $((OPTIND - 1))

    [[ $# -eq 1 ]] || { usage >&2; die "Indica el backup a restaurar o 'latest'"; }
    [[ "$backup_dir" == /* ]] || backup_dir="$PWD/$backup_dir"

    local backup_file=$1
    if [[ "$backup_file" == "latest" ]]; then
        backup_file="$(latest_backup)"
        [[ -n "$backup_file" ]] || die "No hay backups en $backup_dir"
    fi
    [[ "$backup_file" == /* ]] || backup_file="$PWD/$backup_file"
    [[ -f "$backup_file" ]] || die "No existe el archivo: $backup_file"

    cd "$PROJECT_DIR"
    require_running_db

    log INFO "Backup seleccionado: $backup_file"
    verify_checksum "$backup_file"
    confirm

    log INFO "Restaurando..."
    restore_database "$backup_file"
    log INFO "Restauracion completada"
}

main "$@"
