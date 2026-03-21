#!/usr/bin/env bash
# =============================================================
#  init.sh — первоначальная настройка media-stack
#  Запускать ОДИН РАЗ перед первым docker compose up
#  Использование: sudo bash scripts/init.sh
# =============================================================

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}   $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║     Media Stack — Инициализация          ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# -------------------------------------------------------------
# 1. Проверка .env
# -------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

if [[ ! -f "$REPO_DIR/.env" ]]; then
  log_warn ".env не найден. Копирую из .env.example..."
  cp "$REPO_DIR/.env.example" "$REPO_DIR/.env"
  log_warn "Заполни $REPO_DIR/.env и запусти скрипт снова."
  exit 1
fi

source "$REPO_DIR/.env"

# -------------------------------------------------------------
# 2. Проверка переменных
# -------------------------------------------------------------
log_info "Проверка переменных окружения..."

[[ -z "${DATA_ROOT:-}" ]]   && log_error "DATA_ROOT не задан в .env"
[[ -z "${CONFIG_ROOT:-}" ]] && log_error "CONFIG_ROOT не задан в .env"
[[ -z "${PUID:-}" ]]        && log_error "PUID не задан в .env"
[[ -z "${PGID:-}" ]]        && log_error "PGID не задан в .env"

log_success "Переменные проверены (DATA_ROOT=$DATA_ROOT)"

# -------------------------------------------------------------
# 3. Проверка раздела диска (критично для hardlink)
# -------------------------------------------------------------
log_info "Проверка файловой системы для hardlink..."

DATA_DEVICE=$(stat -c "%d" "$DATA_ROOT" 2>/dev/null || echo "")
if [[ -z "$DATA_DEVICE" ]]; then
  log_warn "Папка $DATA_ROOT не существует — будет создана."
else
  # Проверяем что torrents и media будут на одном разделе
  PARENT_DEVICE=$(stat -c "%d" "$(dirname "$DATA_ROOT")")
  if [[ "$DATA_DEVICE" != "$PARENT_DEVICE" ]]; then
    log_success "Раздел $DATA_ROOT отдельно примонтирован — hardlink будет работать внутри него."
  else
    log_info "Раздел: $DATA_ROOT на одном разделе с родительской папкой."
    log_info "Убедись что torrents/ и media/ не разнесены по разным дискам."
  fi
fi

# -------------------------------------------------------------
# 4. Создание структуры каталогов
# -------------------------------------------------------------
log_info "Создание структуры каталогов..."

DIRS=(
  "$DATA_ROOT/torrents/movies"
  "$DATA_ROOT/torrents/tv"
  "$DATA_ROOT/media/movies"
  "$DATA_ROOT/media/tv"
  "$CONFIG_ROOT/jellyfin"
  "$CONFIG_ROOT/sonarr"
  "$CONFIG_ROOT/radarr"
  "$CONFIG_ROOT/prowlarr"
  "$CONFIG_ROOT/qbittorrent"
  "$CONFIG_ROOT/jellyseerr"
  "$CONFIG_ROOT/bazarr"
  "$CONFIG_ROOT/notifiarr"
)

for DIR in "${DIRS[@]}"; do
  if [[ ! -d "$DIR" ]]; then
    mkdir -p "$DIR"
    log_success "Создана: $DIR"
  else
    log_info "Уже существует: $DIR"
  fi
done

# -------------------------------------------------------------
# 5. Установка прав
# -------------------------------------------------------------
log_info "Установка прав (PUID=$PUID, PGID=$PGID)..."
chown -R "$PUID:$PGID" "$DATA_ROOT"
chmod -R 755 "$DATA_ROOT"
log_success "Права установлены на $DATA_ROOT"

# -------------------------------------------------------------
# 6. Проверка NVIDIA
# -------------------------------------------------------------
log_info "Проверка NVIDIA GPU..."

if command -v nvidia-smi &>/dev/null; then
  GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
  log_success "Найдена GPU: $GPU_NAME"

  if ! docker info 2>/dev/null | grep -q "nvidia"; then
    log_warn "NVIDIA Container Toolkit не настроен в Docker."
    log_warn "Установи: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
    log_warn "Затем: sudo systemctl restart docker"
  else
    log_success "NVIDIA Container Toolkit активен в Docker."
  fi
else
  log_warn "nvidia-smi не найден. Убедись что драйверы NVIDIA установлены."
fi

# -------------------------------------------------------------
# 7. Проверка docker compose
# -------------------------------------------------------------
log_info "Проверка docker compose..."
if ! docker compose version &>/dev/null; then
  log_error "docker compose не найден. Установи Docker Desktop или Docker Engine с плагином compose."
fi
log_success "$(docker compose version)"

# -------------------------------------------------------------
# 8. Валидация compose файла
# -------------------------------------------------------------
log_info "Валидация docker-compose.yml..."
cd "$REPO_DIR"
if docker compose config --quiet 2>/dev/null; then
  log_success "docker-compose.yml валиден."
else
  log_error "Ошибки в docker-compose.yml. Проверь .env и файл конфигурации."
fi

# -------------------------------------------------------------
# Итог
# -------------------------------------------------------------
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║     Инициализация завершена успешно!     ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo -e "  Следующий шаг:"
echo -e "  ${GREEN}docker compose up -d${NC}"
echo ""
echo -e "  Адреса сервисов после запуска:"
echo -e "    Jellyfin:    ${BLUE}http://localhost:8096${NC}"
echo -e "    Sonarr:      ${BLUE}http://localhost:8989${NC}"
echo -e "    Radarr:      ${BLUE}http://localhost:7878${NC}"
echo -e "    qBittorrent: ${BLUE}http://localhost:8080${NC}"
echo -e "    Prowlarr:    ${BLUE}http://localhost:9696${NC}"
echo -e "    Jellyseerr:  ${BLUE}http://localhost:5055${NC}"
echo -e "    Bazarr:      ${BLUE}http://localhost:6767${NC}"
echo -e "    Notifiarr:   ${BLUE}http://localhost:5454${NC}"
echo ""
