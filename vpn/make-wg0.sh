#!/bin/sh
# Writes /out/wg0.conf for gluetun. TT_VPN=warp (default), local (your local/wg0.conf) or fake. Runs once per `compose up`.
set -eu
cd /out

if [ "${TT_VPN:-warp}" = fake ]; then
  # Keys padded to valid 32-byte base64 so gluetun accepts the format. The handshake never completes.
  cat > wg0.conf <<CONF
[Interface]
PrivateKey = thisKeyBase64IsObviouslyFakeAAAAAAAAAAAAAAA=
Address = 10.69.69.2/32

[Peer]
PublicKey = thisKeyBase64IsObviouslyFakeBBBBBBBBBBBBBBB=
AllowedIPs = 0.0.0.0/0
Endpoint = 69.69.69.69:51820
CONF
  echo "wg0.conf: fake peer, qbt-vpn will stay offline"
  exit 0
fi

if [ "${TT_VPN:-warp}" = local ]; then
  # Any WireGuard config, e.g. from windscribe.com/getconfig/wireguard. gluetun wants an IP endpoint and we skip IPv6.
  [ -f /local/wg0.conf ] || { echo "TT_VPN=local but there's no local/wg0.conf" >&2; exit 1; }
  ep=$(sed -n 's/^Endpoint *= *//p' /local/wg0.conf); host=${ep%:*}; port=${ep##*:}
  case $host in *[!0-9.]*) ip=$(nslookup -type=a "$host" | awk '/^Address: / {a=$2} END {print a}') ;; *) ip=$host ;; esac
  [ -n "$ip" ] || { echo "can't resolve $host" >&2; exit 1; }
  sed -E \
    -e 's/^(Address *= *[^,]+),.*/\1/' \
    -e 's/^AllowedIPs *= *.*/AllowedIPs = 0.0.0.0\/0/' \
    -e "s/^Endpoint *= *.*/Endpoint = $ip:$port/" \
    -e '/^DNS *= /d' \
    /local/wg0.conf > wg0.conf
  echo "wg0.conf: local/wg0.conf via $host ($ip)"
  exit 0
fi

WGCF_VERSION=2.3.1
case "$(uname -m)" in aarch64) arch=arm64 ;; *) arch=amd64 ;; esac
[ -x wgcf ] || wget -qO wgcf "https://github.com/ViRb3/wgcf/releases/download/v$WGCF_VERSION/wgcf_${WGCF_VERSION}_linux_$arch"
chmod +x wgcf
[ -f wgcf-account.toml ] || ./wgcf register --accept-tos
./wgcf generate

# gluetun wants an IP endpoint and we skip IPv6
sed -E \
  -e 's/^(Address = [^,]+),.*/\1/' \
  -e 's/^AllowedIPs = .*/AllowedIPs = 0.0.0.0\/0/' \
  -e 's/^Endpoint = .*/Endpoint = 162.159.192.1:2408/' \
  -e '/^DNS = /d' \
  wgcf-profile.conf > wg0.conf
echo "wg0.conf: Cloudflare WARP"
