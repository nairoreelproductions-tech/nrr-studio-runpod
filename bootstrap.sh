#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# NRR Cloud Workstation — Perfected Vast.ai VM Bootstrap
# Optimized for: GUI Visibility, Blender 4.5.7 LTS, and Rclone Speed.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

# ── CONFIGURATION ────────────────────────────────────────────
# We move out of /root/ into /home/ so the GUI can "see" the files.
STUDIO_ROOT="/home/studio"
DESKTOP_DIR="/home/Desktop"
VPS_HOST="107.172.153.249"
VPS_USER="studio-sync"
LOG="$STUDIO_ROOT/bootstrap.log"

# ── INITIALIZATION ───────────────────────────────────────────
mkdir -p "$STUDIO_ROOT"
mkdir -p "$DESKTOP_DIR"
log() { echo "[nrr] $(date '+%H:%M:%S') $*" | tee -a "$LOG"; }

log "========================================"
log "NRR Studio bootstrap starting (GUI-READY)"
log "========================================"

# ── SECTION 1: GPU & Rclone Install ──────────────────────────
log "Checking GPU..."
if command -v nvidia-smi &>/dev/null; then
    log "GPU detected: $(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)"
fi

if ! command -v rclone &>/dev/null; then
    log "Installing rclone for high-speed server-to-server transfer..."
    curl -fsSL https://rclone.org/install.sh | sudo bash
fi

# ── SECTION 2: SSH & SFTP Configuration ──────────────────────
if [ -z "${VPS_SSH_KEY_B64:-}" ]; then
    log "ERROR: VPS_SSH_KEY_B64 is missing."
    exit 1
fi

log "Decoding SSH key..."
mkdir -p "/root/.ssh"
echo "$VPS_SSH_KEY_B64" | base64 -d > "/root/.ssh/studio_sync_key"
chmod 600 "/root/.ssh/studio_sync_key"
ssh-keyscan -p 22 "$VPS_HOST" >> "/root/.ssh/known_hosts" 2>/dev/null || true

log "Writing rclone config..."
mkdir -p "/root/.config/rclone"
cat > "/root/.config/rclone/rclone.conf" << EOF
[vps]
type = sftp
host = $VPS_HOST
port = 22
user = $VPS_USER
key_file = /root/.ssh/studio_sync_key
EOF

# ── SECTION 3: Directory Setup & Data Pull ───────────────────
log "Building workspace in /home/studio..."
mkdir -p "$STUDIO_ROOT/BLENDER_APPS" \
         "$STUDIO_ROOT/CONFIG_MASTER/scripts/addons" \
         "$STUDIO_ROOT/LIBRARY_GLOBAL" \
         "$STUDIO_ROOT/PROJECTS"

log "Pulling Projects and Library from VPS via rclone..."
# Using rclone ensures max speed over standard browser downloads
rclone copy vps:/PROJECTS "$STUDIO_ROOT/PROJECTS" --transfers=8 --stats=10s
rclone copy vps:/LIBRARY_GLOBAL "$STUDIO_ROOT/LIBRARY_GLOBAL" --transfers=8
rclone copy vps:/CONFIG_MASTER "$STUDIO_ROOT/CONFIG_MASTER" --transfers=4
rclone copy vps:/BLENDER_APPS "$STUDIO_ROOT/BLENDER_APPS" --transfers=4

# ── SECTION 4: Blender 4.5.7 Setup ───────────────────────────
log "Configuring Blender 4.5.7 LTS..."

BLENDER_TAR=$(ls "$STUDIO_ROOT/BLENDER_APPS/blender-4.5.7"*.tar.xz 2>/dev/null | head -1 || true)

if [ -n "$BLENDER_TAR" ]; then
    if [ ! -d "$STUDIO_ROOT/BLENDER_APPS/blender-app" ]; then
        log "Extracting 4.5.7 LTS..."
        tar -xf "$BLENDER_TAR" -C "$STUDIO_ROOT/BLENDER_APPS/"
        EXTRACTED_DIR=$(ls -d "$STUDIO_ROOT/BLENDER_APPS/blender-4.5.7"*linux* 2>/dev/null | head -1)
        mv "$EXTRACTED_DIR" "$STUDIO_ROOT/BLENDER_APPS/blender-app"
    fi

    # Create the Desktop Shortcut in the VISIBLE directory
    log "Creating GUI Desktop Shortcut..."
    cat > "$DESKTOP_DIR/Blender-Studio.desktop" << EOF
[Desktop Entry]
Name=Blender 4.5.7 (Studio)
Exec=$STUDIO_ROOT/BLENDER_APPS/blender-app/blender %f
Icon=$STUDIO_ROOT/BLENDER_APPS/blender-app/blender.svg
Type=Application
Terminal=false
Categories=Graphics;3DGraphics;
EOF

    chmod +x "$DESKTOP_DIR/Blender-Studio.desktop"
    # Also add to the system menu for easy searching
    cp "$DESKTOP_DIR/Blender-Studio.desktop" /usr/share/applications/
else
    log "WARN: Blender 4.5.7 tarball not found on VPS. Falling back to system version."
fi

# ── SECTION 5: Addon Symlinking ──────────────────────────────
# Link addons to the specific 4.5 config folder
ADDON_TARGET="/root/.config/blender/4.5/scripts/addons"
ADDON_SOURCE="$STUDIO_ROOT/CONFIG_MASTER/scripts/addons"

if [ -d "$ADDON_SOURCE" ]; then
    mkdir -p "$ADDON_TARGET"
    ln -sfn "$ADDON_SOURCE"/* "$ADDON_TARGET/"
    log "Addons linked to Blender 4.5 config."
fi

# ── SECTION 6: Background Sync (Updated Paths) ───────────────
CRON_CMD="rclone sync $STUDIO_ROOT/PROJECTS vps:/PROJECTS --transfers=4 2>>$LOG"
(crontab -l 2>/dev/null | grep -v "vps:/PROJECTS" ; echo "*/5 * * * * $CRON_CMD") | crontab -
log "Project sync scheduled every 5 minutes."

# ── SECTION 7: The "Visibility" Hammer ───────────────────────
log "Applying GUI permissions..."
# This removes "Locked" icons and allows Dolphin to browse the folders
chmod -R 777 "$STUDIO_ROOT"
chmod -R 777 "$DESKTOP_DIR"

log "========================================"
log "BOOTSTRAP COMPLETE"
log "========================================"
