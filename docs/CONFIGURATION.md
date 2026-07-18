# Configuration

Helm defaults: `deploy/helm/ws4000/values.yaml`. Starter: `values.example.yaml`.

GPU details: [GPU.md](GPU.md)

## Required at install

| Value | Description |
|-------|-------------|
| `kick.streamKey` | Kick RTMP stream key |
| `kick.rtmpUrl` | Kick RTMP ingest URL |
| `hostPaths.music` | Node music dir (when NFS unset) |
| `ingress.basicAuth.password` | When `ingress.basicAuth.enabled` |

## Key values

| Value | Default | Description |
|-------|---------|-------------|
| `image.repository` | `ghcr.io/coconitro/ws4000` | Container image |
| `image.tag` | `latest` | Image tag |
| `config.enabled` | `false` | Mount profile/config from volume |
| `config.type` | `hostPath` | `hostPath`, `nfs`, or `pvc` |
| `vlc.enabled` | `true` | VLC background playlist |
| `vlc.playlist` | `/music/ws4000-all.xspf` | Playlist path |
| `gpu.enabled` | `false` | Streamer VAAPI encode |
| `gpu.ws4000Enabled` | `false` | Sim DXVK rendering |
| `ingress.host` | `ws4000.example.com` | Ingress hostname |
| `novnc.enabled` | `true` | Web VNC sidecar |
| `profileExport.enabled` | `true` | Profile HTTP export |
| `taiganetTimeProxy.enabled` | `false` | Stub `tm.php` ServerTime locally when the real endpoint hangs or bans cloud IPs, so the sim can proceed to tgftp |

## Environment variables (ws4000 container)

| Variable | Default | Description |
|----------|---------|-------------|
| `RESOLUTION` | `800x600` | Desktop size |
| `MUSIC_DIR` | `/music` | Music directory |
| `VLC_ENABLED` | `1` | Set `0` to skip VLC |
| `PLAYLIST` | from Helm | VLC playlist |
| `X11_BACKGROUND` | unset | Wallpaper when sim down |
| `PROFILE_SYNC_INTERVAL` | `15` | Profile export sync seconds |

## Streamer env vars

Set via `stream.*` and `gpu.*` Helm values. See [GPU.md](GPU.md) for `STREAM_USE_GPU`, `STREAM_GPU_MODE`, etc.
