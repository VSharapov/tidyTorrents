#!/bin/sh
# Seeds qBittorrent.conf from our template on first start, then runs the image's entrypoint.
# WebUI login: admin / hunter2. Localhost needs no login (the hook relies on that).
set -eu
conf=/config/qBittorrent/config/qBittorrent.conf
if [ ! -f "$conf" ]; then
  mkdir -p "${conf%/*}"
  sed "s|@TT_STORAGE@|$TT_STORAGE|" /tt/qBittorrent.conf > "$conf"
fi
mkdir -p "$TT_STORAGE/unsorted-pre-hook" "$TT_STORAGE/btih"
chown "$PUID:$PGID" "$TT_STORAGE" "$TT_STORAGE/unsorted-pre-hook" "$TT_STORAGE/btih"
# The image starts qbt via doas, which drops the environment, so hand the hook what it needs.
printf 'TT_STORAGE=%s\nTT_INSTANCE=%s\nQBT_WEBUI_PORT=%s\n' "$TT_STORAGE" "$TT_INSTANCE" "$QBT_WEBUI_PORT" > /config/tt.env
exec /entrypoint.sh
