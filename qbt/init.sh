#!/bin/sh
# Seeds qBittorrent.conf from our template on first start, then runs the image's entrypoint.
# WebUI login: admin / hunter2. Localhost needs no login (the hook relies on that).
set -eu
conf=/config/qBittorrent/config/qBittorrent.conf
if [ ! -f "$conf" ]; then
  mkdir -p "${conf%/*}"
  sed "s|@TT_STORAGE@|$TT_STORAGE|" /tt/qBittorrent.conf > "$conf"
fi
# Your sparse overrides in local/qBittorrent.conf win, every start.
if [ -f /tt-local/qBittorrent.conf ]; then
  python3 - "$conf" /tt-local/qBittorrent.conf <<'PY'
import configparser, sys
def load(p):
    c = configparser.RawConfigParser(delimiters=("=",), comment_prefixes=("#", ";")); c.optionxform = str
    c.read(p); return c
conf, local = load(sys.argv[1]), load(sys.argv[2])
for s in local.sections():
    if not conf.has_section(s): conf.add_section(s)
    for k, v in local.items(s): conf.set(s, k, v)
with open(sys.argv[1], "w") as f: conf.write(f, space_around_delimiters=False)
PY
fi
mkdir -p "$TT_STORAGE/unsorted-pre-hook" "$TT_STORAGE/btih"
chown "$PUID:$PGID" "$TT_STORAGE" "$TT_STORAGE/unsorted-pre-hook" "$TT_STORAGE/btih"
# The image starts qbt via doas, which drops the environment, so hand the hook what it needs.
printf 'TT_STORAGE=%s\nTT_INSTANCE=%s\nQBT_WEBUI_PORT=%s\n' "$TT_STORAGE" "$TT_INSTANCE" "$QBT_WEBUI_PORT" > /config/tt.env
exec /entrypoint.sh
