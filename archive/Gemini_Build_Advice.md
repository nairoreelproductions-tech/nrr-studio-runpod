To get Blender 4.5.7 LTS running smoothly on a RunPod virtual workstation with Parsec, you're essentially building a high-performance "Headless-to-GUI" bridge. Since you're a "vibe coder," you'll appreciate that the secret sauce isn't just the software—it's how the container talks to the GPU and handles the display buffer.

The reason you lacked root access before was likely due to the template's USER configuration. In your custom Dockerfile, we will stay in root to ensure you have total control.

1. The Blender 4.5.7 LTS Dependencies
Blender 4.x (especially the 2026 LTS releases) requires the VFX Platform 2026 library standards. You need more than just "Open with"; you need the underlying X11 and OpenGL stack.

The must-have libraries:

libx11-6, libxi6, libxxf86vm1, libxrender1: For the windowing system.

libgl1-mesa-glx: For OpenGL rendering.

libkbcommon0: To handle your keyboard input through the remote connection.

libwayland-client0: For modern Linux display compatibility.

2. The Dockerfile Template
This Dockerfile is designed for RunPod. it installs a lightweight XFCE desktop, the specific Blender version you requested, and the Parsec dependencies.

Dockerfile
# Use NVIDIA CUDA base for GPU acceleration
FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV USER=root

# 1. Install System Basics, Desktop, and Blender Dependencies
RUN apt-get update && apt-get install -y \
    xfce4 xfce4-goodies \
    xserver-xorg-video-dummy \
    wget curl xz-utils sudo \
    libgl1 libxi6 libxxf86vm1 libxrender1 libxfixes3 \
    libxcursor1 libxinerama1 libxkbcommon0 libsm6 libice6 \
    libglu1-mesa libglib2.0-0 libfontconfig1 libxext6 \
    && apt-get clean

# 2. Install Parsec
# We download the official .deb. Note: Parsec Host on Linux requires an X-server.
RUN wget https://builds.parsec.app/package/parsec-linux.deb \
    && dpkg -i parsec-linux.deb || apt-get install -y -f \
    && rm parsec-linux.deb

# 3. Setup Blender 4.5.7 LTS
WORKDIR /opt
RUN wget https://mirror.clarkson.edu/blender/release/Blender4.5/blender-4.5.7-linux-x64.tar.xz \
    && tar -xf blender-4.5.7-linux-x64.tar.xz \
    && mv blender-4.5.7-linux-x64 blender \
    && ln -s /opt/blender/blender /usr/local/bin/blender \
    && rm blender-4.5.7-linux-x64.tar.xz

# 4. Configure Virtual Display (Crucial for Parsec/Blender)
COPY xorg.conf /etc/X11/xorg.conf
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Expose Parsec and Web ports
EXPOSE 8080 5900 8000-8010/udp

ENTRYPOINT ["/start.sh"]
3. The Hardware Configuration (xorg.conf)
Since there is no physical monitor plugged into the RunPod GPU, Blender will crash if it doesn't find a display. You need a "Dummy" display config in your folder to copy into the image:

Plaintext
Section "Device"
    Identifier     "Device0"
    Driver         "nvidia"
    VendorName     "NVIDIA Corporation"
EndSection

Section "Screen"
    Identifier     "Screen0"
    Device         "Device0"
    Monitor        "Monitor0"
    DefaultDepth    24
    SubSection     "Display"
        Depth       24
        Modes      "1920x1080"
    EndSubSection
EndSection
4. Why Parsec might be tricky (and the alternative)
Parsec's Linux "Host" support can sometimes be finicky in Docker containers because it expects a logged-in seat.

Pro Tip: If Parsec gives you trouble with "Error 14003" (no display detected), most VFX artists on RunPod use Sunshine (the host) and Moonlight (the client).

Sunshine is open-source and specifically built to handle headless GPU servers like RunPod.

It uses the same low-latency technology as Parsec but is much easier to "vibe code" into a Docker container.

Final Checklist for RunPod:
Port Forwarding: In your RunPod settings, make sure to open UDP ports 8000-8010. Parsec (and Sunshine) uses these for the actual video stream.

Volume Mounts: Map /workspace to a persistent volume so your Blender projects don't vanish when the pod stops.

The "Open With" Fix: Once you're inside the GUI via Parsec/Moonlight, don't right-click the file. Open a terminal and type blender. This will give you the error logs if a library is still missing, which is way more helpful than a silent "Open with" failure.

Does the project you're working on involve heavy Eevee/Cycles rendering, or are you mostly focused on the mechanical rigging side? Knowing that can help me tune the GPU settings in your template.

heavy cycles cause i want to do lookdev stuff mainly, bake smoke sims and so on and finally render. so lets use sinshine and moonlight and you give me a very detailed report of how i should achieve this as i am building the project in vs code suing claude code as my assistant. those instuctions will be a great guide for that project. format it as an md file

Building a high-performance virtual workstation for Blender 4.5.7 LTS on RunPod requires a more sophisticated setup than a standard VNC desktop. Since you're doing heavy Lookdev and smoke simulations, latency is your enemy—which is why Sunshine (Host) and Moonlight (Client) are the right choices.

