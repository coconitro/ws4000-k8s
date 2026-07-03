#!/bin/bash
set -euo pipefail

export DISPLAY="${DISPLAY:-:99}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/pulse/run}"
export PULSE_SERVER="${PULSE_SERVER:-unix:${XDG_RUNTIME_DIR}/pulse/native}"

RES="${RESOLUTION:-800x600}"
KICK_URL="${KICK_RTMP_URL:?KICK_RTMP_URL is required}"
KICK_KEY="${KICK_STREAM_KEY:?KICK_STREAM_KEY is required}"
KICK_OUT="${KICK_URL%/}/app/${KICK_KEY}"
KICK_OUT="${KICK_URL%/}/app/${KICK_KEY}"

FPS="${STREAM_FPS:-30}"
VBIT="${STREAM_VIDEO_BITRATE:-3500k}"
VMAX="${STREAM_VIDEO_MAXRATE:-3500k}"
VBUF="${STREAM_VIDEO_BUFSIZE:-10000k}"
ABIT="${STREAM_AUDIO_BITRATE:-160k}"
X264_PRESET="${STREAM_X264_PRESET:-ultrafast}"
GOP=$((FPS * 2))
OUT_W="${STREAM_OUTPUT_WIDTH:-1280}"
OUT_H="${STREAM_OUTPUT_HEIGHT:-720}"
USE_GPU="${STREAM_USE_GPU:-0}"
GPU_MODE="${STREAM_GPU_MODE:-vaapi}"
VAAPI_DEVICE="${STREAM_VAAPI_DEVICE:-/dev/dri/renderD128}"
LOGO="${STREAM_LOGO:-}"
LOGO_H="${STREAM_LOGO_HEIGHT:-60}"
LOGO_MARGIN="${STREAM_LOGO_MARGIN:-10}"
LOGO_ALPHA="${STREAM_LOGO_ALPHA:-0.7}"
USE_LOGO=0
if [ -n "$LOGO" ] && [ -f "$LOGO" ]; then
  USE_LOGO=1
fi

FILTER_SCALE="[0:v]fps=${FPS}:round=up,setpts=N/${FPS}/TB[cap];[cap]scale=${OUT_W}:${OUT_H}:force_original_aspect_ratio=decrease:flags=lanczos,pad=${OUT_W}:${OUT_H}:(ow-iw)/2:(oh-ih)/2:black"
FILTER_HYBRID_SCALE="[0:v]fps=${FPS}:round=up,setpts=N/${FPS}/TB[cap];[cap]format=nv12,hwupload[gpuin];[gpuin]scale_vaapi=w=${OUT_W}:h=${OUT_H}:force_original_aspect_ratio=decrease[scaled];[scaled]hwdownload,format=nv12[scaledcpu];[scaledcpu]pad=${OUT_W}:${OUT_H}:(ow-iw)/2:(oh-ih)/2:black"

if [ "$USE_LOGO" = "1" ]; then
  FILTER_BASE="${FILTER_SCALE}[padded];[1:v]scale=-2:${LOGO_H},format=rgba,colorchannelmixer=aa=${LOGO_ALPHA}[logo];[padded][logo]overlay=x=main_w-overlay_w-${LOGO_MARGIN}:y=main_h-overlay_h-${LOGO_MARGIN}[v]"
  FILTER_HYBRID="${FILTER_HYBRID_SCALE}[padded];[1:v]scale=-2:${LOGO_H},format=rgba,colorchannelmixer=aa=${LOGO_ALPHA}[logo];[padded][logo]overlay=x=main_w-overlay_w-${LOGO_MARGIN}:y=main_h-overlay_h-${LOGO_MARGIN}[v]"
  INPUT_COMMON=(
    -fflags nobuffer+genpts -thread_queue_size 2048
    -rtbufsize 100M -f x11grab -draw_mouse 0 -framerate "$FPS" -video_size "$RES" -i :99
    -thread_queue_size 2048 -loop 1 -framerate "$FPS" -i "$LOGO"
  )
  AUDIO_MAP=2:a
else
  FILTER_BASE="${FILTER_SCALE}[v]"
  FILTER_HYBRID="${FILTER_HYBRID_SCALE}[v]"
  INPUT_COMMON=(
    -fflags nobuffer+genpts -thread_queue_size 2048
    -rtbufsize 100M -f x11grab -draw_mouse 0 -framerate "$FPS" -video_size "$RES" -i :99
  )
  AUDIO_MAP=1:a
fi

echo "Waiting for X11 display and PulseAudio from ws4000..."
for i in $(seq 1 90); do
  X11_OK=0
  PULSE_OK=0
  [ -S /tmp/.X11-unix/X99 ] && X11_OK=1
  [ -S /tmp/pulse/run/pulse/native ] && PULSE_OK=1
  [ "$X11_OK" = 1 ] && [ "$PULSE_OK" = 1 ] && break
  if [ $((i % 5)) -eq 0 ]; then
    echo "  still waiting (${i}/90): X11=$X11_OK PulseAudio=$PULSE_OK"
    ls -la /tmp/.X11-unix/ /tmp/pulse/run/pulse/ 2>/dev/null || true
  fi
  sleep 2
done

if [ ! -S /tmp/.X11-unix/X99 ] || [ ! -S /tmp/pulse/run/pulse/native ]; then
  echo "ERROR: ws4000 not ready (missing X99 or PulseAudio socket after 3 min)"
  ls -laR /tmp/.X11-unix /tmp/pulse 2>/dev/null || true
  exit 1
fi

ENCODER_MODE="CPU libx264"
STREAM_FUNC=stream_cpu_x264

