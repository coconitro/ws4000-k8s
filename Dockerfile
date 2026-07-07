FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    WINEARCH=win64 \
    WINEPREFIX=/wineprefix \
    WINEESYNC=1 \
    WINEFSYNC=1 \
    PATH="/opt/wine-ge/bin:${PATH}" \
    TZ=America/Los_Angeles

RUN dpkg --add-architecture i386 && \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl xz-utils \
    xvfb x11vnc xdotool x11-xserver-utils \
    xserver-xorg-core xserver-xorg-video-amdgpu xserver-xorg-input-libinput pciutils \
    pulseaudio ffmpeg vlc cabextract tzdata feh \
    mesa-va-drivers mesa-vulkan-drivers vainfo \
    libfreetype6 libfreetype6:i386 \
    libvulkan1 libvkd3d1 \
    libc6-i386 lib32gcc-s1 lib32stdc++6 \
    libx11-6:i386 libxext6:i386 libxrender1:i386 libxrandr2:i386 \
    libxi6:i386 libgl1:i386 libvulkan1:i386 \
    libpulse0:i386 libasound2:i386 \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone \
    && rm -rf /var/lib/apt/lists/*

COPY container/entrypoint/wineboot-wrapper /wineboot-wrapper
COPY container/entrypoint/configure-wine-timezone.sh /usr/local/bin/configure-wine-timezone.sh
COPY container/entrypoint/prepare-ws4000.sh /usr/local/bin/prepare-ws4000.sh

# Install Wine-GE 8-26 (x86_64 build, supports win32 via WoW64)
RUN set -ex && \
    curl -fL https://github.com/GloriousEggroll/wine-ge-custom/releases/download/GE-Proton8-26/wine-lutris-GE-Proton8-26-x86_64.tar.xz \
      -o /tmp/wine.tar.xz && \
    mkdir -p /opt/wine-ge && \
    tar -xJ -C /opt/wine-ge -f /tmp/wine.tar.xz && \
    rm /tmp/wine.tar.xz && \
    mv /opt/wine-ge/lutris-GE-Proton8-26-x86_64/* /opt/wine-ge/ && \
    rmdir /opt/wine-ge/lutris-GE-Proton8-26-x86_64 && \
    \
    cp /wineboot-wrapper /opt/wine-ge/bin/wineboot && \
    chmod +x /opt/wine-ge/bin/wineboot /usr/local/bin/configure-wine-timezone.sh /usr/local/bin/prepare-ws4000.sh && \
    \
    test -x /opt/wine-ge/bin/wine && \
    test -x /opt/wine-ge/bin/wineboot && \
    /opt/wine-ge/bin/wine --version && \
    echo '=== Running wineboot --init (win64) ===' && \
    WINEPREFIX=/wineprefix WINEARCH=win64 /opt/wine-ge/bin/wineboot --init 2>&1 | cat ; rc=$? ; \
    echo "wineboot rc=$rc" ; \
    [ $rc -eq 0 ] || exit 1 ; \
    echo "SUCCESS: wineboot works"

# Install winetricks + DXVK at build time (win64)
RUN curl -fL https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks \
      -o /usr/local/bin/winetricks && \
    chmod +x /usr/local/bin/winetricks && \
    winetricks --version && \
    WINEPREFIX=/wineprefix WINEARCH=win64 winetricks -q dxvk && \
    touch /wineprefix/.dxvk-ready && \
    for dll in d3d8 d3d9 d3d11 dxgi; do \
      WINEPREFIX=/wineprefix WINEARCH=win64 /opt/wine-ge/bin/wine64 reg add \
        'HKCU\Software\Wine\DllOverrides' /v "$dll" /t REG_SZ /d native /f; \
    done && \
    WINEPREFIX=/wineprefix WINEARCH=win64 TZ=$TZ configure-wine-timezone.sh && \
    /opt/wine-ge/bin/wineserver -w && \
    chown -R 1000:1000 /wineprefix

RUN mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix
RUN useradd -m -u 1000 wineuser
USER wineuser
WORKDIR /app/WS4000v4

COPY --chown=wineuser:wineuser assets/ws4000 /app/WS4000v4
COPY --chown=wineuser:wineuser container/entrypoint/start.sh /start.sh
COPY container/entrypoint/entrypoint.sh /entrypoint.sh
COPY --chown=wineuser:wineuser container/entrypoint/stream.sh /usr/local/bin/stream.sh
COPY --chown=wineuser:wineuser container/entrypoint/verify-gpu-stream.sh /usr/local/bin/verify-gpu-stream.sh
COPY --chown=wineuser:wineuser container/entrypoint/verify-ws4000-render.sh /usr/local/bin/verify-ws4000-render.sh
COPY container/entrypoint/healthcheck.sh /usr/local/bin/healthcheck.sh
COPY container/entrypoint/check-ws4000-alive.sh /usr/local/bin/check-ws4000-alive.sh
COPY container/entrypoint/check-kick-stream.sh /usr/local/bin/check-kick-stream.sh
COPY container/entrypoint/recover-ws4000-sim.sh /usr/local/bin/recover-ws4000-sim.sh
# Cache-bust when WS4000 bundle contents change (profile.dat, Config.w4k, etc.)
ARG WS4000_BUST=1
USER root
RUN echo "WS4000 bundle bust=${WS4000_BUST}" && \
    chmod +x /entrypoint.sh /start.sh /usr/local/bin/stream.sh /usr/local/bin/verify-gpu-stream.sh /usr/local/bin/verify-ws4000-render.sh /usr/local/bin/healthcheck.sh /usr/local/bin/check-ws4000-alive.sh /usr/local/bin/check-kick-stream.sh /usr/local/bin/recover-ws4000-sim.sh && \
    ln -sfn /app/WS4000v4 /wineprefix/drive_c/WS4000v4_win && \
    cd /app/WS4000v4 && \
    if [ ! -f Config.w4k ] && [ -f config.w4k ]; then cp config.w4k Config.w4k; fi && \
    test -f WS4000v4.exe && \
    ls -la WS4000v4.exe Data.000 fmod64.dll 2>/dev/null || ls -la WS4000v4.exe

EXPOSE 5900
USER root
CMD ["/entrypoint.sh"]
