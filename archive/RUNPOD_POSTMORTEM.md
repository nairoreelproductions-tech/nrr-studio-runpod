# RunPod Docker Approach — Postmortem

## What We Built

A custom Docker image (`nrrdocker24/nrr-studio`) based on `madiator2011/kasm-runpod-desktop:mldesk` that bundled Blender, rclone, Vulkan 1.3, VirtualGL, Tailscale, and Sunshine into a container for RunPod GPU pods. The image was built via GitHub Actions CI and deployed through RunPod templates.

## Why It Didn't Work

RunPod pods are Docker containers with restricted kernel access. This caused cascading issues:

| Problem | Root Cause | Workaround Attempted |
|---|---|---|
| No hardware GPU rendering in VNC | Container has no direct GPU framebuffer | VirtualGL intercepted GL calls — fragile, added latency |
| Vulkan 1.3 missing | Base image Ubuntu 20.04 ships Vulkan 1.1 | Built Vulkan SDK 1.3.283 from source — 40+ min build time |
| Sunshine streaming broken | No `/dev/uinput` for virtual input devices | Tried video-only mode (no keyboard/mouse) — unusable |
| Tailscale kernel mode blocked | No `/dev/net/tun` in container | Userspace networking worked but added latency |
| KasmVNC latency 200–400ms | WebSocket + VNC encoding overhead | No fix possible within the protocol |
| Sunshine .deb install unreliable | LizardByte release naming varies across versions | Tried multiple URL patterns — still fragile |

## What We Learned

1. **Containers are for batch compute, VMs are for workstations.** Interactive desktop use requires direct hardware access that containers cannot provide.
2. **Don't build around platform limitations.** VirtualGL, userspace Tailscale, and video-only Sunshine were all workarounds for missing kernel features. Each one added complexity and reduced quality.
3. **CI minutes add up fast.** Each diagnostic Docker build took 20–40 minutes on GitHub Actions. Three failed builds consumed significant time for incremental debugging.
4. **Third-party apt repos fail in constrained base images.** The `madiator2011` base image had broken apt sources. Static binaries and direct .deb installs were the only reliable approach.

## What We Kept

- **VPS storage layer** — SFTP, studio-sync user, directory structure, rclone config — all unchanged
- **Sync logic** — rclone copy/sync patterns ported directly into the new bootstrap script
- **Secret injection model** — VPS_SSH_KEY_B64 env var pattern reused

## The Pivot

Switched to Vast.ai Ubuntu Desktop VMs, which provide:
- Full KDE Plasma desktop with native GPU access
- Pre-installed Blender, Sunshine, Moonlight, Tailscale
- No Docker, no VirtualGL, no Vulkan hacking
- 20–60ms latency via Moonlight (vs 200–400ms on KasmVNC)

The entire Docker/CI pipeline replaced by a single `bootstrap.sh` that does rclone sync and Blender addon config.
