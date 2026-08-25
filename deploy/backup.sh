#!/usr/bin/env bash
# Point-in-time backup of TREK's data + uploads.
#
# The SQLite database runs in WAL mode, so copying travel.db while the server is
# writing can capture a torn state. This stops the container for the few seconds
# it takes to archive, which is the simple way to guarantee consistency. Caddy
# keeps running, so visitors see a 502 rather than a connection failure.
#
# Install as a nightly cron job (as the trek user, which is in the docker group):
#   crontab -e
#   15 3 * * * /opt/trek/deploy/backup.sh >> /opt/trek/backups/backup.log 2>&1

set -euo pipefail

# The archive contains .env (and therefore ENCRYPTION_KEY), so it is as
# sensitive as the database itself. Keep it root-readable only.
umask 077

APP_DIR="${APP_DIR:-/opt/trek}"
BACKUP_DIR="${BACKUP_DIR:-/opt/trek/backups}"
RETAIN_DAYS="${RETAIN_DAYS:-14}"
COMPOSE="docker compose -f ${APP_DIR}/docker-compose.prod.yml"

stamp="$(date +%Y%m%d-%H%M%S)"
archive="${BACKUP_DIR}/trek-${stamp}.tar.gz"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
cd "$APP_DIR"

echo "[$(date -Is)] stopping trek for a consistent snapshot"
$COMPOSE stop trek

# Always restart the app, even if tar fails partway through.
trap '$COMPOSE start trek' EXIT

tar -czf "$archive" \
	-C "$APP_DIR" data uploads .env

$COMPOSE start trek
trap - EXIT

echo "[$(date -Is)] wrote $archive ($(du -h "$archive" | cut -f1))"

# Prune old archives.
find "$BACKUP_DIR" -name 'trek-*.tar.gz' -mtime "+${RETAIN_DAYS}" -delete

echo "[$(date -Is)] done. Retained: $(find "$BACKUP_DIR" -name 'trek-*.tar.gz' | wc -l) archives"
