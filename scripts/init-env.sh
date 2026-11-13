#!/usr/bin/env bash
# Crea el .env a partir de .env.example y cambia cada "change-me-please" por una
# contraseña aleatoria, para que nadie arranque el stack con contraseñas por defecto.
# Nunca machaca un .env que ya exista.
#
# Uso: scripts/init-env.sh   (o: make env)
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly SCRIPT_DIR PROJECT_DIR
readonly PLACEHOLDER="change-me-please"

tmp_file=""

log() {
    local level=$1
    shift
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >&2
}

die() {
    log ERROR "$@"
    exit 1
}

cleanup() {
    if [[ -n "$tmp_file" ]]; then
        rm -f -- "$tmp_file"
    fi
}

generate_secret() {
    # 24 bytes de /dev/urandom en hexadecimal (48 caracteres), así no dependo de openssl
    od -An -vtx1 -N24 /dev/urandom | tr -d ' \n'
}

main() {
    local example="$PROJECT_DIR/.env.example"
    local target="$PROJECT_DIR/.env"
    local line generated=0

    [[ -f "$example" ]] || die "No existe $example"
    if [[ -e "$target" ]]; then
        log INFO ".env ya existe; no se modifica"
        return 0
    fi

    umask 077
    trap cleanup EXIT
    tmp_file="$(mktemp "$PROJECT_DIR/.env.XXXXXX")"

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == *"=$PLACEHOLDER" ]]; then
            printf '%s=%s\n' "${line%%=*}" "$(generate_secret)"
            generated=$((generated + 1))
        else
            printf '%s\n' "$line"
        fi
    done < "$example" > "$tmp_file"

    mv -- "$tmp_file" "$target"
    tmp_file=""
    log INFO ".env creado con $generated contrasenas aleatorias (permisos 600)"
}

main "$@"
