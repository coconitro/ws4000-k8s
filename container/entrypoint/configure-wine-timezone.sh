#!/bin/bash
# Map the container's IANA timezone to Wine's Windows timezone registry.
# WS4000 uses Windows timezone APIs (cctz/absl) and fails without this mapping.
set -e

TZ="${TZ:-America/Los_Angeles}"
WINE="${WINE:-/opt/wine-ge/bin/wine64}"
WINEPREFIX="${WINEPREFIX:-/wineprefix}"
WINEARCH="${WINEARCH:-win64}"

iana_to_windows_tz() {
    case "$1" in
        Atlantic/Reykjavik|Etc/UTC|UTC|GMT) echo "Greenwich Standard Time" ;;
        America/New_York|US/Eastern) echo "Eastern Standard Time" ;;
        America/Chicago|US/Central) echo "Central Standard Time" ;;
        America/Denver|US/Mountain) echo "Mountain Standard Time" ;;
        America/Los_Angeles|US/Pacific) echo "Pacific Standard Time" ;;
        America/Phoenix) echo "US Mountain Standard Time" ;;
        America/Anchorage) echo "Alaskan Standard Time" ;;
        Pacific/Honolulu) echo "Hawaiian Standard Time" ;;
        *)
            local mapped
            mapped=$("$WINE" reg query "HKLM\\Software\\Wine\\Time Zones\\TZ Mapping" /v "$1" 2>/dev/null \
                | awk '/REG_SZ/ {print $NF; exit}') || true
            echo "${mapped:-Greenwich Standard Time}"
            ;;
    esac
}

WINE_TZ=$(iana_to_windows_tz "$TZ")

"$WINE" reg add "HKLM\\System\\CurrentControlSet\\Control\\TimeZoneInformation" \
    /v TimeZoneKeyName /t REG_SZ /d "$WINE_TZ" /f >/dev/null

# Avoid repeated tzres.dll load/unload under Wine (bug 46266).
"$WINE" reg delete "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Time Zones\\${WINE_TZ}" \
    /v MUI_Std /f >/dev/null 2>&1 || true
"$WINE" reg delete "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Time Zones\\${WINE_TZ}" \
    /v MUI_Dlt /f >/dev/null 2>&1 || true

"$(dirname "$WINE")/wineserver" -w 2>/dev/null || true
echo "Wine timezone configured: ${TZ} -> ${WINE_TZ}"
