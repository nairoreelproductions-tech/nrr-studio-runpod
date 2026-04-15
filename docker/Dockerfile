FROM madiator2011/kasm-runpod-desktop:mldesk

USER root

# Install runtime deps + build tools for Vulkan 1.3 loader
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl openssh-client \
    build-essential git pkg-config \
    libxcb1-dev libx11-xcb-dev libxrandr-dev libwayland-dev \
    && rm -rf /var/lib/apt/lists/*

# Install rclone
RUN curl https://rclone.org/install.sh | bash

# Upgrade cmake (Ubuntu 20.04 ships 3.16, Vulkan-Loader needs 3.17+)
RUN pip3 install cmake

# Build Vulkan 1.3 Headers + Loader from source (Blender 4.5+ needs Vulkan 1.3)
RUN cd /tmp \
    && git clone --branch v1.3.283 --depth 1 https://github.com/KhronosGroup/Vulkan-Headers.git \
    && cmake -S Vulkan-Headers -B Vulkan-Headers/build -DCMAKE_INSTALL_PREFIX=/usr \
    && cmake --install Vulkan-Headers/build \
    && git clone --branch v1.3.283 --depth 1 https://github.com/KhronosGroup/Vulkan-Loader.git \
    && cmake -S Vulkan-Loader -B Vulkan-Loader/build -DCMAKE_BUILD_TYPE=Release \
    && cmake --build Vulkan-Loader/build -j$(nproc) \
    && cmake --install Vulkan-Loader/build \
    && ldconfig \
    && rm -rf /tmp/Vulkan-Headers /tmp/Vulkan-Loader

# Copy and register the startup wrapper
COPY fix-workspace-and-start.sh /usr/local/bin/fix-workspace-and-start.sh
RUN chmod +x /usr/local/bin/fix-workspace-and-start.sh

ENTRYPOINT ["/usr/local/bin/fix-workspace-and-start.sh"]
