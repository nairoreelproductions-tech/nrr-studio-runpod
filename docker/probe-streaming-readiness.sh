#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# Streaming Readiness Probe — Phase 1 Diagnostic
# Runs at pod startup to answer all unknowns before full build.
# Results logged to /workspace/startup.log
# ──────────────────────────────────────────────────────────────

LOG=/workspace/startup.log
log() { echo "[probe] $*" | tee -a "$LOG"; }

log "=========================================================="
log "STREAMING READINESS PROBE — $(date)"
log "=========================================================="

# ── 1. OS version ────────────────────────────────────────────
log "--- OS VERSION ---"
cat /etc/os-release >> "$LOG" 2>&1

# ── 2. TUN device (Tailscale WireGuard needs this) ──────────
log "--- TUN DEVICE (/dev/net/tun) ---"
if [ -e /dev/net/tun ]; then
    log "OK: /dev/net/tun exists"
    ls -la /dev/net/tun >> "$LOG" 2>&1
else
    log "MISSING: /dev/net/tun — Tailscale kernel WireGuard will fail"
    log "Attempting to create it..."
    mkdir -p /dev/net 2>/dev/null
    if mknod /dev/net/tun c 10 200 2>>"$LOG"; then
        log "CREATED: /dev/net/tun — manual creation worked"
        ls -la /dev/net/tun >> "$LOG" 2>&1
    else
        log "CANNOT create TUN device — will need userspace networking"
    fi
fi

# ── 3. uinput device (Sunshine virtual input) ───────────────
log "--- UINPUT DEVICE (/dev/uinput) ---"
if [ -e /dev/uinput ]; then
    log "OK: /dev/uinput exists"
    ls -la /dev/uinput >> "$LOG" 2>&1
else
    log "MISSING: /dev/uinput — trying modprobe..."
    if modprobe uinput 2>>"$LOG"; then
        log "modprobe uinput: OK"
        if [ -e /dev/uinput ]; then
            log "NOW EXISTS: /dev/uinput"
            ls -la /dev/uinput >> "$LOG" 2>&1
        else
            log "STILL MISSING after modprobe — Moonlight mouse/keyboard won't work"
        fi
    else
        log "modprobe FAILED — Moonlight input won't work (video-only fallback)"
    fi
fi

# ── 4. Container capabilities ───────────────────────────────
log "--- CAPABILITIES ---"
if command -v capsh >/dev/null 2>&1; then
    capsh --print >> "$LOG" 2>&1
else
    log "capsh not available — reading /proc/self/status"
    grep -i cap /proc/self/status >> "$LOG" 2>&1
fi

# ── 5. Privileged container check ───────────────────────────
log "--- PRIVILEGED CHECK ---"
if ip link add dummy0 type dummy 2>/dev/null; then
    ip link del dummy0 2>/dev/null
    log "OK: Container IS privileged (can create network devices)"
else
    log "WARNING: Container may NOT be privileged"
fi

# ── 6. NET_ADMIN capability (Tailscale needs this) ──────────
log "--- NET_ADMIN CHECK ---"
if ip tuntap add mode tun test-tun 2>/dev/null; then
    ip tuntap del mode tun test-tun 2>/dev/null
    log "OK: NET_ADMIN capability available"
else
    log "WARNING: NET_ADMIN may not be available — Tailscale may need --tun=userspace-networking"
fi

# ── 7. Tailscale daemon test ────────────────────────────────
log "--- TAILSCALE TEST ---"
if command -v tailscaled >/dev/null 2>&1; then
    tailscale version >> "$LOG" 2>&1
    log "Starting tailscaled for socket test..."
    tailscaled --state=/var/lib/tailscale/tailscaled.state \
               --socket=/var/run/tailscale/tailscaled.sock &
    TS_PID=$!
    sleep 3
    if [ -S /var/run/tailscale/tailscaled.sock ]; then
        log "OK: tailscaled socket created — daemon is running"
        tailscale --socket=/var/run/tailscale/tailscaled.sock status 2>>"$LOG" \
            || log "tailscale status: not logged in (expected — no TS_AUTHKEY for probe)"
    else
        log "FAILED: tailscaled socket NOT created after 3s"
        # Check if it crashed
        if kill -0 "$TS_PID" 2>/dev/null; then
            log "tailscaled PID $TS_PID is still running — may need more time"
        else
            log "tailscaled PID $TS_PID has exited — check for errors above"
        fi
    fi
    kill "$TS_PID" 2>/dev/null
    wait "$TS_PID" 2>/dev/null
