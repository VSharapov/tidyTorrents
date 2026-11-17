#!/usr/bin/env bash
# End-to-end test with the example config: fetch the test torrents, download them (throttled,
# with a restart halfway), check layout, links and IPs, try to seed back, then shut down.
# Never deletes anything it downloaded. Extra .torrent files in torrents/test/<instance>/ get tested too.
set -u
cd "$(dirname "$0")"
docker info >/dev/null 2>&1 && dc="docker compose" || dc="sudo docker compose"
conf() { sed -n "s/^$1=//p" .env 2>/dev/null | tail -1; }
storage=$(conf TT_STORAGE); storage=${storage:-$PWD/my-beloved-linux-iso-collection}
library=$(conf TT_LIBRARY); library=${library:-$PWD/penguinarr/library}
tmp=$(mktemp -d); fails=0

pass() { echo "  ok   $*"; }
fail() { echo "  FAIL $*"; fails=$((fails + 1)); }
port() { [ "$1" = qbt-raw ] && echo 8121 || echo 8122; }
login() { curl -sf -c "$tmp/$1" --data 'username=admin&password=hunter2' "localhost:$(port "$1")/api/v2/auth/login" >/dev/null; }
api() { local i=$1 path=$2; shift 2; curl -sf -b "$tmp/$i" "localhost:$(port "$i")/api/v2/$path" "$@"; }
# one line per test torrent (others in the client are ignored): hash progress state ratio
info() { api "$1" torrents/info | python3 -c 'import json,sys
for t in json.load(sys.stdin):
    if t["hash"] in sys.argv[1].split(): print(t["hash"], t["progress"], t["state"], t["ratio"])' "$tested"; }
pieces() { api "$1" "torrents/properties?hash=$2" | python3 -c 'import json,sys; print(json.load(sys.stdin)["pieces_have"])'; }
all() { info qbt-raw; info qbt-vpn; }
wait_for() { local n=$1; shift; for _ in $(seq "$n"); do "$@" && return 0; sleep 2; done; return 1; }
logins() { for i in qbt-raw qbt-vpn; do wait_for 60 login $i || fail "$i login (admin/hunter2)"; done; }
shutdown() { echo "== shutting down gracefully"; $dc down; rm -rf "$tmp"; }
trap 'shutdown; exit 130' INT TERM

echo "== fetching test torrents"; ./fetch-test-torrents.sh
tested=$(ls torrents/test/*/ 2>/dev/null | sed -n 's/\.torrent$//p' | tr '\n' ' ')
echo "== starting the stack"; $dc up -d --quiet-pull || exit 1
logins

echo "== who sees what"
house=$(curl -sf https://ifconfig.me)
raw=$($dc exec -T qbt-raw wget -qO- https://ifconfig.me)
[ -n "$house" ] && [ "$raw" = "$house" ] && pass "qbt-raw shows the house IP ($raw). The ISP is watching." \
  || fail "qbt-raw shows '$raw', house is '$house'"
$dc exec -T qbt-vpn wget -qO- https://www.cloudflare.com/cdn-cgi/trace | grep -q '^warp=on' \
  && pass "qbt-vpn is behind Cloudflare WARP. Cloudflare is watching, but they're cool." \
  || fail "qbt-vpn is not on WARP (expected if TT_VPN=fake or you set up a real VPN)"

echo "== adding torrents, throttled to 100 KiB/s so nothing finishes before the restart"
for i in qbt-raw qbt-vpn; do
  api $i app/setPreferences --data-urlencode 'json={"dl_limit":102400}' || fail "$i speed limit"
  have=$(info $i)
  for f in torrents/test/$i/*.torrent; do
    h=$(basename "$f" .torrent)
    grep -q "^$h " <<<"$have" || api $i torrents/add -F "torrents=@$f" >/dev/null || fail "$i add $h"
  done
done
start=$(date +%s)

echo "== layout"
for f in torrents/test/*/*.torrent; do
  h=$(basename "$f" .torrent) d=$storage/btih/$(basename "$f" .torrent)
  wait_for 30 test -s "$d/$h.torrent" && [ -d "$d/files" ] && [ -d "$d/extras" ] \
    && pass "btih/$h has files/, extras/ and its .torrent" || fail "btih/$h layout"
done
[ -z "$(ls -A "$storage/unsorted-pre-hook")" ] && pass "unsorted-pre-hook is empty" || fail "stuff stuck in unsorted-pre-hook"

echo "== restart mid-download"
incomplete() { for i in qbt-raw qbt-vpn; do info $i | awk -v i=$i '$2 < 1 {print i, $1}'; done; }
# Wait until every unfinished torrent has a verified piece, or there's nothing to compare.
all_have_pieces() { [ -z "$(incomplete | while read -r i h; do [ "$(pieces $i $h)" -gt 0 ] || echo x; done)" ]; }
wait_for 90 all_have_pieces || true
# Compare verified pieces: partial pieces are always lost on restart, that's just BitTorrent.
before=$(incomplete | while read -r i h; do n=$(pieces $i $h); [ "$n" -gt 0 ] && echo "$i $h $n"; done)
if [ -z "$before" ]; then
  echo "  WARN everything is already downloaded, so there is nothing to resume. Resume test skipped."
  echo "       To test resume, drop some new .torrent files into torrents/test/qbt-raw/ or qbt-vpn/."
else
  $dc restart qbt-raw qbt-vpn >/dev/null; logins; sleep 5
  while read -r i h was; do
    now=$(pieces $i $h); state=$(info $i | awk -v h="$h" '$1 == h {print $3}')
    if [[ $state == checking[DU]* ]] || [ "${now:-0}" -lt "$was" ]; then fail "$h has $now pieces ($state), had $was: that's a recheck"
    else pass "$h resumed with $now verified pieces (had $was), no recheck"; fi
  done <<<"$before"
fi
for i in qbt-raw qbt-vpn; do api $i app/setPreferences --data-urlencode 'json={"dl_limit":0}'; done

echo "== waiting for downloads, speed limit off"
done_dl() { [ -z "$(all | awk '$2 < 1')" ]; }
wait_for 900 done_dl && pass "all downloads finished" || fail "downloads still unfinished after 30 min"
dl=$(( $(date +%s) - start ))

echo "== penguinarr"
f=$(ls torrents/test/qbt-raw/*.torrent | head -1); h=$(basename "$f" .torrent)
root=$(ls "$storage/btih/$h/files" | head -1)
mkdir -p "$storage/btih/$h/extras/$root/hashes"
echo "69696969  $root" > "$storage/btih/$h/extras/$root/hashes/coolHash69.sum"
penguinarr/penguinarr
for f in torrents/test/*/*.torrent; do
  h=$(basename "$f" .torrent)
  find "$library" -lname "$storage/btih/$h/files/*" | grep -q . && pass "$h is in the library" || fail "$h not in the library"
done
find "$library" -name coolHash69.sum -lname "$storage/btih/*/extras/*" | grep -q . \
  && pass "extras: coolHash69.sum sits beside the torrent's files" || fail "coolHash69.sum missing from library"
[ -z "$(find "$library" -xtype l)" ] && pass "no dangling links" || fail "dangling links in $library"

budget=$(( dl * 2 > 60 ? dl * 2 : 60 ))
echo "== seeding back for up to ${budget}s (2x the download time) in pursuit of ratio 1.0"
ratio_ok() { [ -z "$(all | awk '$4 < 1')" ]; }
if wait_for $(( budget / 2 )) ratio_ok; then pass "ratio 1.0 everywhere. Someone out there really needed these."
else echo "  ...ratio still under 1.0. The community thanks you for your generosity and took nothing in return."; fi

shutdown
[ "$fails" = 0 ] && echo "== PASS" || { echo "== $fails FAILED"; exit 1; }
