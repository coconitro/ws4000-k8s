# GPU acceleration

AMD GPU support on Linux nodes with `/dev/dri`. Two independent toggles.

## Stream encoding (`gpu.enabled`)

Offloads ffmpeg H.264 encode to the GPU (VAAPI). Lowers streamer CPU.

Default mode: `gpu.mode: vaapi`

Pipeline: capture X11 → `h264_vaapi` → H.264 pipe → FLV remux (Kick needs AVCC headers). Direct VAAPI→FLV fails on AMD Mesa.

### Quick start

```bash
helm upgrade --install ws4000 oci://ghcr.io/coconitro/ws4000 \
  -f my-values.yaml \
  --set gpu.enabled=true \
  --set gpu.mode=vaapi \
  --set gpu.supplementalGroups={109}
```

Discover render group GID: `getent group render`

### Verify

```bash
kubectl exec deployment/ws4000-ws4000 -c streamer -- /usr/local/bin/verify-gpu-stream.sh
```

### Modes

| Mode | What |
|------|------|
| `vaapi` | Full GPU H.264 encode (recommended) |
| `hybrid` | GPU scale, CPU libx264 encode |
| `amf` | Needs custom ffmpeg with `--enable-amf` |

### Troubleshooting

- **EPERM on `/dev/dri`** — set `gpu.privileged: true` or use AMD GPU device plugin
- **Kick not live** — run verify script; try `--set gpu.mode=hybrid`

## Simulator rendering (`gpu.ws4000Enabled`)

Optional. DXVK + Xorg for lower WS4000 CPU. Default off. Separate from stream encode.

```bash
helm upgrade ws4000 ./deploy/helm/ws4000 \
  --reuse-values \
  --set gpu.ws4000Enabled=true \
  --set gpu.privileged=true
```

Verify:

```bash
kubectl exec deployment/ws4000-ws4000 -c ws4000 -- /usr/local/bin/verify-ws4000-render.sh
```

## Helm values

| Value | Default | Purpose |
|-------|---------|---------|
| `gpu.enabled` | `false` | Streamer VAAPI encode |
| `gpu.ws4000Enabled` | `false` | Sim DXVK rendering |
| `gpu.mode` | `vaapi` | Encode pipeline |
| `gpu.device` | `/dev/dri/renderD128` | Render node |
| `gpu.libvaDriverName` | `radeonsi` | LIBVA driver |
| `gpu.mountHostDri` | `true` | Mount host `/dev/dri` |
| `gpu.supplementalGroups` | `[]` | Render group GID(s) |
| `gpu.privileged` | `false` | cgroup v2 DRI access |
| `gpu.nodeSelector` | `{}` | Schedule on GPU nodes |

See `values.example.yaml` for a full starter file.
