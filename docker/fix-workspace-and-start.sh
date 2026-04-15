#!/usr/bin/env bash
set -e

LOG=/workspace/startup.log

log() { echo "[studio] $*" | tee -a "$LOG"; }

log "================================================"
log "NRR Cloud Workstation startup — $(date)"
log "================================================"

# ── 1. Fix /workspace permissions ────────────────────────────
log "Creating /workspace directories..."
mkdir -p \
    /workspace/BLENDER_APPS \
    /workspace/CONFIG_MASTER/scripts/addons \
    /workspace/LIBRARY_GLOBAL \
    /workspace/PROJECTS

chown -R kasm-user:kasm-user /workspace
chmod -R 775 /workspace

# ── 2. Write SSH key — owned by kasm-user ────────────────────
if [ -z "${VPS_SSH_KEY_B64}" ]; then
    log "WARNING: VPS_SSH_KEY_B64 is not set. Skipping VPS sync."
    SKIP_SYNC=1
else
    log "Decoding SSH key..."
    echo "${VPS_SSH_KEY_B64}" | base64 -d > /run/studio_sync_key
    chown kasm-user:kasm-user /run/studio_sync_key
    chmod 600 /run/studio_sync_key

    # known_hosts for kasm-user (not root)
    mkdir -p /home/kasm-user/.ssh
    ssh-keyscan -p 22 107.172.153.249 >> /home/kasm-user/.ssh/known_hosts 2>/dev/null || true
    chown -R kasm-user:kasm-user /home/kasm-user/.ssh
    chmod 700 /home/kasm-user/.ssh
    chmod 600 /home/kasm-user/.ssh/known_hosts

    SKIP_SYNC=0
fi

# ── 3. Write rclone config — in kasm-user's home ────────────
if [ "${SKIP_SYNC}" = "0" ]; then
    log "Writing rclone config for kasm-user..."
    mkdir -p /home/kasm-user/.config/rclone

    cat > /home/kasm-user/.config/rclone/rclone.conf << 'EOF'
[vps]
type = sftp
host = 107.172.153.249
port = 22
user = studio-sync
key_file = /run/studio_sync_key
EOF

    chown -R kasm-user:kasm-user /home/kasm-user/.config/rclone

    # ── 4. Quick connectivity test ───────────────────────────
    log "Testing SFTP connection to VPS..."
    if su -s /bin/bash -c "rclone lsd vps:/" kasm-user >> "$LOG" 2>&1; then
        log "VPS connection OK."
    else
        log "ERROR: Cannot connect to VPS. Check SSH key and VPS config."
        log "Skipping file sync — pod will start with empty workspace."
        SKIP_SYNC=1
    fi
fi

# ── 5. Pull files from VPS (as kasm-user) ───────────────────
if [ "${SKIP_SYNC}" = "0" ]; then
    log "Pulling BLENDER_APPS from VPS..."
    su -s /bin/bash -c "rclone copy vps:/BLENDER_APPS /workspace/BLENDER_APPS --transfers=4 --stats=10s" kasm-user >> "$LOG" 2>&1 \
        || log "WARN: BLENDER_APPS sync had errors"

    log "Pulling CONFIG_MASTER from VPS..."
    su -s /bin/bash -c "rclone copy vps:/CONFIG_MASTER /workspace/CONFIG_MASTER --transfers=4 --stats=10s" kasm-user >> "$LOG" 2>&1 \
        || log "WARN: CONFIG_MASTER sync had errors"

    log "Pulling LIBRARY_GLOBAL from VPS (this may take a while)..."
    su -s /bin/bash -c "rclone copy vps:/LIBRARY_GLOBAL /workspace/LIBRARY_GLOBAL --transfers=8 --stats=10s" kasm-user >> "$LOG" 2>&1 \
        || log "WARN: LIBRARY_GLOBAL sync had errors"

    log "Pulling PROJECTS from VPS..."
    su -s /bin/bash -c "rclone copy vps:/PROJECTS /workspace/PROJECTS --transfers=4 --stats=10s" kasm-user >> "$LOG" 2>&1 \
        || log "WARN: PROJECTS sync had errors"
fi

# ── 6. Extract Blender if tarball present ────────────────────
log "Checking for Blender tarball..."
BLENDER_TAR=$(ls /workspace/BLENDER_APPS/blender-*.tar.xz 2>/dev/null | head -1)

if [ -n "$BLENDER_TAR" ] && [ ! -d /workspace/BLENDER_APPS/blender-app ]; then
    log "Extracting Blender from ${BLENDER_TAR}..."
    tar -xf "$BLENDER_TAR" -C /workspace/BLENDER_APPS/
    BLENDER_DIR=$(ls -d /workspace/BLENDER_APPS/blender-*-linux-x64 2>/dev/null | head -1)
    if [ -n "$BLENDER_DIR" ]; then
        mv "$BLENDER_DIR" /workspace/BLENDER_APPS/blender-app
        log "Blender extracted to /workspace/BLENDER_APPS/blender-app"
    fi
elif [ -d /workspace/BLENDER_APPS/blender-app ]; then
    log "Blender already extracted."
else
    log "No Blender tarball found in BLENDER_APPS/. Upload one to the VPS first."
fi

# Ensure kasm-user owns everything after extraction
chown -R kasm-user:kasm-user /workspace

# ── 7. Create desktop shortcut ──────────────────────────────
log "Setting up desktop shortcut..."
mkdir -p /home/kasm-user/Desktop

if [ -f /workspace/BLENDER_APPS/blender-app/blender ]; then
    ICON_PATH=/workspace/BLENDER_APPS/blender-app/blender.svg
    [ -f "$ICON_PATH" ] || ICON_PATH=blender

    cat > /home/kasm-user/Desktop/Blender.desktop << EOF2
[Desktop Entry]
Name=Blender
Exec=/workspace/BLENDER_APPS/blender-app/blender
Icon=${ICON_PATH}
Type=Application
Terminal=false
Categories=Graphics;3DGraphics;
EOF2
    chmod +x /home/kasm-user/Desktop/Blender.desktop
    chown kasm-user:kasm-user /home/kasm-user/Desktop/Blender.desktop
    log "Desktop shortcut created."
else
    log "Blender binary not found — shortcut not created."
fi

# ── 8. Start background project sync (as kasm-user) ─────────
if [ "${SKIP_SYNC}" = "0" ]; then
    log "Starting background PROJECTS sync (every 5 minutes)..."
    su -s /bin/bash -c '
        while true; do
            sleep 300
            rclone sync /workspace/PROJECTS vps:/PROJECTS --transfers=4 2>/dev/null || true
        done
    ' kasm-user &
    log "Background sync PID: $!"
fi

log "================================================"
log "Startup complete. Handing off to base image."
log "================================================"

# ── 9. Hand off to the base image entrypoint ─────────────────
if [ $# -gt 0 ]; then
    exec "$@"
else
    exec /dockerstartup/kasm_default_profile.sh /dockerstartup/vnc_startup.sh
fi
