# tidyTorrents

qBittorrent in docker, twice, with infohash-addressed storage and a library made of links.

## The dream

Every torrent lives in exactly one place, named by its infohash:

```sh
$ tree my-beloved-linux-iso-collection/
my-beloved-linux-iso-collection/
├── btih
│   ├── 19f13ac2519b70a34b903bc237d552333741a9f8
│   │   ├── 19f13ac2519b70a34b903bc237d552333741a9f8.torrent   # resume without DHT
│   │   ├── files/                                             # what the torrent says; qbt owns it
│   │   │   └── nanolinux64-1.3_202109/nanolinux64-1.3.iso
│   │   └── extras/                                            # what you added; same tree shape
│   │       └── nanolinux64-1.3_202109/hashes/coolHash69.sum
│   └── fe5e0a71d4de0e4eab40bd5bd15a86051dc19d59
│       └── ...
└── unsorted-pre-hook/                                         # empty, unless the hook broke
```

Your library is just a bunch of links pointing in. A library entry shows `files/` and `extras/`
merged, so `coolHash69.sum` sits right next to the torrent's own files, and nothing the torrent
owns ever gets touched. qBittorrent never sees `extras/`, so a recheck stays clean and
"delete with files" can't eat your notes.

## Two clients, one disk

Of course, your torrent client needs a VPN so that none of your linux rivals at the local ISP
know which distros you're into. But an ISP that sees *no* torrenting gets suspicious. So:

- **qbt-raw**: straight onto the ISP's pipe, for performative torrenting. Let them watch you seed
  NanoLinux64 and Tiny Core Pure64. Let them conclude you are cool.
- **qbt-vpn**: behind a VPN, for secretly torrenting the boring Linux ISOs you actually desire.

Both write to the same `btih/`. Don't add the same torrent to both. If you do, whatever happens happens.

The VPN is **Cloudflare WARP** by default: registered anonymously on first start, no signup, no
data cap. Cloudflare keeps logs, and says itself that WARP "is not designed to hide your identity".
This is fine. This repo is for educational purposes only and legally downloads Linux ISOs, so we
have nothing to fear. Nothing at all. Set `TT_VPN=fake` for an obviously fake WireGuard peer that
keeps qbt-vpn offline, or uncomment the PrivadoVPN block in `.env` if you sign up for a real one.

## Quick start

```sh
cp .env.example .env    # optional; point TT_STORAGE at your NAS here
docker compose up -d
```

- qbt-raw WebUI: http://localhost:8121, qbt-vpn WebUI: http://localhost:8122. Login `admin` / `hunter2`.
- Add torrents in the WebUI. They're added stopped into `unsorted-pre-hook/`; the on-add hook moves
  them to `btih/<hash>/files/`, saves the `.torrent`, and starts them.
- Run `penguinarr/penguinarr` to rebuild the library.

## penguinarr

Radarr and Sonarr have never heard of Debian. **penguinarr** is the *arr for penguins: it groups
every torrent by the first word of its name and links it into `penguinarr/library/` (or `TT_LIBRARY`),
one absolute symlink per file. `TinyCore-11.1` goes under `tinycore/`, `tiny-core-pure-64-16.2` under
`tiny/`. Close enough. It needs no metadata, so it scrapes none.

## Testing

```sh
./test.sh
```

Downloads six tiny test torrents (about 160 MB, webseeded from archive.org) with a speed limit,
restarts both clients halfway to prove they resume without a recheck, checks the layout, the
library and who sees which IP, then tries to seed back to ratio 1.0 and shuts everything down.
It never deletes what it downloaded, so the second run can't test resume and will tell you so.

## Repo

```
compose.yaml            gluetun + qbt-vpn + qbt-raw (+ a one-shot WARP config init)
.env.example            storage path, VPN choice
vpn/make-wg0.sh         writes gluetun's wg0.conf: WARP via wgcf, or the fake peer
qbt/                    qBittorrent.conf template + init that seeds it on first start
hooks/on-add.sh         files new torrents under btih/<hash>
penguinarr/penguinarr   the *arr
test.sh                 end-to-end test; test-torrents.txt + fetch-test-torrents.sh feed it
```

Storage must be an absolute path: it's mounted at the same path in every container, so the
library's absolute symlinks resolve everywhere. Containers run as uid/gid 1000.
