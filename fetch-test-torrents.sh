#!/bin/sh
# Downloads the .torrent files in test-torrents.txt into torrents/test/<instance>/ (gitignored).
set -eu
cd "$(dirname "$0")"
grep -v '^#' test-torrents.txt | while read -r instance hash url; do
  out="torrents/test/$instance/$hash.torrent"
  [ -s "$out" ] && continue
  mkdir -p "${out%/*}"
  curl -sfL -o "$out" "$url" && echo "got $out" || echo "FAILED $url" >&2
done
