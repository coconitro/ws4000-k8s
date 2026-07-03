# ws4000-k8s

WS4000 simulator in Docker/Wine. Streams to Kick via ffmpeg sidecar.

## Setup

```bash
./build/download-ws4000.sh   # first time
./build/run-local.sh         # http://localhost:6080/vnc.html
```

## Kubernetes

```bash
cp deploy/helm/ws4000/values.example.yaml my-values.yaml
# edit kick keys, music path, ingress host
helm upgrade --install ws4000 oci://ghcr.io/coconitro/ws4000 -f my-values.yaml
```

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md). GPU: [docs/GPU.md](docs/GPU.md).

## Scripts

| Script | Purpose |
|--------|---------|
| `./build/run-local.sh` | Local Docker test |
| `./build/push-image.sh` | Build and push to GHCR |
| `./build/publish-chart.sh` | Publish Helm chart to GHCR |
| `./build/export-profile.sh` | Pull profile.dat from cluster |
| `./build/seed-config-volume.sh` | Copy config files to NFS/host path |

Simulator binaries are not in git. Run `./build/download-ws4000.sh` before building.
