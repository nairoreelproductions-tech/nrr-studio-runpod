#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# NRR Cloud Workstation — PRODUCTION BOOTSTRAP (ZIP RETAINED)
# Fixed: Absolute VPS Paths, 'user' Ownership, and ZIP Integrity.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

# ── CONFIGURATION ────────────────────────────────────────────
GUI_USER="user"
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
log "NRR Studio bootstrap: FINAL REVISION"
log "========================================"

# ── SECTION 1: Tools & Connectivity ────────────────────────
if ! command -v rclone &>/dev/null; then
    log "Installing rclone..."
    curl -fsSL https://rclone.org/install.sh | sudo bash
fi

mkdir -p "/root/.ssh"
echo "${VPS_SSH_KEY_B64:-}" | base64 -d > "/root/.ssh/studio_sync_key" || { log "ERROR: Key missing"; exit 1; }
chmod 600 "/root/.ssh/studio_sync_key"

mkdir -p "/root/.config/rclone"
cat > "/root/.config/rclone/rclone.conf" << EOF
[vps]
type = sftp
host = $VPS_HOST
port = 22
user = $VPS_USER
key_file = /root/.ssh/studio_sync_key
EOF

# ── SECTION 2: Data Pull (Absolute VPS Paths) ───────────────
log "Building workspace in $STUDIO_ROOT..."
mkdir -p "$STUDIO_ROOT/BLENDER_APPS" \
         "$STUDIO_ROOT/PROJECTS" \
         "$STUDIO_ROOT/LIBRARY_GLOBAL" \
         "$STUDIO_ROOT/CONFIG_MASTER"

# Pulling from confirmed /srv/studio location on VPS
log "Syncing data from VPS /srv/studio/..."
rclone copy vps:/srv/studio/PROJECTS "$STUDIO_ROOT/PROJECTS" --transfers=8 --stats=10s
rclone copy vps:/srv/studio/LIBRARY_GLOBAL "$STUDIO_ROOT/LIBRARY_GLOBAL" --transfers=16
rclone copy vps:/srv/studio/CONFIG_MASTER "$STUDIO_ROOT/CONFIG_MASTER" --transfers=4
rclone copy vps:/srv/studio/BLENDER_APPS "$STUDIO_ROOT/BLENDER_APPS" --transfers=4

# ── SECTION 3: Blender 4.5.7 & Shortcut ──────────────────────
log "Configuring Blender 4.5.7..."
BLENDER_TAR=$(ls "$STUDIO_ROOT/BLENDER_APPS/blender-4.5.7"*.tar.xz 2>/dev/null | head -1 || true)

if [ -n "$BLENDER_TAR" ]; then
    if [ ! -d "$STUDIO_ROOT/BLENDER_APPS/blender-app" ]; then
        log "Extracting Blender Binary..."
        tar -xf "$BLENDER_TAR" -C "$STUDIO_ROOT/BLENDER_APPS/"
        EXTRACTED_DIR=$(ls -d "$STUDIO_ROOT/BLENDER_APPS/blender-4.5.7"*linux* 2>/dev/null | head -1)
        mv "$EXTRACTED_DIR" "$STUDIO_ROOT/BLENDER_APPS/blender-app"
    fi

    # Create shortcut in the 'user' Desktop
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

# ── SECTION 4: THE OWNERSHIP FIX (STRICT) ────────────────────
log "Finalizing permissions for 'user:users'..."
# Transfer ownership of the entire studio and the desktop link
chown -R "$GUI_USER:users" "$STUDIO_ROOT"
chown -R "$GUI_USER:users" "$DESKTOP_DIR"

# Ensure directories are writable for the 'user' account
find "$STUDIO_ROOT" -type d -exec chmod 775 {} +
find "$STUDIO_ROOT" -type f -exec chmod 664 {} +
# Make sure the blender binary remains executable
[ -f "$STUDIO_ROOT/BLENDER_APPS/blender-app/blender" ] && chmod +x "$STUDIO_ROOT/BLENDER_APPS/blender-app/blender"

log "Ownership transferred. ZIP files preserved in CONFIG_MASTER."

# ── SECTION 5: Background Sync ───────────────────────────────
CRON_CMD="rclone sync $STUDIO_ROOT/PROJECTS vps:/srv/studio/PROJECTS --transfers=4 2>>$LOG"
(crontab -l 2>/dev/null | grep -v "/srv/studio/PROJECTS" ; echo "*/5 * * * * $CRON_CMD") | crontab -

log "========================================"
log "BOOTSTRAP COMPLETE - ALL FILES WRITABLE"
log "========================================"
