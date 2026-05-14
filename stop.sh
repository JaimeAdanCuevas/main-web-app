#!/usr/bin/env bash
# NeuroBerry - Script de parada completa
# Uso: ./stop.sh [--clean] [--volumes]
#   --clean    : elimina imágenes construidas (fuerza rebuild en próximo start)
#   --volumes  : elimina todos los volúmenes (¡borra datos de BD y MinIO!)
set -euo pipefail

ROOT_MAIN="$(cd "$(dirname "$0")" && pwd)"
ROOT_NN="$(cd "$ROOT_MAIN/../neural-network-api" && pwd)"
COMPOSE_MAIN="$ROOT_MAIN/docker-compose.dev.yml"
COMPOSE_NN="$ROOT_NN/docker-composer.dev.yaml"

CLEAN=false
VOLUMES=false
for arg in "$@"; do
  [[ "$arg" == "--clean"   ]] && CLEAN=true
  [[ "$arg" == "--volumes" ]] && VOLUMES=true
done

green()  { printf "\033[32m✔  %s\033[0m\n" "$1"; }
yellow() { printf "\033[33m►  %s\033[0m\n" "$1"; }
red()    { printf "\033[31m⚠  %s\033[0m\n" "$1"; }

printf "\n\033[1mNeuroBerry — Parada\033[0m\n"
printf "════════════════════════════════════\n\n"

COMPOSE_FLAGS=()
$VOLUMES && COMPOSE_FLAGS+=("-v")

yellow "Deteniendo API de inferencia..."
cd "$ROOT_NN"
docker compose -f "$COMPOSE_NN" down "${COMPOSE_FLAGS[@]}" 2>/dev/null && green "API de inferencia detenida" || true

yellow "Deteniendo stack principal..."
cd "$ROOT_MAIN"
docker compose -f "$COMPOSE_MAIN" down "${COMPOSE_FLAGS[@]}" 2>/dev/null && green "Stack principal detenido" || true

if $CLEAN; then
  yellow "Eliminando imágenes construidas..."
  docker rmi main-web-app-flask_api main-web-app-webclient neural-network-api-neural-api 2>/dev/null || true
  green "Imágenes eliminadas"
fi

if $VOLUMES; then
  red "Volúmenes eliminados — la base de datos y MinIO fueron borrados"
fi

printf "\nPara iniciar de nuevo: ./start.sh\n\n"
