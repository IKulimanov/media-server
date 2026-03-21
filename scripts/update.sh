#!/usr/bin/env bash
# =============================================================
#  update.sh — безопасное обновление media-stack
#  Использование: bash scripts/update.sh
# =============================================================

set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}   $1"; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

source .env

echo ""
log_info "Скачиваем новые образы..."
docker compose pull

log_info "Перезапускаем изменённые контейнеры..."
docker compose up -d --remove-orphans

log_info "Удаляем старые образы..."
docker image prune -f

log_success "Стек обновлён!"
echo ""
docker compose ps
