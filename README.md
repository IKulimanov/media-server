# 🎬 Media Stack

Полный self-hosted медиасервер на базе Jellyfin с автоматической загрузкой, субтитрами и уведомлениями в Telegram.

**Стек:** Jellyfin · Sonarr · Radarr · Prowlarr · qBittorrent · Bazarr · Jellyseerr · Notifiarr · Watchtower

**Особенности конфигурации:**
- ✅ NVIDIA GPU — аппаратное транскодирование (NVENC/NVDEC)
- ✅ Hardlink — загруженные файлы не копируются, экономия места
- ✅ Telegram уведомления — новые загрузки, ошибки, обновления контейнеров
- ✅ Локальный доступ — всё работает без внешнего прокси
- ✅ Безопасность — контейнеры запускаются не от root (PUID/PGID)

---

## Содержание

1. [Требования](#1-требования)
2. [Структура данных и hardlink](#2-структура-данных-и-hardlink)
3. [Установка](#3-установка)
4. [Настройка NVIDIA](#4-настройка-nvidia)
5. [Настройка сервисов](#5-настройка-сервисов)
   - [qBittorrent](#51-qbittorrent)
   - [Prowlarr](#52-prowlarr)
   - [Radarr](#53-radarr)
   - [Sonarr](#54-sonarr)
   - [Bazarr](#55-bazarr)
   - [Jellyfin](#56-jellyfin)
   - [Jellyseerr](#57-jellyseerr)
6. [Уведомления в Telegram](#6-уведомления-в-telegram)
   - [Notifiarr — события загрузок](#61-notifiarr--события-загрузок)
   - [Watchtower — обновления контейнеров](#62-watchtower--обновления-контейнеров)
7. [Обслуживание](#7-обслуживание)
8. [Устранение неполадок](#8-устранение-неполадок)

---

## 1. Требования

| Компонент | Минимум | Рекомендуется |
|-----------|---------|---------------|
| ОС | Ubuntu 22.04 / Debian 12 | Ubuntu 24.04 |
| RAM | 4 GB | 8+ GB |
| CPU | 4 ядра | 6+ ядер |
| GPU | NVIDIA (любая) | RTX 3060+ |
| Docker | 24.x | последний |
| Docker Compose | v2.x (`docker compose`) | последний |
| NVIDIA Driver | 525+ | последний |
| NVIDIA Container Toolkit | требуется | — |

### Установка Docker (если не установлен)

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
```

---

## 2. Структура данных и hardlink

> **Почему это важно?**
> Hardlink позволяет Sonarr/Radarr "переместить" файл из папки загрузок в медиатеку мгновенно и без копирования — файл занимает место только один раз. Для этого обе папки **обязаны** находиться на одном разделе диска и видеться контейнерам через **один и тот же volume**.

```
/data                          ← DATA_ROOT (один раздел!)
├── torrents/
│   ├── movies/                ← qBittorrent сохраняет фильмы сюда
│   └── tv/                    ← qBittorrent сохраняет сериалы сюда
├── media/
│   ├── movies/                ← Radarr создаёт hardlink сюда (0 доп. места)
│   └── tv/                    ← Sonarr создаёт hardlink сюда (0 доп. места)
└── configs/                   ← конфиги всех сервисов
```

**Как видят /data контейнеры:**

| Контейнер | Volume | Путь внутри |
|-----------|--------|-------------|
| qBittorrent | `${DATA_ROOT}/torrents` | `/data/torrents` |
| Sonarr | `${DATA_ROOT}` | `/data` |
| Radarr | `${DATA_ROOT}` | `/data` |
| Jellyfin | `${DATA_ROOT}/media` | `/data/media` (read-only) |

Sonarr видит и `/data/torrents/tv`, и `/data/media/tv` — они внутри одного mount, hardlink работает.

---

## 3. Установка

### Шаг 1 — Клонировать репозиторий

```bash
git clone https://github.com/YOUR_USERNAME/media-stack.git
cd media-stack
```

### Шаг 2 — Создать .env

```bash
cp .env.example .env
nano .env   # или любой редактор
```

Обязательно заполнить:

```env
TZ=Asia/Bishkek           # твой часовой пояс
PUID=1000                  # результат команды: id -u
PGID=1000                  # результат команды: id -g
DATA_ROOT=/data            # путь к данным (должен быть на одном разделе!)
CONFIG_ROOT=/data/configs  # путь к конфигам
HOSTNAME=mediaserver       # имя в уведомлениях
TELEGRAM_BOT_TOKEN=...     # токен от @BotFather
TELEGRAM_CHAT_ID=...       # твой chat id
```

### Шаг 3 — Инициализация

```bash
sudo bash scripts/init.sh
```

Скрипт создаст все папки, установит права и проверит NVIDIA.

### Шаг 4 — Запуск

```bash
docker compose up -d
```

### Шаг 5 — Проверка статуса

```bash
docker compose ps
```

Все контейнеры должны быть `healthy` через 1–2 минуты.

---

## 4. Настройка NVIDIA

NVIDIA Container Toolkit должен быть установлен **до** запуска стека.

### Установка (Ubuntu/Debian)

```bash
# Добавить репозиторий NVIDIA
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# Установить
sudo apt update
sudo apt install -y nvidia-container-toolkit

# Настроить Docker и перезапустить
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

### Проверка

```bash
# GPU должна быть видна из контейнера
docker run --rm --gpus all nvidia/cuda:12.0-base-ubuntu22.04 nvidia-smi
```

### Активация в Jellyfin

После запуска стека:

1. Открыть `http://localhost:8096`
2. Панель управления → Воспроизведение → Транскодирование
3. Выбрать **NVENC** как аппаратное ускорение
4. Включить опции: **H.264, H.265, AV1** (по возможностям карты)
5. Включить **NVDEC** для аппаратного декодирования

---

## 5. Настройка сервисов

> Порядок важен: сначала qBittorrent и Prowlarr, затем Radarr/Sonarr, затем остальные.

### 5.1 qBittorrent

**Адрес:** `http://localhost:8080`

**Получить пароль при первом входе:**
```bash
docker logs qbittorrent 2>&1 | grep "temporary password"
```

**Настройки → Загрузки:**
- Default Torrent Management Mode: **Automatic** ← обязательно!
- Default Save Path: `/data/torrents`

**Настройки → WebUI:**
- Сменить пароль на свой

**Добавить категории** (левый sidebar → правая кнопка на All → Add category):

| Категория | Save path |
|-----------|-----------|
| `radarr`  | `/data/torrents/movies` |
| `sonarr`  | `/data/torrents/tv` |

> Категории должны совпадать с тем, что настроишь в Radarr/Sonarr позже.

---

### 5.2 Prowlarr

**Адрес:** `http://localhost:9696`

1. Settings → General → скопировать **API Key** (понадобится для Radarr/Sonarr)
2. Indexers → Add Indexer → выбрать нужные трекеры
3. Settings → Apps → Add Application:
   - Radarr: `http://radarr:7878`, вставить API ключ Radarr
   - Sonarr: `http://sonarr:8989`, вставить API ключ Sonarr

> Prowlarr автоматически синхронизирует индексаторы в Radarr и Sonarr — вручную добавлять трекеры в каждый сервис не нужно.

---

### 5.3 Radarr

**Адрес:** `http://localhost:7878`

**Settings → Media Management:**
- Root Folder: `/data/media/movies` ← Add Root Folder
- ⚠️ Show Advanced → **Use Hardlinks instead of Copy: ✅ включить**
- Rename Movies: включить (рекомендуется)

**Settings → Download Clients → Add → qBittorrent:**
- Host: `qbittorrent`
- Port: `8080`
- Username/Password: твои данные от qBittorrent
- Category: `radarr`

**Settings → General → скопировать API Key** (для Prowlarr и Notifiarr)

**Проверка hardlink:**
После первой загрузки файл должен появиться и в `/data/torrents/movies/` и в `/data/media/movies/`. Суммарный размер папок не должен удвоиться — это признак успешного hardlink.

```bash
# Проверить что это hardlink (одинаковый inode):
ls -li /data/torrents/movies/SomeMovie/
ls -li /data/media/movies/SomeMovie/
# Первая колонка (inode) должна совпадать
```

---

### 5.4 Sonarr

**Адрес:** `http://localhost:8989`

**Settings → Media Management:**
- Root Folder: `/data/media/tv`
- ⚠️ Show Advanced → **Use Hardlinks instead of Copy: ✅ включить**

**Settings → Download Clients → Add → qBittorrent:**
- Host: `qbittorrent`
- Port: `8080`
- Category: `sonarr`

**Settings → General → скопировать API Key**

---

### 5.5 Bazarr

**Адрес:** `http://localhost:6767`

1. Settings → Sonarr: `http://sonarr:8989`, API Key из Sonarr
2. Settings → Radarr: `http://radarr:7878`, API Key из Radarr
3. Settings → Languages: добавить нужные языки субтитров
4. Settings → Providers: добавить OpenSubtitles или другие источники

---

### 5.6 Jellyfin

**Адрес:** `http://localhost:8096`

**Первый запуск:**
1. Выбрать язык → Создать admin аккаунт
2. Add Media Library:
   - Тип: **Movies**, папка: `/data/media/movies`
   - Тип: **Shows**, папка: `/data/media/tv`
3. Remote Access → ✅ Allow Remote Connections, ❌ Automatic Port Mapping

**NVIDIA транскодирование** — см. раздел [4. Настройка NVIDIA](#4-настройка-nvidia).

**Доступ с других устройств в сети:**
```
http://<IP-адрес-ноутбука>:8096
```
Узнать IP: `ip addr show | grep "inet " | grep -v 127`

---

### 5.7 Jellyseerr

**Адрес:** `http://localhost:5055`

1. Sign In with Jellyfin: `http://jellyfin:8096`
2. Ввести логин/пароль admin от Jellyfin
3. Sync Libraries → выбрать Movies и TV Shows
4. Settings → Radarr/Sonarr: добавить API ключи

Jellyseerr позволяет другим пользователям **запрашивать** контент — Radarr/Sonarr автоматически поставят его в очередь загрузки.

---

## 6. Уведомления в Telegram

### Создание Telegram-бота

1. Открыть [@BotFather](https://t.me/BotFather) в Telegram
2. Написать `/newbot` → дать имя → получить **токен**
3. Написать своему боту любое сообщение (иначе он не сможет отправлять тебе сообщения)
4. Получить chat_id:
   ```
   https://api.telegram.org/bot<ТОКЕН>/getUpdates
   ```
   Найти `"chat":{"id": 123456789}` — это твой TELEGRAM_CHAT_ID
5. Вставить оба значения в `.env`

---

### 6.1 Notifiarr — события загрузок

Notifiarr отправляет уведомления о:
- ✅ Новый фильм/сериал добавлен в очередь
- ✅ Загрузка завершена
- ✅ Ошибки в Sonarr/Radarr/Prowlarr
- ✅ Здоровье контейнеров

**Шаг 1 — Регистрация**

Зарегистрироваться на [notifiarr.com](https://notifiarr.com) (бесплатный tier достаточен).

**Шаг 2 — Получить API ключ**

В личном кабинете: Profile → API Key → скопировать.

**Шаг 3 — Настройка Telegram в notifiarr.com**

1. В личном кабинете: Notifications → Add Integration → Telegram
2. Ввести Bot Token и Chat ID
3. Выбрать типы уведомлений:
   - Sonarr: Grabbed, Downloaded, Failed
   - Radarr: Grabbed, Downloaded, Failed
   - Health: все типы

**Шаг 4 — Добавить API ключ в конфиг**

```bash
nano /data/configs/notifiarr/notifiarr.conf
# Вставить api_key = "твой_ключ"
```

**Шаг 5 — Добавить API ключи сервисов в конфиг**

```ini
[sonarr]
  [[sonarr.instance]]
  url     = "http://sonarr:8989"
  api_key = "ключ_из_sonarr_settings_general"

[radarr]
  [[radarr.instance]]
  url     = "http://radarr:7878"
  api_key = "ключ_из_radarr_settings_general"
```

**Шаг 6 — Перезапустить Notifiarr**

```bash
docker compose restart notifiarr
```

**Шаг 7 — Подключить Notifiarr в Sonarr/Radarr**

В Sonarr: Settings → Connect → Add → Notifiarr:
- API Key: ключ из notifiarr.com
- Включить: On Grab, On Download, On Upgrade, On Health Issue

В Radarr — аналогично.

---

### 6.2 Watchtower — обновления контейнеров

Watchtower уже настроен в `docker-compose.yml`. Он:
- Каждую ночь в 4:00 проверяет новые версии образов
- Обновляет контейнеры с минимальным даунтаймом
- Отправляет уведомление в Telegram с именами обновлённых контейнеров

Пример уведомления:
```
💧 Watchtower
✅ jellyfin обновлён до lscr.io/linuxserver/jellyfin:latest
✅ sonarr обновлён до lscr.io/linuxserver/sonarr:latest
```

Watchtower использует токен и chat_id из `.env` — дополнительная настройка не нужна.

---

## 7. Обслуживание

### Обновление стека

```bash
bash scripts/update.sh
```

### Просмотр логов

```bash
# Все сервисы
docker compose logs -f

# Конкретный сервис
docker compose logs -f radarr
docker compose logs -f jellyfin
```

### Перезапуск сервиса

```bash
docker compose restart sonarr
```

### Остановка и запуск

```bash
docker compose down    # остановить (данные сохраняются)
docker compose up -d   # запустить снова
```

### Бэкап конфигов

```bash
# Архивировать все конфиги (без медиафайлов)
tar -czf media-stack-backup-$(date +%Y%m%d).tar.gz /data/configs/
```

---

## 8. Устранение неполадок

### Hardlink не работает — файлы копируются

**Симптом:** размер `/data/media` растёт так же как `/data/torrents`

**Диагностика:**
```bash
# Проверить что файлы на одном разделе
df /data/torrents /data/media
# Вывод должен показывать ОДНО устройство (например /dev/sda1)

# Проверить inode файла
stat /data/torrents/movies/SomeMovie/file.mkv
stat /data/media/movies/SomeMovie/file.mkv
# Поле "Inode:" должно совпадать
```

**Решение:** если устройства разные — `/data/torrents` и `/data/media` находятся на разных разделах. Перенести всё на один раздел или примонтировать общий диск как `/data`.

### Контейнер не запускается

```bash
docker compose logs <имя_контейнера>
```

### NVIDIA GPU не видна в Jellyfin

```bash
# Проверить что GPU видна из контейнера
docker exec jellyfin nvidia-smi

# Если ошибка — проверить toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
docker compose up -d jellyfin
```

### qBittorrent не доступен из Sonarr/Radarr

Sonarr и Radarr обращаются к qBittorrent по имени `qbittorrent` (имя контейнера), не по `localhost`. Убедись что в настройках Download Client указан хост `qbittorrent`, порт `8080`.

### Пароль qBittorrent при первом запуске

```bash
docker logs qbittorrent 2>&1 | grep -i password
```

---

## Порты сервисов

| Сервис | Порт | Назначение |
|--------|------|------------|
| Jellyfin | 8096 | HTTP (основной) |
| Jellyfin | 8920 | HTTPS |
| Sonarr | 8989 | WebUI |
| Radarr | 7878 | WebUI |
| qBittorrent | 8080 | WebUI |
| Prowlarr | 9696 | WebUI |
| Jellyseerr | 5055 | WebUI |
| Bazarr | 6767 | WebUI |
| Notifiarr | 5454 | WebUI |

Все сервисы доступны только локально по адресу `http://localhost:<порт>` или `http://<IP-ноутбука>:<порт>` из других устройств в локальной сети.

---

> Нужен внешний доступ через интернет? Добавь Nginx Proxy Manager + DuckDNS или Cloudflare Tunnel — это отдельная тема, не входящая в базовую конфигурацию.
