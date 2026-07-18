# Deployment

## Prerequisites

Music directory on the node (or NFS). **Not bundled in this repo** — add your own XSPF playlist and MP3s:

```text
/path/on/host/ws4000-music/
  ws4000-all.xspf    # VLC playlist (optional; set vlc.playlist)
  *.mp3
```

Config/branding on NFS or hostPath when `config.enabled: true`:

```text
apps/ws4000-config/
  profile.dat
  Config.w4k
  ws4000-logo.png
  ws4000-background.jpg
```

Seed locally: `./build/seed-config-volume.sh --src assets/ws4000 --dest /path/to/config`

## Install

```bash
cp deploy/helm/ws4000/values.example.yaml my-values.yaml
helm upgrade --install ws4000 oci://ghcr.io/coconitro/ws4000 \
  -f my-values.yaml \
  --set kick.streamKey=YOUR_KEY \
  --set kick.rtmpUrl=YOUR_RTMP_URL
```

## Required values

| Value | Description |
|-------|-------------|
| `kick.streamKey` | Kick stream key |
| `kick.rtmpUrl` | Kick RTMP URL |
| `hostPaths.music` | Music directory (or set `nfs.server`) |
| `ingress.host` | Web VNC hostname |
| `ingress.basicAuth.password` | When basic auth enabled |

## Config volume

Enable external profile/config/branding:

```yaml
config:
  enabled: true
  type: nfs          # hostPath | nfs | pvc
  seedFromImage: false
  nfs:
    subPath: apps/ws4000-config   # export inherits nfs.export unless set here

branding:
  streamLogo: ws4000-logo.png
  x11Background: ws4000-background.jpg

stream:
  logo: /config/ws4000-logo.png
```

## GPU stream encode

See [GPU.md](GPU.md). Quick start:

```bash
helm upgrade ws4000 ./deploy/helm/ws4000 \
  --reuse-values \
  --set gpu.enabled=true \
  --set gpu.supplementalGroups={109}
```

## Taiganet ServerTime proxy (optional)

WS4000 fetches `https://www.taiganet.com/tm.php` for ServerTime (8-byte unix timestamp) before continuing to tgftp / `v4data`. That endpoint often hangs or bans cloud egress.

```yaml
taiganetTimeProxy:
  enabled: true
```

This adds a pod sidecar that answers `/tm.php` locally and reverse-proxies other taiganet paths upstream.

## Web UI

| URL | Purpose |
|-----|---------|
| `http://<ingress.host>/` | Landing page |
| `http://<ingress.host>/vnc.html` | Simulation console |
| `http://<ingress.host>/export/profile.dat` | Profile download |

## Upgrade

```bash
helm upgrade ws4000 oci://ghcr.io/coconitro/ws4000 -f my-values.yaml --set image.tag=latest
```
