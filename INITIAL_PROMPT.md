# Initial Prompt for Claude Code

Copy and paste this entire message as your first message when you open a new Claude Code session.

---

I am setting up a plug-and-play GPU workstation pipeline for my production studio (Nairoeel Productions) using Vast.ai VMs for Blender work. Read CLAUDE.md first for the full project context, then read PLAN.md for the implementation steps.

Here is where we are right now:

**Already done:**
- RackNerd VPS running Ubuntu 24.04 with Coolify, Traefik, and File Browser (see docs/VPS_REFERENCE.md)
- VPS storage set up: `/srv/studio/` directory structure, `studio-sync` SFTP user, chroot config
- SFTP connection verified working
- rclone keypair generated, public key on VPS
- Bootstrap script written (`bootstrap.sh`) — handles rclone sync, Blender version detection, addon config, crontab

**What I need help with:**

Pick up from the current phase in PLAN.md. Walk me through each step interactively. For steps that require me to run commands on a Vast.ai VM or on my Windows machine, show me exactly what to run and wait for me to confirm before moving on.

Key docs:
- `docs/VASTAI_QUICKSTART.md` — team setup guide with Moonlight instructions
- `docs/VPS_REFERENCE.md` — VPS server documentation
- `archive/` — old RunPod/Docker approach (archived for reference)