else
    log "MISSING: tailscaled not installed — Tailscale install failed at build time"
fi

# ── 8. X11 display server ───────────────────────────────────
log "--- DISPLAY SERVER ---"
log "DISPLAY env var = '${DISPLAY}'"

# Wait for KasmVNC to start the display (it launches after this script)
DISPLAY_FOUND=0
for i in $(seq 1 60); do
    if xdpyinfo -display :1 >/dev/null 2>&1; then
        log "OK: X11 display :1 is active (found after ${i}s)"
        xdpyinfo -display :1 2>&1 | head -20 >> "$LOG"
        DISPLAY_FOUND=1
        break
    fi
    sleep 1
done

if [ "$DISPLAY_FOUND" -eq 0 ]; then
    log "TIMEOUT: display :1 not available after 60s"
    log "Checking for any X displays..."
    for d in 0 1 2 10; do
        if xdpyinfo -display ":$d" >/dev/null 2>&1; then
            log "FOUND: display :$d is active"
        fi
    done
fi

# ── 9. X11 authority / access control ───────────────────────
log "--- XAUTHORITY ---"
log "XAUTHORITY env var = '${XAUTHORITY}'"
log "Searching for .Xauthority files..."
find / -maxdepth 4 -name ".Xauthority" 2>/dev/null | while read f; do
    log "  Found: $f (owner: $(stat -c '%U:%G' "$f" 2>/dev/null || echo 'unknown'))"
done

if [ "$DISPLAY_FOUND" -eq 1 ]; then
    log "Testing xhost access control on :1..."
    DISPLAY=:1 xhost 2>>"$LOG" || log "xhost command failed or not available"
fi

# ── 10. GPU and Vulkan ──────────────────────────────────────
log "--- GPU & VULKAN ---"
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi >> "$LOG" 2>&1
else
    log "nvidia-smi not available"
fi

log "VK_ICD_FILENAMES = '${VK_ICD_FILENAMES}'"
log "Vulkan ICD directory contents:"
ls -la /usr/share/vulkan/icd.d/ >> "$LOG" 2>&1 || log "No /usr/share/vulkan/icd.d/ directory"

if command -v vulkaninfo >/dev/null 2>&1; then
    log "Running vulkaninfo --summary..."
    DISPLAY=:1 vulkaninfo --summary >> "$LOG" 2>&1 || log "vulkaninfo failed"
else
    log "vulkaninfo not installed"
fi

# ── 11. Sunshine binary ─────────────────────────────────────
log "--- SUNSHINE ---"
if command -v sunshine >/dev/null 2>&1; then
    log "Sunshine binary found at: $(which sunshine)"
    sunshine --version >> "$LOG" 2>&1 || log "sunshine --version failed"
    log "Checking for --creds flag..."
    if sunshine --help 2>&1 | grep -qi "cred"; then
        log "OK: --creds flag appears to exist"
        sunshine --help 2>&1 | grep -i "cred" >> "$LOG"
    else
        log "NO --creds flag found — may need different auth setup method"
        log "Full --help output (first 30 lines):"
        sunshine --help 2>&1 | head -30 >> "$LOG"
    fi
else
    log "MISSING: sunshine binary not found — install failed at build time"
fi

# ── 12. Audio state (should be minimal) ─────────────────────
log "--- AUDIO STATE ---"
log "Installed audio-related packages:"
dpkg -l 2>/dev/null | grep -iE "pulse|pipewire|alsa" >> "$LOG" 2>&1 \
    || log "No audio packages detected"
log "Running audio processes:"
ps aux | grep -iE "pulse|pipewire" | grep -v grep >> "$LOG" 2>&1 \
    || log "No audio processes running"

# ── 13. KasmVNC process info ────────────────────────────────
log "--- KASMVNC ---"
log "KasmVNC/VNC processes:"
ps aux | grep -iE "kasm|vnc|Xvnc" | grep -v grep >> "$LOG" 2>&1 \
    || log "No VNC processes found (may not have started yet)"

# ── 14. Network interfaces ──────────────────────────────────
log "--- NETWORK INTERFACES ---"
ip addr show >> "$LOG" 2>&1 || log "ip addr failed"

log "=========================================================="
log "PROBE COMPLETE"
log "Review this log via KasmVNC: cat /workspace/startup.log"
log "=========================================================="