if [ "$USE_GPU" = "1" ]; then
  export LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-radeonsi}"
  if [ ! -e "$VAAPI_DEVICE" ]; then
    echo "ERROR: GPU encoding enabled but $VAAPI_DEVICE not found"
    ls -la /dev/dri/ 2>/dev/null || true
    exit 1
  fi
  echo "GPU enabled — checking VAAPI ($VAAPI_DEVICE, driver=$LIBVA_DRIVER_NAME, mode=$GPU_MODE)..."
  vainfo --display drm --device "$VAAPI_DEVICE" 2>&1 || true

  # Kick requires strict CBR for hardware encoders; match bufsize to target bitrate.
  VBUF="$VBIT"
  VMAX="$VBIT"

  case "$GPU_MODE" in
    vaapi)
      ENCODER_MODE="VAAPI h264_vaapi -> H.264 pipe -> FLV remux"
      STREAM_FUNC=stream_gpu_vaapi_mkv
      ;;
    hybrid)
      ENCODER_MODE="hybrid scale_vaapi + libx264"
      STREAM_FUNC=stream_gpu_hybrid
      ;;
    amf)
      ENCODER_MODE="AMF h264_amf"
      STREAM_FUNC=stream_gpu_amf
      ;;
    *)
      echo "ERROR: unknown STREAM_GPU_MODE=$GPU_MODE (expected vaapi, hybrid, or amf)"
      exit 1
      ;;
  esac
fi

X264_COMMON=(
  -c:v libx264 -preset "$X264_PRESET" -tune zerolatency -profile:v high -threads 0
  -b:v "$VBIT" -maxrate "$VMAX" -bufsize "$VBUF"
  -x264-params "nal-hrd=cbr:force-cfr=1:bframes=0:ref=1:rc-lookahead=0:sync-lookahead=0:aq-mode=0"
  -g "$GOP" -keyint_min "$GOP" -sc_threshold 0
  -pix_fmt yuv420p -vsync cfr
)

AUDIO_COMMON=(
  -c:a aac -b:a "$ABIT" -ar 48000
  -max_interleave_delta 0
)

stream_cpu_x264() {
  ffmpeg "${INPUT_COMMON[@]}" \
    -thread_queue_size 2048 -f pulse -i default \
    -filter_complex "$FILTER_BASE" \
    -map "[v]" -map "$AUDIO_MAP" \
    "${X264_COMMON[@]}" \
    "${AUDIO_COMMON[@]}" \
    -f flv "$KICK_OUT" || true
}

stream_gpu_vaapi_mkv() {
  # AMD h264_vaapi cannot write AVCC extradata for FLV directly. Encode to an
  # Annex B H.264 bytestream (in-band SPS/PPS), then remux to Kick FLV.
  # Do NOT set -global_header — Mesa VAAPI uses in-band headers only.
  ffmpeg -vaapi_device "$VAAPI_DEVICE" \
    "${INPUT_COMMON[@]}" \
    -filter_complex "${FILTER_BASE};[v]format=nv12,hwupload[vout]" \
    -map "[vout]" -an \
    -c:v h264_vaapi -profile:v high \
    -b:v "$VBIT" -maxrate "$VMAX" -bufsize "$VBUF" \
    -rc_mode CBR -g "$GOP" -bf 0 \
    -f h264 - \
  | ffmpeg -hide_banner -loglevel warning \
    -probesize 500000 -analyzeduration 500000 \
    -fflags nobuffer+genpts \
    -thread_queue_size 2048 \
    -framerate "$FPS" -f h264 -i pipe:0 \
    -thread_queue_size 2048 -f pulse -i default \
    -map 0:v -map 1:a \
    -c:v copy -bsf:v dump_extra \
    "${AUDIO_COMMON[@]}" \
    -f flv "$KICK_OUT" || true
}

stream_gpu_hybrid() {
  ffmpeg -vaapi_device "$VAAPI_DEVICE" \
    "${INPUT_COMMON[@]}" \
    -thread_queue_size 2048 -f pulse -i default \
    -filter_complex "$FILTER_HYBRID" \
    -map "[v]" -map "$AUDIO_MAP" \
    "${X264_COMMON[@]}" \
    "${AUDIO_COMMON[@]}" \
    -f flv "$KICK_OUT" || true
}

stream_gpu_amf() {
  if ! ffmpeg -hide_banner -encoders 2>/dev/null | grep -q ' h264_amf '; then
    echo "ERROR: h264_amf encoder not available in this ffmpeg build."
    echo "  AMF requires a custom ffmpeg compiled with --enable-amf."
    echo "  Use gpu.mode=vaapi (default) or gpu.mode=hybrid instead."
    exit 1
  fi
  ffmpeg "${INPUT_COMMON[@]}" \
    -thread_queue_size 2048 -f pulse -i default \
    -filter_complex "$FILTER_BASE" \
    -map "[v]" -map "$AUDIO_MAP" \
    -c:v h264_amf -profile:v high \
    -quality quality -rc cbr \
    -b:v "$VBIT" -maxrate "$VMAX" -bufsize "$VBUF" \
    -g "$GOP" -bf 0 \
    "${AUDIO_COMMON[@]}" \
    -f flv "$KICK_OUT" || true
}

echo "Ready — starting ffmpeg stream (capture ${RES} -> ${OUT_W}x${OUT_H} 16:9, ${FPS}fps ${VBIT}, ${ENCODER_MODE})"
while true; do
  "$STREAM_FUNC"
  echo "Stream dropped, restarting..."
  sleep 5
done
