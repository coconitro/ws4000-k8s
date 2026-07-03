#!/bin/bash
# Validate AMD VAAPI encode -> H.264 pipe -> FLV remux produces Kick-compatible headers.
# Run inside the streamer container on a GPU node:
#   kubectl exec -it deployment/ws4000-ws4000 -c streamer -- /usr/local/bin/verify-gpu-stream.sh
set -euo pipefail

VAAPI_DEVICE="${STREAM_VAAPI_DEVICE:-/dev/dri/renderD128}"
export LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-radeonsi}"

if [ ! -e "$VAAPI_DEVICE" ]; then
  echo "FAIL: $VAAPI_DEVICE not found"
  ls -la /dev/dri/ 2>/dev/null || true
  exit 1
fi

echo "=== vainfo ==="
vainfo --display drm --device "$VAAPI_DEVICE" 2>&1 | grep -E 'H264|EncSlice|Driver' || true

echo "=== VAAPI encode -> H.264 bytestream (5s testsrc) ==="
ffmpeg -hide_banner -loglevel error -y \
  -vaapi_device "$VAAPI_DEVICE" \
  -f lavfi -i "testsrc=duration=5:size=1280x720:rate=30" \
  -vf 'format=nv12,hwupload' \
  -c:v h264_vaapi -profile:v high -b:v 3500k -maxrate 3500k -bufsize 3500k \
  -rc_mode CBR -g 60 -bf 0 \
  -f h264 /tmp/ws4000-gpu-test.h264

echo "=== H.264 -> FLV remux (copy + dump_extra) ==="
ffmpeg -hide_banner -loglevel error -y \
  -framerate 30 -f h264 -i /tmp/ws4000-gpu-test.h264 \
  -c:v copy -bsf:v dump_extra \
  -an -f flv /tmp/ws4000-gpu-test.flv

FLV_EXTRA=$(ffprobe -v error -select_streams v:0 -show_entries stream=extradata_size -of csv=p=0 /tmp/ws4000-gpu-test.flv)
echo "FLV extradata_size: ${FLV_EXTRA:-0}"

if [ "${FLV_EXTRA:-0}" -gt 0 ] 2>/dev/null; then
  echo "PASS: FLV has AVCC extradata — Kick ingest should accept this pipeline."
  exit 0
fi

echo "FAIL: FLV extradata is empty — Kick will reject the stream."
echo "Try gpu.mode=hybrid (scale_vaapi + libx264) instead of vaapi."
exit 1
