# NRR Studio

Cloud GPU workstation system for [Nairoeel Productions](https://nairoeel.com). Rent a Vast.ai VM, run one script, and get a full Blender environment with your project files synced from the VPS.
## 📖 [Click here for the Studio Team Manual](VM_MANUAL.md)
## How It Works

```
Your laptop ──► uploads files ──► VPS (source of truth)
                                      │
                                    SFTP
                                      │
Your laptop ──► rents Vast.ai VM ──► bootstrap.sh pulls files
                                     Blender + addons ready
                                     PROJECTS sync back every 5 min
```

- **Storage**: RackNerd VPS with SFTP access via `studio-sync` user
- **Compute**: Vast.ai Ubuntu Desktop VMs with GPU acceleration
- **Sync**: rclone over SFTP, automatic background sync for PROJECTS
- **Access**: WebRTC browser desktop (quick) or Moonlight streaming (low-latency)

## Quick Start

1. Rent an **Ubuntu Desktop (VM)** on [vast.ai](https://vast.ai)
2. SSH into the VM:
   ```
   ssh -p <port> user@<ip>
   ```
3. Run the bootstrap:
   ```bash
   export VPS_SSH_KEY_B64="<your-base64-key>"
   curl -fsSL https://raw.githubusercontent.com/nairoreelproductions-tech/nrr-studio/main/bootstrap.sh | bash
   ```
4. Open Blender and start working in `~/studio/PROJECTS/`

See [VASTAI_QUICKSTART.md](VASTAI_QUICKSTART.md) for the full guide, including Moonlight setup for low-latency streaming.

## Repository Layout

| File | What it does |
|---|---|
| `bootstrap.sh` | Sets up rclone, pulls files from VPS, configures Blender addons, starts sync |
| `launch.ps1` | Windows helper — SSHes into VM and runs bootstrap with your key |
| `.env.studio.template` | Template for storing your SSH key locally (never committed) |
| `VASTAI_QUICKSTART.md` | Step-by-step guide for team members |
| `VPS_REFERENCE.md` | VPS server documentation and SSH cheat sheet |
| `PLAN.md` | Implementation phases and verification steps |
| `archive/` | Old RunPod/Docker approach (kept for reference) |

## Windows Launcher

If you have `.env.studio` set up with your key:

```powershell
.\launch.ps1 -VmIp <instance-ip> -SshPort <mapped-port>
```

This handles the SSH connection and key injection automatically.
