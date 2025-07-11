# tidyTorrents

qBittorrent in docker, with VPN and an organization UI

## The dream

torrents are stored in a flat structure, e.g.:

```sh
$  tree /torrents/
/torrents/
└── btih
    ├── 563e7281c000e18091e5c0d39d098cff135dab26
    │   ├── v2.torrent
    │   └── files
    │       └── debian-12.8.0-amd64-DVD-1.iso
    └── d3dbf9bf61ebe9207284be8795bb39ffe0506b50
        ├── v2.torrent
        └── files
            └── CentOS-Stream-9-20240610.0-x86_64-boot.iso

6 directories, 4 files
```

Now your library can just be a bunch of symlinks.
How do you enable normies to add stuff?
Expose a webUI - they provide a torrent/magnet, and 1 or more library path, e.g.:
`/Media/Books/Melville, Herman/Moby-Dick, /Media/Books/Melville, Herman/Whale, The`
Use the [qBittorrent WebUI API][qbt-web-api] or [cli][qbt-cli] to properly locate the content.
Create a torrent file to enable resuming without reliance on DHT.
Create symlinks from the library path(s) to the torrent infohash.
Of course, your torrent client needs a VPN config so that none of your linx rivals at the local ISP know which distros you're into.

[qbt-web-api]: https://github.com/qbittorrent/qBittorrent/wiki/#webui-api
[wbt-cli]: https://github.com/ludviglundgren/qbittorrent-cli

## The plan

A docker compose file that runs the BT client, with VPN, And the normie-friendly webUI.
