#!/usr/bin/env bash
# NeuroBerry - Script de inicio completo
# Uso: ./start.sh [--rebuild]
set -euo pipefail

ROOT_MAIN="$(cd "$(dirname "$0")" && pwd)"
ROOT_NN="$(cd "$ROOT_MAIN/../neural-network-api" && pwd)"
COMPOSE_MAIN="$ROOT_MAIN/docker-compose.dev.yml"
COMPOSE_NN="$ROOT_NN/docker-composer.dev.yaml"

REBUILD=false
for arg in "$@"; do [[ "$arg" == "--rebuild" ]] && REBUILD=true; done

# ─── Colores ──────────────────────────────────────────────────────────────────
green()  { printf "\033[32m✔  %s\033[0m\n" "$1"; }
yellow() { printf "\033[33m►  %s\033[0m\n" "$1"; }
red()    { printf "\033[31m✘  %s\033[0m\n" "$1"; exit 1; }
info()   { printf "\033[36m   %s\033[0m\n" "$1"; }

# ─── Funciones ────────────────────────────────────────────────────────────────
gen_secret() { python3 -c "import secrets; print(secrets.token_hex(32))"; }

wait_http() {
  local url="$1" retries=30 delay=3
  for i in $(seq 1 $retries); do
    code=$(curl -sS -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    [[ "$code" =~ ^2|^3 ]] && return 0
    sleep $delay
  done
  return 1
}

bootstrap_minio() {
  yellow "Bootstrapping MinIO (buckets, usuario, política)..."
  local root_user root_pass s3_key s3_secret
  root_user=$(grep '^MINIO_ROOT_USER=' "$ROOT_MAIN/.env" | cut -d= -f2)
  root_pass=$(grep '^MINIO_ROOT_PASSWORD=' "$ROOT_MAIN/.env" | cut -d= -f2)
  s3_key=$(grep '^S3_ACCESS_KEY=' "$ROOT_MAIN/.env" | cut -d= -f2)
  s3_secret=$(grep '^S3_SECRET_KEY=' "$ROOT_MAIN/.env" | cut -d= -f2)

  docker run --rm \
    --entrypoint /bin/sh \
    --network main-web-app_default \
    -v "$ROOT_MAIN/minio-policy.json:/tmp/minio-policy.json:ro" \
    -e MC_HOST_local="http://${root_user}:${root_pass}@s3:9000" \
    -e HTTP_PROXY= -e HTTPS_PROXY= -e http_proxy= -e https_proxy= \
    -e NO_PROXY='s3,localhost,127.0.0.1' -e no_proxy='s3,localhost,127.0.0.1' \
    minio/mc:RELEASE.2025-07-21T05-28-08Z-cpuv1 -lc "
      mc mb local/dataset   --ignore-existing
      mc mb local/inferences --ignore-existing
      mc anonymous set download local/dataset   2>/dev/null || true
      mc anonymous set download local/inferences 2>/dev/null || true
      mc admin user add local '$s3_key' '$s3_secret' 2>/dev/null || true
      mc admin policy create local myapp-policy /tmp/minio-policy.json 2>/dev/null || true
      mc admin policy attach local myapp-policy --user '$s3_key' 2>/dev/null || true
      echo 'MinIO bootstrap OK'
    " 2>&1 | grep -E 'OK|Error|ERROR|created|added|Bucket' || true
}

# ─── 1. Prerrequisitos ────────────────────────────────────────────────────────
printf "\n\033[1mNeuroBerry — Inicio\033[0m\n"
printf "════════════════════════════════════\n\n"

yellow "Verificando prerrequisitos..."
command -v docker >/dev/null 2>&1 || red "Docker no encontrado. Instálalo primero."
docker info >/dev/null 2>&1     || red "El daemon de Docker no está corriendo."
command -v python3 >/dev/null 2>&1 || red "python3 no encontrado."
green "Prerrequisitos OK"

# ─── 2. Archivos .env (main stack) ───────────────────────────────────────────
yellow "Configurando variables de entorno (main stack)..."

if [[ ! -f "$ROOT_MAIN/.env" ]]; then
  cp "$ROOT_MAIN/.env_template" "$ROOT_MAIN/.env"
  info ".env principal creado desde template"
fi

# Generar secretos si están vacíos
if ! grep -q '^S3_ACCESS_KEY=.\+' "$ROOT_MAIN/.env" 2>/dev/null; then
  sed -i "s|^S3_ACCESS_KEY=.*|S3_ACCESS_KEY=neuroberry_s3_user|" "$ROOT_MAIN/.env"
fi
if ! grep -q '^S3_SECRET_KEY=.\+' "$ROOT_MAIN/.env" 2>/dev/null; then
  sed -i "s|^S3_SECRET_KEY=.*|S3_SECRET_KEY=$(gen_secret)|" "$ROOT_MAIN/.env"
fi
if ! grep -q '^FLASK_LOGFILE_PATH=.\+' "$ROOT_MAIN/.env" 2>/dev/null; then
  sed -i "s|^FLASK_LOGFILE_PATH=.*|FLASK_LOGFILE_PATH=/tmp/app-flask-errors.log|" "$ROOT_MAIN/.env"
fi

green "Variables main stack listas"

# ─── 3. .env de la API principal ─────────────────────────────────────────────
yellow "Configurando variables de entorno (API principal)..."

API_ENV="$ROOT_MAIN/api-brain-mapper/.env"
if [[ ! -f "$API_ENV" ]]; then
  cp "$ROOT_MAIN/api-brain-mapper/.env.format" "$API_ENV"
  info "api-brain-mapper/.env creado desde template"
fi

# Leer valores del .env principal para sincronizar
S3_KEY=$(grep '^S3_ACCESS_KEY=' "$ROOT_MAIN/.env" | cut -d= -f2)
S3_SEC=$(grep '^S3_SECRET_KEY=' "$ROOT_MAIN/.env" | cut -d= -f2)

# Generar SECRET_KEY si es el placeholder
if grep -q '^SECRET_KEY=ultrasecret\|^SECRET_KEY=$' "$API_ENV" 2>/dev/null; then
  NEW_SK=$(gen_secret)
  sed -i "s|^SECRET_KEY=.*|SECRET_KEY=$NEW_SK|" "$API_ENV"
fi

# Generar NN_API_SECRET_KEY si es placeholder
if grep -q '^NN_API_SECRET_KEY=<\|^NN_API_SECRET_KEY=$' "$API_ENV" 2>/dev/null; then
  NEW_NN=$(gen_secret)
  sed -i "s|^NN_API_SECRET_KEY=.*|NN_API_SECRET_KEY=$NEW_NN|" "$API_ENV"
fi

# Sincronizar credenciales S3 y host
sed -i "s|^S3_ACCESS_KEY=.*|S3_ACCESS_KEY=$S3_KEY|" "$API_ENV"
sed -i "s|^S3_SECRET_KEY=.*|S3_SECRET_KEY=$S3_SEC|" "$API_ENV"
sed -i "s|^DB_NAME=.*|DB_NAME=$(grep '^DB_NAME=' "$ROOT_MAIN/.env" | cut -d= -f2)|" "$API_ENV"
sed -i "s|^DB_USER=.*|DB_USER=$(grep '^DB_USER=' "$ROOT_MAIN/.env" | cut -d= -f2)|" "$API_ENV"
sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=$(grep '^DB_USER_PASSWORD=' "$ROOT_MAIN/.env" | cut -d= -f2)|" "$API_ENV"
sed -i "s|^NN_API_HOST=.*|NN_API_HOST=http://host.docker.internal:8080|" "$API_ENV"
grep -q '^extra_hosts\|host.docker.internal' "$API_ENV" 2>/dev/null || true

green "Variables API principal listas"

# ─── 4. .env del cliente web ──────────────────────────────────────────────────
yellow "Configurando variables de entorno (cliente web)..."

WEB_ENV="$ROOT_MAIN/webclient/.env"
if [[ ! -f "$WEB_ENV" ]]; then
  echo "VITE_API_BASE_URL=http://localhost:5000" > "$WEB_ENV"
  info "webclient/.env creado"
fi
green "Variables cliente web listas"

# ─── 5. .env de la API de inferencia ─────────────────────────────────────────
yellow "Configurando variables de entorno (API de inferencia)..."

NN_ENV="$ROOT_NN/.env"
if [[ ! -f "$NN_ENV" ]]; then
  cp "$ROOT_NN/.env_template" "$NN_ENV"
  info ".env de inferencia creado desde template"
fi

# Sincronizar NN_API_SECRET_KEY con el valor generado en la API principal
NN_SECRET=$(grep '^NN_API_SECRET_KEY=' "$API_ENV" | cut -d= -f2)
sed -i "s|^SECRET_KEY_TOKENS=.*|SECRET_KEY_TOKENS=$NN_SECRET|" "$NN_ENV"

if ! grep -q '^MODEL_YAML_PATH=.\+' "$NN_ENV" 2>/dev/null; then
  sed -i "s|^MODEL_YAML_PATH=.*|MODEL_YAML_PATH=/app/app/models/my_dataset.yaml|" "$NN_ENV"
fi

green "Variables inferencia listas"

# ─── 6. Archivos de log ───────────────────────────────────────────────────────
yellow "Preparando archivos de log..."
LOG_PATH=$(grep '^FLASK_LOGFILE_PATH=' "$ROOT_MAIN/.env" | cut -d= -f2)
touch "$LOG_PATH" 2>/dev/null && green "Log Flask: $LOG_PATH" || \
  info "No se pudo crear $LOG_PATH (no crítico)"

# ─── 7. Iniciar stack de inferencia ──────────────────────────────────────────
yellow "Iniciando API de inferencia (neural-network-api)..."
mkdir -p "$ROOT_NN/models/weights" "$ROOT_NN/models/temp_configs"

BUILD_FLAG=""
$REBUILD && BUILD_FLAG="--build"

cd "$ROOT_NN"
docker compose -f "$COMPOSE_NN" up -d $BUILD_FLAG
green "API de inferencia iniciada"

# ─── 8. Iniciar stack principal ───────────────────────────────────────────────
yellow "Iniciando stack principal (main-web-app)..."
cd "$ROOT_MAIN"
docker compose -f "$COMPOSE_MAIN" up -d $BUILD_FLAG
green "Stack principal iniciado"

# ─── 9. Esperar MinIO y hacer bootstrap ──────────────────────────────────────
yellow "Esperando que MinIO esté disponible..."
if wait_http "http://localhost:9000/minio/health/live"; then
  green "MinIO disponible"
  bootstrap_minio
else
  red "MinIO no respondió a tiempo. Revisa: docker compose -f $COMPOSE_MAIN logs s3"
fi

# ─── 10. Esperar servicios restantes ─────────────────────────────────────────
yellow "Esperando API principal..."
wait_http "http://localhost:5000/" && green "API principal disponible" || \
  info "API aún iniciando, dale unos segundos más"

# ─── 11. Healthcheck final ───────────────────────────────────────────────────
printf "\n"
"$ROOT_MAIN/healthcheck.sh" || true

# ─── Resumen ─────────────────────────────────────────────────────────────────
printf "\n\033[1mAcceso rápido:\033[0m\n"
printf "  %-25s %s\n" "Aplicación Web"     "http://localhost:3003"
printf "  %-25s %s\n" "API Principal"      "http://localhost:5000"
printf "  %-25s %s\n" "MinIO Consola"      "http://localhost:9001"
printf "  %-25s %s\n" "API Inferencia"     "http://localhost:8080/health"
printf "\n\033[1mCredenciales por defecto:\033[0m\n"
printf "  %-25s %s\n" "Web (email)"        "admin@gmail.com"
printf "  %-25s %s\n" "Web (contraseña)"   'Pass$612345'
printf "  %-25s %s\n" "MinIO (usuario)"    "$(grep '^MINIO_ROOT_USER=' "$ROOT_MAIN/.env" | cut -d= -f2)"
printf "  %-25s %s\n" "MinIO (contraseña)" "$(grep '^MINIO_ROOT_PASSWORD=' "$ROOT_MAIN/.env" | cut -d= -f2)"
printf "\n"
