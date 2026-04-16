#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# NRR Cloud Workstation — Vast.ai VM Bootstrap
# Sets up rclone sync, Blender addons, and background project sync.
# Idempotent — safe to run multiple times.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

STUDIO_ROOT="$HOME/studio"
VPS_HOST="107.172.153.249"
VPS_USER="studio-sync"
LOG="$STUDIO_ROOT/bootstrap.log"

# ── Logging ─────────────────────────────────────────────────
mkdir -p "$STUDIO_ROOT"
log() { echo "[nrr] $(date '+%H:%M:%S') $*" | tee -a "$LOG"; }

log "========================================"
log "NRR Studio bootstrap starting"
log "========================================"

# ── Section 1: Validate environment ─────────────────────────
log "Checking GPU..."
if command -v nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    log "GPU detected: $GPU_NAME"
else
    log "WARNING: nvidia-smi not found. Blender will run in CPU mode."
fi

# ── Section 2: Install rclone ───────────────────────────────
if command -v rclone &>/dev/null; then
    log "rclone already installed: $(rclone version | head -1)"
else
    log "Installing rclone..."
    curl -fsSL https://rclone.org/install.sh | sudo bash
    log "rclone installed: $(rclone version | head -1)"
fi

# ── Section 3: SSH key setup ───────────────────────────────
if [ -z "${VPS_SSH_KEY_B64:-}" ]; then
    log "ERROR: VPS_SSH_KEY_B64 is not set."
    log "Run:  export VPS_SSH_KEY_B64=\"<your-base64-key>\"  then re-run this script."
    exit 1
fi

log "Decoding SSH key..."
mkdir -p "$HOME/.ssh"
echo "$VPS_SSH_KEY_B64" | base64 -d > "$HOME/.ssh/studio_sync_key"
chmod 600 "$HOME/.ssh/studio_sync_key"

log "Adding VPS to known_hosts..."
ssh-keyscan -p 22 "$VPS_HOST" >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
# Deduplicate known_hosts entries
sort -u "$HOME/.ssh/known_hosts" -o "$HOME/.ssh/known_hosts"

# ── Section 4: rclone config ───────────────────────────────
log "Writing rclone config..."
mkdir -p "$HOME/.config/rclone"
cat > "$HOME/.config/rclone/rclone.conf" << EOF
[vps]
type = sftp
host = $VPS_HOST
port = 22
user = $VPS_USER
key_file = $HOME/.ssh/studio_sync_key
EOF

# ── Section 5: Test SFTP connectivity ───────────────────────
log "Testing SFTP connection to VPS..."
if rclone lsd vps:/ >> "$LOG" 2>&1; then
    log "VPS connection OK."
else
    log "ERROR: Cannot connect to VPS. Check SSH key and VPS config."
    log "Verify manually:  sftp -i ~/.ssh/studio_sync_key $VPS_USER@$VPS_HOST"
    exit 1
fi

# ── Section 6: Create directory structure ───────────────────
log "Creating studio directories..."
mkdir -p \
    "$STUDIO_ROOT/BLENDER_APPS" \
    "$STUDIO_ROOT/CONFIG_MASTER/scripts/addons" \
    "$STUDIO_ROOT/LIBRARY_GLOBAL" \
    "$STUDIO_ROOT/PROJECTS"

# ── Section 7: Pull files from VPS ──────────────────────────
log "Pulling CONFIG_MASTER from VPS..."
rclone copy vps:/CONFIG_MASTER "$STUDIO_ROOT/CONFIG_MASTER" \
    --transfers=4 --stats=10s --stats-log-level=NOTICE 2>&1 | tee -a "$LOG" \
    || log "WARN: CONFIG_MASTER sync had errors"

log "Pulling LIBRARY_GLOBAL from VPS (this may take a while)..."
rclone copy vps:/LIBRARY_GLOBAL "$STUDIO_ROOT/LIBRARY_GLOBAL" \
    --transfers=8 --stats=10s --stats-log-level=NOTICE 2>&1 | tee -a "$LOG" \
    || log "WARN: LIBRARY_GLOBAL sync had errors"

log "Pulling PROJECTS from VPS..."
rclone copy vps:/PROJECTS "$STUDIO_ROOT/PROJECTS" \
    --transfers=4 --stats=10s --stats-log-level=NOTICE 2>&1 | tee -a "$LOG" \
    || log "WARN: PROJECTS sync had errors"

log "Pulling BLENDER_APPS from VPS..."
rclone copy vps:/BLENDER_APPS "$STUDIO_ROOT/BLENDER_APPS" \
    --transfers=4 --stats=10s --stats-log-level=NOTICE 2>&1 | tee -a "$LOG" \
    || log "WARN: BLENDER_APPS sync had errors"

# ── Section 8: Blender version detection + addon setup ──────
log "Configuring Blender..."

# Detect pre-installed Blender version
SYSTEM_BLENDER=""
SYSTEM_BLENDER_VER=""
if command -v blender &>/dev/null; then
    SYSTEM_BLENDER="$(command -v blender)"
    SYSTEM_BLENDER_VER="$(blender --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)"
    log "Pre-installed Blender: $SYSTEM_BLENDER_VER at $SYSTEM_BLENDER"
fi

# Check if we have a tarball from VPS with a different version
BLENDER_TAR="$(ls "$STUDIO_ROOT/BLENDER_APPS/blender-"*.tar.xz 2>/dev/null | head -1 || true)"
ACTIVE_BLENDER_VER="$SYSTEM_BLENDER_VER"
USING_CUSTOM_BLENDER=false

