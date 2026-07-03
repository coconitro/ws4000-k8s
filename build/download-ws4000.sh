#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${DEST:-${ROOT}/assets/ws4000}"
URL="${WS4000_DOWNLOAD_URL:-https://www.taiganet.com/dlv4new.php?os_type=win&public=1&dl_type=archive}"

need_download=0
for f in WS4000v4.exe Data.000 fmod64.dll; do
  if [ ! -f "${DEST}/${f}" ]; then
    need_download=1
    break
  fi
done

if [ "$need_download" = "0" ]; then
  echo "WS4000 binaries already present in ${DEST}"
  exit 0
fi

echo "=== Downloading WS4000 archive ==="
mkdir -p "${DEST}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

archive="${tmpdir}/ws4000-archive"
curl -fL "$URL" -o "$archive"

extract_dir="${tmpdir}/extract"
mkdir -p "$extract_dir"

if file "$archive" | grep -qi 'zip'; then
  unzip -q "$archive" -d "$extract_dir"
elif file "$archive" | grep -Eiq '7-zip|7z'; then
  if command -v 7z >/dev/null 2>&1; then
    7z x "$archive" -o"$extract_dir" >/dev/null
  elif command -v 7za >/dev/null 2>&1; then
    7za x "$archive" -o"$extract_dir" >/dev/null
  else
    echo "ERROR: 7z archive but 7z/7za not installed" >&2
    exit 1
  fi
else
  # Try unzip first, then 7z
  if unzip -t "$archive" >/dev/null 2>&1; then
    unzip -q "$archive" -d "$extract_dir"
  elif command -v 7z >/dev/null 2>&1; then
    7z x "$archive" -o"$extract_dir" >/dev/null
  else
    echo "ERROR: unknown archive format: $(file -b "$archive")" >&2
    exit 1
  fi
fi

echo "=== Extracting into ${DEST} ==="
shopt -s nullglob globstar
found_exe=()
while IFS= read -r -d '' exe; do
  found_exe+=("$exe")
done < <(find "$extract_dir" -name 'WS4000v4.exe' -print0 2>/dev/null)

if [ "${#found_exe[@]}" -eq 0 ]; then
  echo "ERROR: WS4000v4.exe not found in archive" >&2
  exit 1
fi

src_dir="$(dirname "${found_exe[0]}")"
cp -a "${src_dir}/." "${DEST}/"

for f in WS4000v4.exe Data.000 fmod64.dll; do
  if [ ! -f "${DEST}/${f}" ]; then
    echo "ERROR: missing ${f} after extract" >&2
    exit 1
  fi
done

# Normalize archive casing to Config.w4k (WS4000 expects this name)
if [ -f "${DEST}/config.w4k" ] && [ ! -f "${DEST}/Config.w4k" ]; then
  cp -f "${DEST}/config.w4k" "${DEST}/Config.w4k"
fi

echo "WS4000 bundle ready in ${DEST}"
ls -la "${DEST}/WS4000v4.exe" "${DEST}/Data.000" "${DEST}/fmod64.dll"
