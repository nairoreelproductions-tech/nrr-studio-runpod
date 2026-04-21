#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# NRR Cloud Workstation — Bootstrap v5 (User-Owned, Correct Paths)
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

# ── SECTION 7: Shell Aliases ──────────────────────────────────
log "Registering studio aliases..."

ALIAS_BLOCK='
# ── NRR Studio Aliases ─────────────────────────────────────────
STUDIO_ROOT="$HOME/studio"
STUDIO_LOG="$HOME/studio/bootstrap.log"

# Pull everything fresh from the VPS (PROJECTS + LIBRARY + CONFIG)
alias studio-pull='rclone copy vps:/PROJECTS       $HOME/studio/PROJECTS       --transfers=8  --progress &&
                   rclone copy vps:/LIBRARY_GLOBAL  $HOME/studio/LIBRARY_GLOBAL --transfers=16 --progress &&
                   rclone copy vps:/CONFIG_MASTER   $HOME/studio/CONFIG_MASTER  --transfers=4  --progress &&
                   echo "[nrr] Pull complete."'

# Pull PROJECTS only — fastest, use this after a teammate uploads a file
alias studio-pull-projects='rclone copy vps:/PROJECTS $HOME/studio/PROJECTS --transfers=8 --progress && echo "[nrr] Projects pulled."'

# Push PROJECTS up to VPS immediately (does not wait for the 5-min cron)
alias studio-push='rclone sync $HOME/studio/PROJECTS vps:/PROJECTS --transfers=8 --progress && echo "[nrr] Push complete."'

# Push a single folder by name: studio-push-folder my_scene
alias studio-push-folder='f(){ rclone sync "$HOME/studio/PROJECTS/$1" "vps:/PROJECTS/$1" --transfers=4 --progress && echo "[nrr] Pushed: $1"; }; f'

# Show files that differ between local PROJECTS and VPS (dry-run, no changes made)
alias studio-status='rclone check $HOME/studio/PROJECTS vps:/PROJECTS --one-way 2>&1 | grep -E "ERROR|not found|differ|Match" || echo "[nrr] All in sync."'

# Full bidirectional sync: pull everything down, then push projects up
alias studio-sync='studio-pull && studio-push && echo "[nrr] Full sync done."'

# Tail the live sync log
alias studio-log='tail -f $HOME/studio/bootstrap.log'

# List everything currently on the VPS PROJECTS folder
alias studio-ls='rclone ls vps:/PROJECTS'

# Launch Blender
alias studio-open='$HOME/studio/BLENDER_APPS/blender-app/blender &'
# ── End NRR Studio Aliases ────────────────────────────────────
'

# Write aliases to .bashrc if not already present
if ! grep -q "NRR Studio Aliases" "$HOME/.bashrc" 2>/dev/null; then
    echo "$ALIAS_BLOCK" >> "$HOME/.bashrc"
    log "Aliases written to ~/.bashrc"
else
    log "Aliases already present in ~/.bashrc — skipping."
fi

# Make aliases available in the current session
# shellcheck disable=SC1090
source "$HOME/.bashrc" 2>/dev/null || true

log "========================================"
log "DONE. All files in $STUDIO_ROOT are owned by $(whoami)."
log "Blender can save. Rclone will sync back every 5 min."
log ""
log "Available commands:"
log "  studio-pull           Pull all folders from VPS"
log "  studio-pull-projects  Pull PROJECTS only (fastest)"
log "  studio-push           Push PROJECTS to VPS now"
log "  studio-push-folder    Push a single project folder"
log "  studio-status         See what's out of sync"
log "  studio-sync           Full pull + push in one go"
log "  studio-log            Watch the live sync log"
log "  studio-ls             List VPS project files"
log "  studio-open           Launch Blender"
log "========================================"
