#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# NRR Cloud Workstation — Writable & Visible Bootstrap
# Optimized for: Blender 4.5.7 LTS, Rclone Speed, and Full Write Access.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

# ── CONFIGURATION ────────────────────────────────────────────
# We use /home/ubuntu/ because it is the standard writable path for GUI users.
# If your VM uses a different user, change 'ubuntu' to your username.
GUI_USER="ubuntu"
STUDIO_ROOT="/home/$GUI_USER/studio"
DESKTOP_DIR="/home/$GUI_USER/Desktop"
VPS_HOST="107.172.153.249"
VPS_USER="studio-sync"
LOG="$STUDIO_ROOT/bootstrap.log"

# ── INITIALIZATION ───────────────────────────────────────────
mkdir -p "$STUDIO_ROOT"
mkdir -p "$DESKTOP_DIR"
log() { echo "[nrr] $(date '+%H:%M:%S') $*" | tee -a "$LOG"; }

log "========================================"
log "NRR Studio bootstrap starting (WRITABLE FIX)"
log "========================================"

# ── SECTION 1-2: (Rclone & SSH Setup) ────────────────────────
# [Logic remains the same as previous version]
if ! command -v rclone &>/dev/null; then
    curl -fsSL https://rclone.org/install.sh | sudo bash
fi

# Decoding SSH and Writing Rclone Config (Root keeps the keys for the cron job)
mkdir -p "/root/.ssh"
echo "${VPS_SSH_KEY_B64:-}" | base64 -d > "/root/.ssh/studio_sync_key" || { log "ERROR: Key missing"; exit 1; }
chmod 600 "/root/.ssh/studio_sync_key"

cat > "/root/.config/rclone/rclone.conf" << EOF
[vps]
type = sftp
host = $VPS_HOST
port = 22
user = $VPS_USER
key_file = /root/.ssh/studio_sync_key
EOF

# ── SECTION 3: Writable Workspace Construction ───────────────
log "Building workspace in $STUDIO_ROOT..."
mkdir -p "$STUDIO_ROOT/BLENDER_APPS" \
         "$STUDIO_ROOT/PROJECTS" \
         "$STUDIO_ROOT/LIBRARY_GLOBAL" \
         "$STUDIO_ROOT/CONFIG_MASTER"

log "Pulling Projects from VPS..."
rclone copy vps:/PROJECTS "$STUDIO_ROOT/PROJECTS" --transfers=8
rclone copy vps:/BLENDER_APPS "$STUDIO_ROOT/BLENDER_APPS" --transfers=4

# ── SECTION 4: Blender 4.5.7 & Shortcut ──────────────────────
log "Installing Blender 4.5.7 LTS..."
BLENDER_TAR=$(ls "$STUDIO_ROOT/BLENDER_APPS/blender-4.5.7"*.tar.xz 2>/dev/null | head -1 || true)

if [ -n "$BLENDER_TAR" ]; then
    tar -xf "$BLENDER_TAR" -C "$STUDIO_ROOT/BLENDER_APPS/"
    EXTRACTED_DIR=$(ls -d "$STUDIO_ROOT/BLENDER_APPS/blender-4.5.7"*linux* 2>/dev/null | head -1)
    mv "$EXTRACTED_DIR" "$STUDIO_ROOT/BLENDER_APPS/blender-app"

    # Create Shortcut in the GUI User's Desktop
    cat > "$DESKTOP_DIR/Blender-Studio.desktop" << EOF
[Desktop Entry]
Name=Blender 4.5.7 (Studio)
Exec=$STUDIO_ROOT/BLENDER_APPS/blender-app/blender %f
Icon=$STUDIO_ROOT/BLENDER_APPS/blender-app/blender.svg
Type=Application
Terminal=false
EOF
    chmod +x "$DESKTOP_DIR/Blender-Studio.desktop"
fi

# ── SECTION 5: Ownership Transfer (THE FIX) ──────────────────
log "Transferring ownership to $GUI_USER..."
# This is the critical step: making the GUI user the 'owner' of the files.
chown -R $GUI_USER:$GUI_USER "$STUDIO_ROOT"
chown -R $GUI_USER:$GUI_USER "$DESKTOP_DIR"
# Also set wide permissions just to be safe for VFX workflows
chmod -R 775 "$STUDIO_ROOT"

# ── SECTION 6: Background Sync ───────────────────────────────
CRON_CMD="rclone sync $STUDIO_ROOT/PROJECTS vps:/PROJECTS --transfers=4 2>>$LOG"
(crontab -l 2>/dev/null | grep -v "vps:/PROJECTS" ; echo "*/5 * * * * $CRON_CMD") | crontab -

log "BOOTSTRAP COMPLETE - Workspace is now writable!"