This report is structured as a technical guide for you and your AI assistant to build a robust Docker template.

🛠️ High-Performance Blender Workstation: Sunshine + Moonlight Deployment
1. Project Overview
This configuration creates an NVIDIA-accelerated Headless Linux Desktop optimized for low-latency 3D production. It bypasses the browser's limitations by streaming directly from the GPU frame buffer to your local Moonlight client.

Key Components:
Base: nvidia/cuda:12.4.1-devel-ubuntu22.04 (Ensures Cycles/OptiX support).

Desktop: XFCE4 (Lightweight and stable for remote sessions).

Streaming: Sunshine (The low-latency host).

Software: Blender 4.5.7 LTS.

2. The Dockerfile Configuration
Save this as Dockerfile. It handles the installation of all graphics libraries, the desktop environment, and the specific Blender version.

Dockerfile
# 1. Base Image with CUDA support for Cycles/OptiX
FROM nvidia/cuda:12.4.1-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV USER=root

# 2. Install System Essentials & Desktop Environment
RUN apt-get update && apt-get install -y \
    xfce4 xfce4-goodies xserver-xorg-video-dummy \
    wget curl xz-utils sudo psmisc \
    libgl1 libxi6 libxxf86vm1 libxrender1 libxfixes3 \
    libxcursor1 libxinerama1 libxkbcommon0 libsm6 libice6 \
    libglu1-mesa libglib2.0-0 libfontconfig1 libxext6 \
    vulkan-tools libvulkan1 \
    && apt-get clean

# 3. Install Sunshine (Streaming Host)
RUN wget https://github.com/LizardByte/Sunshine/releases/latest/download/sunshine-ubuntu-22.04-amd64.deb \
    && dpkg -i sunshine-ubuntu-22.04-amd64.deb || apt-get install -y -f \
    && rm sunshine-ubuntu-22.04-amd64.deb

# 4. Install Blender 4.5.7 LTS
WORKDIR /opt
RUN wget https://mirror.clarkson.edu/blender/release/Blender4.5/blender-4.5.7-linux-x64.tar.xz \
    && tar -xf blender-4.5.7-linux-x64.tar.xz \
    && mv blender-4.5.7-linux-x64 blender \
    && ln -s /opt/blender/blender /usr/local/bin/blender \
    && rm blender-4.5.7-linux-x64.tar.xz

# 5. Configuration Setup
COPY xorg.conf /etc/X11/xorg.conf
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Sunshine Web UI (47990), Streaming (47984-48010)
EXPOSE 47984-47990/tcp 47998-48000/udp 48010/tcp

ENTRYPOINT ["/start.sh"]
3. Required Support Files
xorg.conf (The Virtual Monitor)
Since RunPod GPUs have no monitor, Blender needs this "Dummy" display to initialize the OpenGL context for rendering.

Plaintext
Section "Device"
    Identifier     "Device0"
    Driver         "nvidia"
    VendorName     "NVIDIA Corporation"
EndSection

Section "Screen"
    Identifier     "Screen0"
    Device         "Device0"
    Monitor        "Monitor0"
    DefaultDepth    24
    SubSection     "Display"
        Depth       24
        Modes      "1920x1080"
    EndSubSection
EndSection
start.sh (The Boot Sequence)
This script fires up the virtual display and the Sunshine server.

Bash
#!/bin/bash
# 1. Start Virtual X Server
Xorg -noreset +extension GLX +extension RANDR +extension RENDER -config /etc/X11/xorg.conf :0 &
sleep 2

# 2. Start Desktop Environment
export DISPLAY=:0
startxfce4 &

# 3. Start Sunshine
# Note: You'll need to set a password in the Sunshine Web UI on first run
sunshine &

# Keep container alive
tail -f /dev/null
4. RunPod Deployment Strategy
When setting up your pod on RunPod, you must configure the following:

Network (Port Mapping)
Sunshine requires specific ports to be open to talk to your local Moonlight client:

TCP: 47984, 47989, 48010

UDP: 47998, 47999, 48000

HTTP: Map port 48010 (Web UI) so you can access it via the RunPod "Connect" button to pair your device.

Persistent Volume
Since you're baking smoke simulations, your cache files will be huge.

In RunPod, mount your volume to /workspace.

In Blender, always set your Cache Path for simulations to somewhere inside /workspace/project_name/cache.

5. First-Run Instructions
Launch the Pod: Use your custom template.

Pairing: Click the "Connect" button for the HTTP port 48010. Log in to the Sunshine Web UI.

PIN Entry: Open Moonlight on your local PC. It will find the RunPod server (if using a fixed IP) or you can enter the Pod's IP manually.

Blender Launch: Once connected via Moonlight, open the terminal in the XFCE desktop and type blender.

For Cycles Lookdev:
Go to Preferences > System and select OptiX. Since we used the nvidia/cuda devel image, Blender will have all the toolkit headers it needs to compile kernels for the specific GPU you rented (e.g., RTX 4090 or A6000).