# Vast.ai Cloud Workstation — Quick Start Guide

This guide covers everything a team member needs to go from zero to working in Blender on a cloud GPU.

---

## A. Spinning Up a Workstation

### Step 1 — Rent a VM

1. Go to [vast.ai](https://vast.ai) and log in
2. Click **Templates** → search for **Ubuntu Desktop (VM)**
3. Pick an instance with a GPU:
   - **Minimum**: RTX 3060 (good for modeling, light viewport work)
   - **Recommended**: RTX 4090 (heavy scenes, EEVEE/Cycles viewport)
4. Click **Rent**
5. Wait for the instance to reach **Running** status (1–3 minutes)

### Step 2 — Access the Desktop

Click the **Open** button in the Vast.ai console. This opens the WebRTC browser desktop (Selkies) on port 6100. You now have a full KDE Plasma desktop with GPU acceleration.

**Default credentials:**
- Desktop username: `user`
- Desktop password: `password`

You can also SSH in for terminal access:
```
ssh -p <mapped-port> user@<instance-ip>
```
The mapped port and IP are shown in the Vast.ai console.

### Step 3 — Run the Bootstrap

Open a terminal on the VM desktop (or SSH in) and run:

```bash
export VPS_SSH_KEY_B64="<paste-your-base64-key-here>"
curl -fsSL https://raw.githubusercontent.com/nairoreelproductions-tech/nrr-studio/main/bootstrap.sh | bash
```

Get the base64 key from your team lead, or generate it from your local `studio_sync_key` file:
```powershell
# PowerShell (on your Windows laptop)
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\.ssh\studio_sync_key"))
```

**Alternative**: Use the `launch.ps1` helper script from your Windows laptop — it handles the SSH connection and key injection for you:
```powershell
.\launch.ps1 -VmIp <instance-ip> -SshPort <mapped-port>
```

### Step 4 — Wait for Sync

The bootstrap pulls files from the VPS. Timing depends on library size:
- CONFIG_MASTER + PROJECTS: 1–2 minutes
- LIBRARY_GLOBAL: 5–20 minutes (large asset packs)

Watch the output for progress. When you see `NRR Studio bootstrap complete!`, you're ready.

### Step 5 — Work

- Open **Blender** from the KDE applications menu
  - If the bootstrap installed a specific version from the VPS, use the **Blender Studio** desktop shortcut instead (or run `blender-studio` in the terminal)
- Your addons from CONFIG_MASTER are already linked
- Work in `~/studio/PROJECTS/`
- Changes sync back to the VPS **every 5 minutes** automatically

### Step 6 — Stop When Done

When you're finished for the day, **stop the instance** in the Vast.ai console. Your files are safe on the VPS — next time you spin up a new VM and run the bootstrap, everything comes back.

---

## B. Moonlight Setup (Low-Latency Streaming)

The browser desktop (WebRTC) has ~50–100ms latency. For sculpting, animation, or any work where input lag matters, switch to **Moonlight + Sunshine** for 20–60ms latency.

### One-Time Setup on Your Windows PC

You only need to do this once.

#### 1. Install Tailscale
- Download from [tailscale.com/download](https://tailscale.com/download)
- Install and sign in with the team's Tailscale account
- Tailscale creates a private network between your PC and the VM — no ports to forward, no firewall rules

#### 2. Install Moonlight
- Download from [moonlight-stream.org](https://moonlight-stream.org)
- Install the Windows client
- Moonlight is a game-streaming client that connects to Sunshine (the server running on the VM)

### Per-Session: VM Side

Each time you spin up a new VM, do this once:

1. Open a terminal on the VM (via WebRTC browser desktop or SSH)
2. Join the Tailscale network:
   ```bash
   sudo tailscale up
   ```
3. A URL will appear — open it in a browser to authorize the VM on your Tailscale network
4. Get the VM's Tailscale IP:
   ```bash
   tailscale ip
   ```
   This gives you a `100.x.x.x` address — note it down.

Sunshine is already installed and running on the VM. No extra setup needed.

### Per-Session: Your Windows PC

1. Make sure **Tailscale is connected** on your PC (system tray icon should show "Connected")
2. Open **Moonlight**
3. Click **Add Host** (or the `+` button)
4. Enter the VM's **Tailscale IP** (the `100.x.x.x` address from above)
5. Moonlight will discover Sunshine and show a **pairing PIN** on the VM's screen
6. Enter the PIN in Moonlight
7. Click the VM to connect — you now have a low-latency desktop stream

### Moonlight Settings for Blender Work

For the best experience with 3D viewports:

| Setting | Recommended Value |
|---|---|
| Resolution | Match your monitor (1080p or 1440p) |
| FPS | 60 |
| Bitrate | 20–40 Mbps (higher = sharper, needs good internet) |
| Video codec | H.265 (HEVC) if your PC supports it, H.264 otherwise |
| Mouse mode | Direct (not relative) |

### Notes

- **WebRTC and Moonlight can run simultaneously** — start with the browser desktop for quick access, switch to Moonlight when you need precision
- **Tailscale auth persists** until the VM is destroyed — you only need to `tailscale up` once per instance
- If Moonlight can't find the host, verify both your PC and the VM show as "Connected" in the [Tailscale admin console](https://login.tailscale.com/admin/machines)
- If you see a black screen in Moonlight, the VM's display server may not be ready yet — wait 30 seconds and try again

---

## C. Access Methods at a Glance

| Method | Latency | Best For | How |
|---|---|---|---|
| WebRTC (browser) | 50–100ms | Quick access, light work, setup | Click "Open" in Vast.ai console |
| Moonlight + Sunshine | 20–60ms | Sculpting, animation, heavy viewport | See Section B above |
| VNC | 80–150ms | Fallback, mobile devices | Connect VNC client to `<ip>:<port-5900>` |
| SSH | N/A | Terminal, file management | `ssh -p <port> user@<ip>` |

---

## D. Troubleshooting

**Bootstrap fails with "Cannot connect to VPS"**
- Check that VPS_SSH_KEY_B64 is set correctly (no quotes, no linebreaks)
- Test manually: `sftp -i ~/.ssh/studio_sync_key studio-sync@107.172.153.249`
- Check VPS is online: `ping 107.172.153.249`

**Blender won't launch**
- Check GPU is detected: `nvidia-smi`
- Try from terminal to see error output: `blender` or `blender-studio`

**Addons not showing in Blender**
- Check the symlinks: `ls -la ~/.config/blender/*/scripts/addons/`
- Make sure CONFIG_MASTER has addons on the VPS: files should be in `/srv/studio/CONFIG_MASTER/scripts/addons/`

**Files not syncing back to VPS**
- Check crontab is set: `crontab -l` (should show the rclone sync entry)
- Check cron is running: `systemctl status cron`
- Force a manual sync: `rclone sync ~/studio/PROJECTS vps:/PROJECTS --transfers=4 -v`
- Check log: `tail -50 ~/studio/bootstrap.log`
