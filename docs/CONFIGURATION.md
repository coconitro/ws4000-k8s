# Configuration

Helm defaults: `deploy/helm/ws4000/values.yaml`. Starter: `values.example.yaml`.

GPU details: [GPU.md](GPU.md)

## Required at install

| Value | Description |
|-------|-------------|
| `kick.streamKey` | Kick RTMP stream key |
| `kick.rtmpUrl` | Kick RTMP ingest URL |
| `kick.channelSlug` | Kick channel slug (for live health check) |
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
| `freezeDetection.enabled` | `true` | Restart pod when sim freezes or exits |
| `taiganetTimeProxy.enabled` | `false` | Stub `tm.php` ServerTime locally when the real endpoint hangs or bans cloud IPs, so the sim can proceed to tgftp |

## Kick stream health check

Runs inside the **streamer** container (not a separate sidecar). When enabled, a background loop checks every `kick.healthCheck.intervalSeconds` (default **600** = 10 minutes) whether ffmpeg is running and, if `kick.channelSlug` is set, whether Kick reports the channel as live.

| Value | Default | Description |
|-------|---------|-------------|
| `kick.healthCheck.enabled` | `false` | Enable periodic Kick live verification |
| `kick.healthCheck.intervalSeconds` | `600` | Seconds between checks |
| `kick.healthCheck.restartOnFailure` | `true` | Kill ffmpeg to force reconnect when not live |
| `kick.channelSlug` | `""` | Your Kick channel slug (required for remote live check) |
| `kick.healthCheck.apiAccessToken` | `""` | Optional Kick API token (`channel:read`) if the public API is blocked |

Example:

```yaml
kick:
  streamKey: "YOUR_KEY"
  rtmpUrl: "YOUR_RTMP_URL"
  channelSlug: "your-channel"
  healthCheck:
    enabled: true
```

## Environment variables (ws4000 container)

| Variable | Default | Description |
|----------|---------|-------------|
| `RESOLUTION` | `800x600` | Desktop size |
| `MUSIC_DIR` | `/music` | Music directory |
| `VLC_ENABLED` | `1` | Set `0` to skip VLC |
| `PLAYLIST` | from Helm | VLC playlist |
| `X11_BACKGROUND` | unset | Wallpaper when sim down (`ws4000-background.jpg`) |
| `X11_FALLBACK_COLOR` | `#0b1a3a` | Solid color when no wallpaper file is available |
| `PROFILE_SYNC_INTERVAL` | `15` | Profile export sync seconds |

## Streamer env vars

Set via `stream.*` and `gpu.*` Helm values. See [GPU.md](GPU.md) for `STREAM_USE_GPU`, `STREAM_GPU_MODE`, etc.

Kick health check (streamer container only): `KICK_HEALTH_CHECK_ENABLED`, `KICK_HEALTH_CHECK_INTERVAL` (default `600`), `KICK_CHANNEL_SLUG`, `KICK_HEALTH_CHECK_RESTART_ON_FAIL`, `KICK_API_ACCESS_TOKEN`.

## Freeze detection notes

Health checks look for the real `WS4000v4.exe` process, not Wine's
`explorer /desktop=... WS4000v4.exe` parent. If only the virtual desktop is
left (black screen with VLC music still playing), the container treats the
sim as dead, tears down Wine so the X11 wallpaper is visible on Kick, then
exits so Kubernetes restarts the pod.

Soft recovery is attempted once per freeze; the flag clears only after the
display hash changes again, so a stuck black frame cannot soft-recover forever.