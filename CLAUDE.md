# NRR Cloud Workstation — Claude Code Project Memory

## What This Project Is

A plug-and-play GPU workstation system for Nairoeel Productions. Any team member can rent a Vast.ai VM, run a bootstrap script, and have a full Blender environment with all their files synced from the VPS — ready to work in minutes.

The system has two parts:
1. **VPS storage** (RackNerd, already set up and working)
2. **Bootstrap script** that configures any Vast.ai Ubuntu Desktop VM

---

## Architecture

```
Team member
  │
  ├─── uploads files via File Browser UI ──► /srv/studio/ on VPS (RackNerd)
  │                                               │
  │                                          SFTP (port 22, studio-sync user)
  │                                               │
  └─── rents Vast.ai VM ──────────────────► bootstrap.sh pulls files on first run
                                            crontab syncs PROJECTS back every 5 min
                                            Blender + addons ready on KDE desktop
                                            Access via WebRTC (browser) or Moonlight
```

**Key decisions:**
- Storage uses SFTP over existing SSH (port 22). No new Nginx config.
- Compute uses Vast.ai Ubuntu Desktop (VM) template — full VM, not containers.
- Secrets injected via SSH session env vars ("laptop-as-control-center" model).

---

## The VPS (RackNerd)

See `docs/VPS_REFERENCE.md` for full server documentation.

Critical facts:
- IP: `107.172.153.249`
- Port 22 is open (iptables already allows it)
- OS: Ubuntu 24.04 LTS
- Auth: Ed25519 key only, password auth disabled
- The sshd_config drop-in `/etc/ssh/sshd_config.d/50-cloud-init.conf` overrides the main config
- **Do not touch**: coolify-proxy (Traefik), iptables rules, /data/coolify/, client portal Nginx config
- Before editing sshd_config: always backup first

---

## VPS Storage Structure

```
/srv/studio/                        ← chroot root, owned by ROOT (OpenSSH requirement)
├── BLENDER_APPS/                   ← Blender tarballs (e.g. blender-4.5.7-linux-x64.tar.xz)
├── CONFIG_MASTER/
│   └── scripts/
│       └── addons/                 ← Blender addon folders
├── LIBRARY_GLOBAL/
│   ├── botaniq/
│   └── alpha_trees/
└── PROJECTS/
    └── Your_Project/
        ├── Project_v01.blend
        └── tex/
```

**Critical**: `/srv/studio/` must be owned by `root:root` with permissions `755` (OpenSSH chroot requirement).

---

## The `studio-sync` SSH User

- System user, no shell (`/usr/sbin/nologin`), home is `/srv/studio`
- Authenticates via Ed25519 keypair (separate from the admin key)
- Chrooted to `/srv/studio` via sshd_config `Match User` block
- Can only SFTP, no shell access, no TCP forwarding

---

## Vast.ai VM Setup

- Template: **Ubuntu Desktop (VM)** on Vast.ai
- Desktop user: `user` (password: `password`)
- Pre-installed: Blender, Sunshine, Moonlight, Tailscale, KDE Plasma, GPU drivers
- Bootstrap script: `bootstrap.sh` at repo root
- Studio files: `/home/user/studio/`

### How It Works

1. Team member rents a VM and SSHes in (or uses browser desktop)
2. Exports `VPS_SSH_KEY_B64` env var and runs `bootstrap.sh`
3. Script installs rclone, pulls files from VPS, configures Blender addons, sets up crontab sync
4. Blender is ready with addons; PROJECTS sync back to VPS every 5 minutes

### Blender Version Handling

- If the VM's pre-installed Blender version matches what's on the VPS → uses pre-installed
- If a different version tarball exists in BLENDER_APPS on the VPS → extracts it, creates `blender-studio` wrapper and desktop shortcut
- Addons from CONFIG_MASTER are symlinked into the active Blender's config directory

---

## Environment Variables

| Variable | Description | Where Set |
|---|---|---|
| `VPS_SSH_KEY_B64` | Base64-encoded OpenSSH private key for studio-sync | Exported via SSH session before running bootstrap |

The VPS host IP is hardcoded in `bootstrap.sh` (`107.172.153.249`) since it never changes.

---

## Sync Logic

| Folder | Direction | Frequency |
|---|---|---|
| `BLENDER_APPS/` | VPS → VM (pull only) | Once at bootstrap |
| `CONFIG_MASTER/` | VPS → VM (pull only) | Once at bootstrap |
| `LIBRARY_GLOBAL/` | VPS → VM (pull only) | Once at bootstrap |
| `PROJECTS/` | VPS → VM at bootstrap, VM → VPS ongoing | Pull at bootstrap, push every 5 min via crontab |

Libraries, configs, and Blender are read-only on the VM. Only PROJECTS syncs back.

---

## VM File Structure

```
/home/user/studio/                  ← studio root
├── BLENDER_APPS/                   ← pulled from VPS, may contain extracted blender-app/
├── CONFIG_MASTER/scripts/addons/   ← pulled from VPS, symlinked into Blender config
├── LIBRARY_GLOBAL/                 ← pulled from VPS
└── PROJECTS/                       ← pulled from VPS, syncs back every 5 min
```

---

## Access Methods

| Method | Latency | Setup |
|---|---|---|
| WebRTC (browser) | 50–100ms | Click "Open" in Vast.ai console |
| Moonlight + Sunshine | 20–60ms | Tailscale on both sides, see docs/VASTAI_QUICKSTART.md |
| VNC | 80–150ms | VNC client to mapped port 5900 |
| SSH | N/A | `ssh -p <port> user@<ip>` |

---

## Definition of Done

- [x] `/srv/studio/` directory structure exists on VPS with correct ownership
- [x] `studio-sync` user exists on VPS
- [x] sshd_config `Match User` block in place, SSH restarted
- [x] SFTP connection works
- [x] rclone keypair generated, public key in authorized_keys
- [ ] `bootstrap.sh` runs successfully on a Vast.ai VM
- [ ] Files appear in `~/studio/` after bootstrap
- [ ] Blender launches with addons loaded
- [ ] File created in `~/studio/PROJECTS/` appears on VPS within 5 minutes
- [ ] Moonlight streaming works via Tailscale

---

## What Not to Do

- Do not modify the Nginx config for the client streaming portal
- Do not run `docker system prune -a` on the VPS
- Do not change iptables rules (port 22 is already open)
- Do not use `chmod 777` anywhere
- Do not store private key values in any file in this repo — keys are injected via env vars at runtime
- Do not add log files to the VPS Nginx config without also adding logrotate entries
