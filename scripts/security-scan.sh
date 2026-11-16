#!/usr/bin/env bash
# Escaneo con Trivy (en Docker). Falla con vulnerabilidades de mi imagen, fallos del
# Dockerfile o secretos en el repo. Las imágenes de terceros solo avisan: no dependen
# de mí, se arreglan subiendo de versión.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly SCRIPT_DIR PROJECT_DIR
readonly TRIVY_IMAGE="${TRIVY_IMAGE:-aquasec/trivy:0.76.1}"
readonly OWN_IMAGE="infra-lab-web:local"
readonly SEVERITIES="HIGH,CRITICAL"

log() {
    local level=$1
    shift
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >&2
}

die() {
    log ERROR "$@"
    exit 1
}

summary() {
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        printf '%s\n' "$@" >> "$GITHUB_STEP_SUMMARY"
    fi
}

run_trivy() {
    docker run --rm \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v infra-lab-trivy-cache:/root/.cache/trivy \
        -v "$PROJECT_DIR:/src:ro" \
        "$TRIVY_IMAGE" --quiet "$@"
}

gate() {
    local description=$1
    shift
    log INFO "$description"
    if "$@"; then
        summary "| $description | OK |"
        return 0
    fi
    summary "| $description | **FALLO** (ver el log del job) |"
    return 1
}

third_party_images() {
    docker compose --env-file .env.example config --images | grep -vxF "$OWN_IMAGE" | sort -u
}

# Devuelve "<critical> <high>"
count_by_severity() {
    run_trivy image --severity "$SEVERITIES" --ignore-unfixed --format json "$1" \
        | jq -r '[.Results[]?.Vulnerabilities[]?.Severity] as $s
                 | "\($s | map(select(. == "CRITICAL")) | length) \($s | map(select(. == "HIGH")) | length)"'
}

report_third_party() {
    local images=() image counts critical high
    while IFS= read -r image; do
        images+=("$image")
    done < <(third_party_images)
    [[ ${#images[@]} -gt 0 ]] || return 0

    log INFO "4/4 Imagenes de terceros (informativo: vulnerabilidades $SEVERITIES con parche)"
    summary "" "### Imagenes de terceros (informativo)" "" \
        "Vulnerabilidades $SEVERITIES con parche disponible. Se corrigen subiendo de version." "" \
        "| Imagen | CRITICAL | HIGH |" "|--------|----------|------|"
    printf '%-52s %8s %5s\n' "IMAGEN" "CRITICAL" "HIGH"
    for image in "${images[@]}"; do
        if counts="$(count_by_severity "$image")"; then
            read -r critical high <<< "$counts"
        else
            log WARN "No se pudo escanear $image"
            critical="?"
            high="?"
        fi
        printf '%-52s %8s %5s\n' "$image" "$critical" "$high"
        summary "| \`$image\` | $critical | $high |"
    done
}

main() {
    command -v docker >/dev/null 2>&1 || die "No se encuentra el comando docker"
    command -v jq >/dev/null 2>&1 || die "No se encuentra el comando jq"
    cd "$PROJECT_DIR"

    log INFO "Construyendo la imagen propia $OWN_IMAGE"
    docker compose --env-file .env.example build web

    summary "## Escaneo de seguridad con Trivy" "" \
        "| Comprobacion (bloqueante) | Resultado |" "|---------------------------|-----------|"
    local failed=0
    gate "1/4 Imagen $OWN_IMAGE: vulnerabilidades $SEVERITIES con parche" \
        run_trivy image --severity "$SEVERITIES" --ignore-unfixed --exit-code 1 "$OWN_IMAGE" \
        || failed=1
    gate "2/4 Dockerfile de la app: configuracion $SEVERITIES" \
        run_trivy config --severity "$SEVERITIES" --exit-code 1 /src/web \
        || failed=1
    # .env y backups/ no están en git, pero pueden existir en local
    gate "3/4 Secretos en los archivos del repositorio" \
        run_trivy fs --scanners secret --skip-files '**/.env' --skip-dirs '**/backups' \
        --exit-code 1 /src \
        || failed=1
    report_third_party

    [[ "$failed" -eq 0 ]] || die "El escaneo ha encontrado problemas bloqueantes"
    log INFO "Escaneo completado sin problemas bloqueantes"
}

main "$@"