if [ -n "$BLENDER_TAR" ]; then
    # Extract version from tarball filename (e.g. blender-4.5.7-linux-x64.tar.xz → 4.5.7)
    TAR_VER="$(basename "$BLENDER_TAR" | grep -oP '\d+\.\d+\.\d+' | head -1)"

    if [ -n "$TAR_VER" ] && [ "$TAR_VER" != "$SYSTEM_BLENDER_VER" ]; then
        log "Version mismatch: VM has $SYSTEM_BLENDER_VER, VPS has $TAR_VER"
        log "Extracting Blender $TAR_VER from VPS tarball..."

        if [ ! -d "$STUDIO_ROOT/BLENDER_APPS/blender-app" ]; then
            tar -xf "$BLENDER_TAR" -C "$STUDIO_ROOT/BLENDER_APPS/"
            BLENDER_DIR="$(ls -d "$STUDIO_ROOT/BLENDER_APPS/blender-"*-linux-x64 2>/dev/null | head -1 || true)"
            if [ -n "$BLENDER_DIR" ]; then
                mv "$BLENDER_DIR" "$STUDIO_ROOT/BLENDER_APPS/blender-app"
            fi
        fi

        if [ -f "$STUDIO_ROOT/BLENDER_APPS/blender-app/blender" ]; then
            # Create wrapper in ~/bin so it's on PATH
            mkdir -p "$HOME/bin"
            cat > "$HOME/bin/blender-studio" << 'WRAPPER'
#!/usr/bin/env bash
exec "$HOME/studio/BLENDER_APPS/blender-app/blender" "$@"
WRAPPER
            chmod +x "$HOME/bin/blender-studio"

            # Create desktop shortcut
            ICON_PATH="$STUDIO_ROOT/BLENDER_APPS/blender-app/blender.svg"
            [ -f "$ICON_PATH" ] || ICON_PATH="blender"
            mkdir -p "$HOME/Desktop"
            cat > "$HOME/Desktop/Blender-Studio.desktop" << SHORTCUT
[Desktop Entry]
Name=Blender $TAR_VER (Studio)
Exec=$HOME/bin/blender-studio %f
Icon=$ICON_PATH
Type=Application
Terminal=false
Categories=Graphics;3DGraphics;
SHORTCUT
            chmod +x "$HOME/Desktop/Blender-Studio.desktop"

            ACTIVE_BLENDER_VER="$TAR_VER"
            USING_CUSTOM_BLENDER=true
            log "Using Blender $TAR_VER from VPS (VM has $SYSTEM_BLENDER_VER)"
        else
            log "WARN: Extraction failed. Falling back to pre-installed Blender."
        fi
    else
        log "Tarball version matches system ($SYSTEM_BLENDER_VER). Using pre-installed Blender."
    fi
else
    log "No Blender tarball on VPS. Using pre-installed Blender."
fi

# Symlink addons from CONFIG_MASTER into Blender's config directory
if [ -n "$ACTIVE_BLENDER_VER" ]; then
    # Blender config uses major.minor (e.g. 4.5, not 4.5.7)
    BLENDER_MAJOR_MINOR="$(echo "$ACTIVE_BLENDER_VER" | grep -oP '^\d+\.\d+')"
    ADDON_TARGET="$HOME/.config/blender/$BLENDER_MAJOR_MINOR/scripts/addons"
    ADDON_SOURCE="$STUDIO_ROOT/CONFIG_MASTER/scripts/addons"

    if [ -d "$ADDON_SOURCE" ] && [ "$(ls -A "$ADDON_SOURCE" 2>/dev/null)" ]; then
        mkdir -p "$ADDON_TARGET"
        for addon in "$ADDON_SOURCE"/*/; do
            addon_name="$(basename "$addon")"
            if [ -d "$addon" ]; then
                ln -sfn "$addon" "$ADDON_TARGET/$addon_name"
                log "Linked addon: $addon_name"
            fi
        done
        # Also link any single-file .py addons
        for addon_file in "$ADDON_SOURCE"/*.py; do
            [ -f "$addon_file" ] || continue
            ln -sf "$addon_file" "$ADDON_TARGET/$(basename "$addon_file")"
            log "Linked addon file: $(basename "$addon_file")"
        done
        log "Addons linked into $ADDON_TARGET"
    else
        log "No addons found in CONFIG_MASTER/scripts/addons/"
    fi
else
    log "WARN: Could not determine Blender version. Skipping addon setup."
fi

# ── Section 9: Background PROJECTS sync via crontab ─────────
CRON_CMD="rclone sync $STUDIO_ROOT/PROJECTS vps:/PROJECTS --transfers=4 2>>$LOG"
CRON_ENTRY="*/5 * * * * $CRON_CMD"

if crontab -l 2>/dev/null | grep -qF "vps:/PROJECTS"; then
    log "Crontab sync already configured."
else
    # Ensure cron is running
    if command -v systemctl &>/dev/null; then
        sudo systemctl start cron 2>/dev/null || true
    fi
    # Add the entry
    (crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -
    log "Crontab configured: PROJECTS sync every 5 minutes."
fi

# ── Section 10: Summary ────────────────────────────────────
log "========================================"
log "NRR Studio bootstrap complete!"
log "========================================"
log ""
log "  Studio root:    $STUDIO_ROOT"
if [ "$USING_CUSTOM_BLENDER" = true ]; then
    log "  Blender:        $ACTIVE_BLENDER_VER (from VPS — run: blender-studio)"
else
    log "  Blender:        $ACTIVE_BLENDER_VER (pre-installed — run: blender)"
fi
log "  Projects:       $STUDIO_ROOT/PROJECTS/"
log "  Sync:           PROJECTS → VPS every 5 min (crontab)"
log "  Log:            $LOG"
log ""
log "  For Moonlight setup, see: docs/VASTAI_QUICKSTART.md"
log ""
