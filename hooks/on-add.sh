#!/bin/sh
# qBittorrent "run on torrent added": $1=%I (v1 hash, "-" if pure v2), $2=%K (torrent ID).
# Files the torrent under btih/<hash>/files, starts it, and saves its .torrent beside it.
set -u
. /config/tt.env
hash=$1; [ "$hash" = - ] && hash=$2
id=$2
api="http://localhost:$QBT_WEBUI_PORT/api/v2/torrents"
dir="$TT_STORAGE/btih/$hash"
log() { echo "$(date -Iseconds) $TT_INSTANCE $hash $*" >> "$TT_STORAGE/on-add.log"; }

mkdir -p "$dir/files" "$dir/extras"
curl -sf "$api/setLocation" -d "hashes=$id" --data-urlencode "location=$dir/files" || { log "setLocation failed"; exit 1; }
# archive.org rewrites its own _meta files, so webseeds can never finish them. Skip them.
skip=$(curl -sf "$api/files?hash=$id" | python3 -c 'import json,sys
print("|".join(str(f["index"]) for f in json.load(sys.stdin) if "_meta." in f["name"]))')
[ -n "$skip" ] && curl -sf "$api/filePrio" -d "hash=$id&id=$skip&priority=0"
curl -sf "$api/start" -d "hashes=$id" || log "start failed"
log "filed"

# Magnets have no metadata yet, so keep trying the export for a while.
for _ in $(seq 60); do
  curl -sf "$api/export?hash=$id" -o "$dir/.$hash.torrent.part" && mv "$dir/.$hash.torrent.part" "$dir/$hash.torrent" && { log "exported"; exit 0; }
  sleep 10
done
rm -f "$dir/.$hash.torrent.part"
log "export gave up"
