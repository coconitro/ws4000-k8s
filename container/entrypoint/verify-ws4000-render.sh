#!/bin/bash
# Verify WS4000 D3D8 rendering path (DXVK + optional GPU).
# Run inside the ws4000 container after deploy:
#   kubectl exec -it deployment/ws4000-ws4000 -c ws4000 -- /usr/local/bin/verify-ws4000-render.sh
set -euo pipefail

export WINEPREFIX="${WINEPREFIX:-/wineprefix}"
export WINEARCH="${WINEARCH:-win64}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-d3d8=n;d3d9=n;d3d11=n;dxgi=n}"
WINE="/opt/wine-ge/bin/wine64"
GPU_DEVICE="${WS4000_GPU_DEVICE:-/dev/dri/renderD128}"

echo "=== DXVK DLLs ==="
for dll in d3d8 d3d9 d3d11 dxgi; do
  path="/wineprefix/drive_c/windows/system32/${dll}.dll"
  if [ -f "$path" ]; then
    echo "OK: $path"
    ls -la "$path"
  else
    echo "MISSING: $path"
  fi
done

echo ""
echo "=== Wine DLL overrides ==="
"$WINE" reg query 'HKCU\Software\Wine\DllOverrides' 2>/dev/null \
  | grep -E 'd3d8|d3d9|d3d11|dxgi' || echo "WARNING: no DXVK overrides in registry"

echo ""
echo "=== GPU device (${WS4000_USE_GPU:-0}) ==="
if [ "${WS4000_USE_GPU:-0}" = "1" ]; then
  if [ -e "$GPU_DEVICE" ]; then
    echo "OK: $GPU_DEVICE present"
    ls -la /dev/dri/ 2>/dev/null || true
  else
    echo "FAIL: WS4000_USE_GPU=1 but $GPU_DEVICE missing"
    exit 1
  fi
else
  echo "WS4000_USE_GPU not set — D3D8 may use CPU lavapipe/wined3d"
fi

echo ""
echo "=== OpenGL driver ==="
PID=$(pgrep -f "WS4000v4.exe" | head -1 || true)
if [ -n "$PID" ] && [ -r "/proc/$PID/maps" ]; then
  if grep -qE 'radeon|amdgpu' /proc/$PID/maps 2>/dev/null && ! grep -q swrast /proc/$PID/maps 2>/dev/null; then
    echo "OK: AMD GPU DRI loaded in WS4000 process"
    grep -E 'radeon|amdgpu' /proc/$PID/maps 2>/dev/null | head -3
  elif grep -q zink /proc/$PID/maps 2>/dev/null; then
    echo "INFO: zink loaded"
    grep zink /proc/$PID/maps 2>/dev/null | head -3
  elif grep -q swrast /proc/$PID/maps 2>/dev/null; then
    echo "WARN: still using software swrast (CPU-bound OpenGL)"
    grep swrast /proc/$PID/maps 2>/dev/null | head -3
  else
    echo "INFO: no GL driver maps yet (sim may still be starting)"
  fi
else
  echo "WS4000 process not running yet"
fi
echo "WS4000_USE_XORG=${WS4000_USE_XORG:-unset} WS4000_USE_ZINK=${WS4000_USE_ZINK:-unset} MESA_LOADER_DRIVER_OVERRIDE=${MESA_LOADER_DRIVER_OVERRIDE:-unset}"
if [ -f /tmp/Xorg.99.log ]; then
  echo "=== Xorg log (last 10 lines) ==="
  tail -10 /tmp/Xorg.99.log 2>/dev/null || true
fi

if command -v vulkaninfo >/dev/null 2>&1; then
  vulkaninfo --summary 2>/dev/null | head -30 || echo "vulkaninfo failed"
elif [ -n "${VK_ICD_FILENAMES:-}" ]; then
  echo "VK_ICD_FILENAMES=${VK_ICD_FILENAMES}"
else
  echo "vulkaninfo not installed; check /usr/share/vulkan/icd.d/"
  ls /usr/share/vulkan/icd.d/ 2>/dev/null || true
fi

echo ""
echo "=== WS4000 launch log (last 30 lines) ==="
tail -30 /tmp/wine.log 2>/dev/null || echo "No /tmp/wine.log yet"

echo ""
echo "=== CPU usage (ws4000 processes) ==="
ps aux 2>/dev/null | grep -E 'WS4000|wine|Xorg|Xvfb' | grep -v grep || true

echo ""
echo "Pass: run 'kubectl top pod -l app.kubernetes.io/name=ws4000 --containers' while simulation is active."
echo "Pass: DXVK HUD — set DXVK_HUD=fps,device on ws4000 container and confirm GPU name (not llvmpipe)."
