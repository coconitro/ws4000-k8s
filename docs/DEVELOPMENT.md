# Development

## Build

```bash
./build/download-ws4000.sh
docker build .
```

Or: `./build/run-local.sh`

With music: `MUSIC_MOUNT=/path/to/music ./build/run-local.sh`

With config/branding: `CONFIG_MOUNT=/path/to/config ./build/run-local.sh`

Skip VLC: `VLC_ENABLED=0 ./build/run-local.sh`

## Profile

```bash
./build/export-profile.sh
./build/import-profile.sh
./build/seed-config-volume.sh --src assets/ws4000 --dest /path/to/config
```

## GPU verify

On a GPU node:

```bash
kubectl exec deployment/ws4000-ws4000 -c streamer -- /usr/local/bin/verify-gpu-stream.sh
kubectl exec deployment/ws4000-ws4000 -c ws4000 -- /usr/local/bin/verify-ws4000-render.sh
```

## Tests

```bash
./build/test-ws4000-process.sh
```

## Publish

```bash
./build/push-image.sh          # GHCR, needs GITHUB_TOKEN
./build/publish-chart.sh       # Helm OCI to GHCR
```

GitHub Actions publishes on push to `main` when mirrored to GitHub.

## Logs

| Log | Container |
|-----|-----------|
| `/tmp/wine.log` | ws4000 |
| `/tmp/vlc.log` | ws4000 |
| streamer stdout | streamer |
