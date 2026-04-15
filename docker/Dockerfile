FROM madiator2011/kasm-runpod-desktop:mldesk

USER root

# Install runtime deps + build tools for Vulkan 1.3 loader
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl openssh-client \
    build-essential git pkg-config \
    libxcb1-dev libx11-xcb-dev libxrandr-dev libwayland-dev \
    && rm -rf /var/lib/apt/lists/*

# Install rclone
RUN curl https://rclone.org/install.sh | bash

# Upgrade cmake (Ubuntu 20.04 ships 3.16, Vulkan-Loader needs 3.17+)
RUN pip3 install cmake

# Build Vulkan 1.3 Headers + Loader from source (Blender 4.5+ needs Vulkan 1.3)
RUN cd /tmp \
    && git clone --branch v1.3.283 --depth 1 https://github.com/KhronosGroup/Vulkan-Headers.git \
    && cmake -S Vulkan-Headers -B Vulkan-Headers/build -DCMAKE_INSTALL_PREFIX=/usr \
    && cmake --install Vulkan-Headers/build \
    && git clone --branch v1.3.283 --depth 1 https://github.com/KhronosGroup/Vulkan-Loader.git \
    && cmake -S Vulkan-Loader -B Vulkan-Loader/build -DCMAKE_BUILD_TYPE=Release \
    && cmake --build Vulkan-Loader/build -j$(nproc) \
    && cmake --install Vulkan-Loader/build \
    && ldconfig \
    && rm -rf /tmp/Vulkan-Headers /tmp/Vulkan-Loader

# ══════════════════════════════════════════════════════════════
# DIAGNOSTIC BUILD — Phase 1: answer unknowns before full build
# ══════════════════════════════════════════════════════════════

# ── DIAG: confirm base OS version ──
RUN echo "=== OS VERSION ===" && cat /etc/os-release

# ── DIAG: install Tailscale via static binary (bypasses apt entirely) ──
RUN set -e \
    && TSVERSION=$(curl -fsSL 'https://pkgs.tailscale.com/stable/?mode=json' \
         | grep -o '"Version":"[^"]*"' | head -1 | cut -d'"' -f4) \
    && echo "Installing Tailscale static binary v${TSVERSION}..." \
    && curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_${TSVERSION}_amd64.tgz" \
         -o /tmp/tailscale.tgz \
    && tar xzf /tmp/tailscale.tgz -C /tmp \
    && install -m 755 "/tmp/tailscale_${TSVERSION}_amd64/tailscale" /usr/local/bin/ \
    && install -m 755 "/tmp/tailscale_${TSVERSION}_amd64/tailscaled" /usr/local/bin/ \
    && rm -rf /tmp/tailscale* \
    && mkdir -p /var/run/tailscale /var/lib/tailscale \
    && echo "Tailscale version:" && tailscale version

# ── DIAG: install Sunshine deps + attempt .deb install ──
# We try multiple URL patterns since LizardByte naming varies by release.
# This step is fault-tolerant — if Sunshine fails, the build still completes.
RUN apt-get update && apt-get install -y --no-install-recommends \
      libevdev-dev libcap-dev libdrm-dev \
    && rm -rf /var/lib/apt/lists/*

# First, list what assets are actually available in the latest Sunshine release
RUN echo "=== SUNSHINE: Available release assets ===" \
    && (curl -fsSL https://api.github.com/repos/LizardByte/Sunshine/releases/latest \
        | grep -o '"name": "[^"]*\.deb"' || echo "Could not fetch release assets") \
    && echo "=== END ASSETS ==="

# Try multiple URL patterns — LizardByte naming changes between releases
RUN . /etc/os-release \
    && echo "=== SUNSHINE INSTALL ATTEMPT ===" \
    && echo "OS: ${NAME} ${VERSION_ID} (${VERSION_CODENAME})" \
    && FOUND=0 \
    && for pattern in \
         "sunshine-${VERSION_CODENAME}-amd64.deb" \
         "sunshine-ubuntu-${VERSION_ID}-amd64.deb" \
         "sunshine-${VERSION_CODENAME}_amd64.deb" \
         "sunshine_${VERSION_CODENAME}_amd64.deb" \
         "sunshine-jammy-amd64.deb" \
         "sunshine-focal-amd64.deb" \
         "sunshine-ubuntu-22.04-amd64.deb" \
         "sunshine-ubuntu-20.04-amd64.deb"; do \
         echo "Trying: ${pattern} ..." \
         && if curl -fSL -o /tmp/sunshine.deb \
              "https://github.com/LizardByte/Sunshine/releases/latest/download/${pattern}" \
              2>/dev/null && [ -s /tmp/sunshine.deb ]; then \
              echo ">>> DOWNLOADED: ${pattern} <<<"; \
              FOUND=1; \
              break; \
            else \
              rm -f /tmp/sunshine.deb; \
            fi; \
       done \
    && if [ "$FOUND" = "1" ]; then \
         echo "=== .deb DEPENDENCIES ===" \
         && (dpkg -I /tmp/sunshine.deb | grep -i "depends" || true) \
         && echo "=== INSTALLING ===" \
         && apt-get update \
         && (apt-get install -y -f /tmp/sunshine.deb \
             && echo ">>> SUNSHINE INSTALL: SUCCESS <<<" \
             || echo ">>> SUNSHINE INSTALL: FAILED (dependency issue?) <<<") \
         && rm -rf /var/lib/apt/lists/*; \
       else \
         echo ">>> SUNSHINE DOWNLOAD: FAILED — none of the URL patterns matched <<<" \
         && echo ">>> Check the 'Available release assets' output above for correct filename <<<"; \
       fi \
    && rm -f /tmp/sunshine.deb || true

# ── DIAG: check what got installed ──
RUN echo "=== INSTALLED PACKAGES (sunshine/audio) ===" \
    && (dpkg -l | grep -iE "pulse|pipewire|sunshine" || echo "No sunshine/audio packages found") \
    && echo "=== SUNSHINE BINARY ===" \
    && (which sunshine && sunshine --version || echo "Sunshine binary not found") \
    && echo "=== SUNSHINE HELP (first 20 lines) ===" \
    && (sunshine --help 2>&1 | head -20 || echo "Sunshine --help failed")

# Add kasm-user to input group (needed for Sunshine virtual input)
RUN usermod -aG input kasm-user || true

# Copy runtime probe script
COPY probe-streaming-readiness.sh /usr/local/bin/probe-streaming-readiness.sh
RUN chmod +x /usr/local/bin/probe-streaming-readiness.sh

# ══════════════════════════════════════════════════════════════
# END DIAGNOSTIC BLOCK
# ══════════════════════════════════════════════════════════════

# Blender launcher wrapper — preloads Vulkan 1.3 + uses VirtualGL for KasmVNC
RUN printf '#!/usr/bin/env bash\n\
export LD_PRELOAD=/usr/local/lib/libvulkan.so.1.3.283\n\
if [ -f /opt/VirtualGL/bin/vglrun ] && [ ! -z "${KASM_EGL_CARD}" ] && [ ! -z "${KASM_RENDERD}" ] && [ -O "${KASM_RENDERD}" ] && [ -O "${KASM_EGL_CARD}" ]; then\n\
    vglrun -d "${KASM_EGL_CARD}" /workspace/BLENDER_APPS/blender-app/blender "$@"\n\
else\n\
    /workspace/BLENDER_APPS/blender-app/blender "$@"\n\
fi\n' > /usr/bin/blender && chmod +x /usr/bin/blender

# Copy and register the startup wrapper
COPY fix-workspace-and-start.sh /usr/local/bin/fix-workspace-and-start.sh
RUN chmod +x /usr/local/bin/fix-workspace-and-start.sh

ENTRYPOINT ["/usr/local/bin/fix-workspace-and-start.sh"]
