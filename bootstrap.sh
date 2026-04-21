#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# NRR Cloud Workstation — Bootstrap v4 (User-Owned, Correct Paths)
# Run inside VNC terminal as 'user':
#   export VPS_SSH_KEY_B64="your_key_here"
#   curl -fsSL https://raw.githubusercontent.com/.../bootstrap.sh | bash
# ─────────────────────────────────────────────────────────────
set -eo pipefail

# ── CONFIGURATION ─────────────────────────────────────────────
VPS_HOST="107.172.153.249"
VPS_USER="studio-sync"
STUDIO_ROOT="$HOME/studio"
DESKTOP_DIR="$HOME/Desktop"
KEY_FILE="$HOME/.ssh/studio_sync_key"
LOG="$STUDIO_ROOT/bootstrap.log"

mkdir -p "$STUDIO_ROOT" "$DESKTOP_DIR"
log() { echo "[nrr] $(date '+%H:%M:%S') $*" | tee -a "$LOG"; }

log "========================================"
log "NRR Bootstrap | user: $(whoami) | home: $HOME"
log "========================================"

# ── SECTION 1: SSH Key (stored in user home, user-owned) ──────
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [ -z "${VPS_SSH_KEY_B64:-}" ]; then
    log "ERROR: VPS_SSH_KEY_B64 is not set. Export it before running."
    exit 1
fi

echo "$VPS_SSH_KEY_B64" | base64 -d > "$KEY_FILE"
chmod 600 "$KEY_FILE"
log "SSH key written to $KEY_FILE"

ssh-keyscan -p 22 "$VPS_HOST" >> "$HOME/.ssh/known_hosts" 2>/dev/null || true

# ── SECTION 2: Install rclone (safe two-step, not piped sudo) ─
if ! command -v rclone &>/dev/null; then
    log "Installing rclone..."
    curl -fsSL https://rclone.org/install.sh -o /tmp/rclone_install.sh
    sudo bash /tmp/rclone_install.sh
    rm -f /tmp/rclone_install.sh
fi
log "rclone: $(command -v rclone)"

# ── SECTION 3: Rclone Config (user-owned) ─────────────────────
mkdir -p "$HOME/.config/rclone"
cat > "$HOME/.config/rclone/rclone.conf" << EOF
[vps]
type = sftp
host = $VPS_HOST
port = 22
user = $VPS_USER
key_file = $KEY_FILE
EOF
log "rclone config written."

# ── SECTION 4: Data Pull ──────────────────────────────────────
# CRITICAL: studio-sync SFTP root IS /srv/studio on the VPS.
# Paths here are relative to that root. Do NOT prefix with /srv/studio.
log "Pulling data from VPS..."
mkdir -p "$STUDIO_ROOT/PROJECTS" \
         "$STUDIO_ROOT/BLENDER_APPS" \
         "$STUDIO_ROOT/LIBRARY_GLOBAL" \
         "$STUDIO_ROOT/CONFIG_MASTER"

rclone copy vps:/PROJECTS       "$STUDIO_ROOT/PROJECTS"       --transfers=8  --stats=10s
rclone copy vps:/BLENDER_APPS   "$STUDIO_ROOT/BLENDER_APPS"   --transfers=4  --stats=10s
rclone copy vps:/LIBRARY_GLOBAL "$STUDIO_ROOT/LIBRARY_GLOBAL" --transfers=16 --stats=10s
rclone copy vps:/CONFIG_MASTER  "$STUDIO_ROOT/CONFIG_MASTER"  --transfers=4  --stats=10s

# ── SECTION 5: Blender 4.5.7 Setup ───────────────────────────
log "Setting up Blender..."
BLENDER_TAR=$(ls "$STUDIO_ROOT/BLENDER_APPS/blender-4.5.7"*.tar.xz 2>/dev/null | head -1 || true)

if [ -n "$BLENDER_TAR" ]; then
    if [ ! -d "$STUDIO_ROOT/BLENDER_APPS/blender-app" ]; then
        log "Extracting $BLENDER_TAR..."
        tar -xf "$BLENDER_TAR" -C "$STUDIO_ROOT/BLENDER_APPS/"
        EXTRACTED_DIR=$(ls -d "$STUDIO_ROOT/BLENDER_APPS/blender-4.5.7"*linux* 2>/dev/null | head -1)
        mv "$EXTRACTED_DIR" "$STUDIO_ROOT/BLENDER_APPS/blender-app"
    fi

    cat > "$DESKTOP_DIR/Blender-Studio.desktop" << EOF
[Desktop Entry]
Name=Blender 4.5.7 (Studio)
Exec=$STUDIO_ROOT/BLENDER_APPS/blender-app/blender %f
Icon=$STUDIO_ROOT/BLENDER_APPS/blender-app/blender.svg
Type=Application
Terminal=false
EOF
    chmod +x "$DESKTOP_DIR/Blender-Studio.desktop"
    log "Blender shortcut created."
else
    log "WARNING: No blender-4.5.7 tar.xz found in BLENDER_APPS. Skipping."
fi

# ── SECTION 6: Cron Sync Back to VPS ─────────────────────────
# Sync uses same relative path. Runs as user, uses user's rclone config.
CRON_CMD="rclone sync $STUDIO_ROOT/PROJECTS vps:/PROJECTS --transfers=4 2>>$LOG"
(crontab -l 2>/dev/null | grep -v "vps:/PROJECTS"; echo "*/5 * * * * $CRON_CMD") | crontab -
log "Cron sync registered."

log "========================================"
log "DONE. All files in $STUDIO_ROOT are owned by $(whoami)."
log "Blender can save. Rclone will sync back every 5 min."
log "========================================"
