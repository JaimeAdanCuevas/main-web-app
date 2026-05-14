#!/usr/bin/env bash
set -u

ROOT_MAIN="/root/main-web-app"
ROOT_NN="/root/neural-network-api"
COMPOSE_MAIN="$ROOT_MAIN/docker-compose.dev.yml"
COMPOSE_NN="$ROOT_NN/docker-composer.dev.yaml"

ok_count=0
fail_count=0

green() { printf "\033[32m%s\033[0m\n" "$1"; }
red() { printf "\033[31m%s\033[0m\n" "$1"; }
yellow() { printf "\033[33m%s\033[0m\n" "$1"; }

check_http() {
  local name="$1"
  local url="$2"
  local expected="$3"

  local code
  code=$(curl -sS -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
  if [[ "$code" == "$expected" ]]; then
    green "[OK] $name -> $url (HTTP $code)"
    ok_count=$((ok_count + 1))
  else
    red "[FAIL] $name -> $url (HTTP $code, expected $expected)"
    fail_count=$((fail_count + 1))
  fi
}

check_compose_service() {
  local root="$1"
  local compose_file="$2"
  local service="$3"

  local status
  status=$(cd "$root" && docker compose -f "$compose_file" ps --status running --services 2>/dev/null | grep -x "$service" || true)

  if [[ "$status" == "$service" ]]; then
    green "[OK] Service running: $service"
    ok_count=$((ok_count + 1))
  else
    red "[FAIL] Service not running: $service"
    fail_count=$((fail_count + 1))
  fi
}

printf "\nNeuroBerry healthcheck\n"
printf "======================\n\n"

if ! command -v docker >/dev/null 2>&1; then
  red "[FAIL] docker command not found"
  exit 2
fi

if ! docker info >/dev/null 2>&1; then
  red "[FAIL] docker daemon is not available"
  exit 2
fi

yellow "Checking main stack services..."
check_compose_service "$ROOT_MAIN" "$COMPOSE_MAIN" "webclient"
check_compose_service "$ROOT_MAIN" "$COMPOSE_MAIN" "flask_api"
check_compose_service "$ROOT_MAIN" "$COMPOSE_MAIN" "postgres"
check_compose_service "$ROOT_MAIN" "$COMPOSE_MAIN" "s3"

yellow "Checking neural stack services..."
check_compose_service "$ROOT_NN" "$COMPOSE_NN" "neural-api"

yellow "Checking endpoints..."
check_http "Web" "http://localhost:3003" "200"
check_http "API root" "http://localhost:5000/" "200"
check_http "MinIO console" "http://localhost:9001" "200"
check_http "Neural API health" "http://localhost:8080/health" "200"

printf "\nSummary: %s OK, %s FAIL\n" "$ok_count" "$fail_count"

if [[ "$fail_count" -eq 0 ]]; then
  green "Platform status: HEALTHY"
  exit 0
fi

red "Platform status: ISSUES DETECTED"
exit 1
