# Implementation Plan — NRR Cloud Workstation

## Overview

Two phases. Phase 1 is complete. Phase 2 is the current work.

---

## Phase 1 — VPS Storage Setup (COMPLETE)

**Goal**: Create the storage directory, a locked-down SFTP user, and verify the connection works.

- [x] Generate rclone Ed25519 keypair
- [x] Create `/srv/studio/` directory structure on VPS with correct ownership
- [x] Create `studio-sync` user (no shell, chrooted)
- [x] Add `Match User` block to sshd_config, restart SSH
- [x] Verify SFTP connection works
- [x] Add public key to authorized_keys

---

## Phase 2 — Vast.ai Bootstrap (CURRENT)

**Goal**: A bootstrap script that configures any Vast.ai Ubuntu Desktop VM into a ready-to-use Blender workstation with VPS file sync.

### What Was Built

| File | Purpose |
|---|---|
| `bootstrap.sh` | Core setup script — rclone, file sync, Blender config, crontab |
| `launch.ps1` | Windows helper to SSH into VM and run bootstrap |
| `.env.studio.template` | Template for team members' local secret storage |
| `docs/VASTAI_QUICKSTART.md` | Step-by-step guide including Moonlight setup |

### Verification Steps

1. Rent a Vast.ai Ubuntu Desktop (VM) — any GPU
2. SSH in: `ssh -p <port> user@<ip>` (password: `password`)
3. Run:
   ```bash
   export VPS_SSH_KEY_B64="<your-key>"
   curl -fsSL https://raw.githubusercontent.com/nairoreelproductions-tech/nrr-studio/main/bootstrap.sh | bash
   ```
4. Verify:
   - `ls ~/studio/PROJECTS/` shows files from VPS
   - `blender --version` works (or `blender-studio` if custom version)
   - Blender → Edit → Preferences → Add-ons shows linked addons
   - `crontab -l` shows the 5-minute sync entry
   - Create a file in `~/studio/PROJECTS/`, wait 5 min, check VPS
5. Test Moonlight (see `docs/VASTAI_QUICKSTART.md` Section B)

---

## Phase 3 — Upload Content to VPS

Once the system is verified, populate the VPS with production content:

- Upload Blender tarball to `/srv/studio/BLENDER_APPS/`
- Upload addon folders to `/srv/studio/CONFIG_MASTER/scripts/addons/`
- Upload asset libraries to `/srv/studio/LIBRARY_GLOBAL/`

---

## Rollback Plan

**VPS sshd_config broke**: Restore backup via VNC (see `docs/VPS_REFERENCE.md` section 5).

**Bootstrap script broken**: Fix the script in the repo and re-run on the VM — the script is idempotent.

**Files lost on VM**: VPS is the source of truth. Spin up a new VM and re-run bootstrap.

**rclone sync issue**: PROJECTS uses `rclone sync` (not `--delete-before`). A bad sync could overwrite VPS files — keep local backups of PROJECTS before major work sessions.
