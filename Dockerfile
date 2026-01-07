# Multi-stage Dockerfile for ISC Kea DHCP Server
# Builds DHCP4, DHCP6, and Control Agent from source

# ============================================================================
# Stage 1: Build Dependencies
# ============================================================================
FROM ubuntu:22.04 AS builder

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    meson \
    ninja-build \
    pkg-config \
    libboost-dev \
    libboost-system-dev \
    liblog4cplus-dev \
    libssl-dev \
    libbotan-2-dev \
    flex \
    bison \
    python3 \
    python3-pip \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install meson if not available in Ubuntu repos (meson >= 1.1.0 required)
# Ubuntu 22.04 has meson 0.61, so we need to upgrade
RUN pip3 install --break-system-packages meson>=1.1.0

# Set working directory
WORKDIR /build

# Copy Kea source code
COPY . /build/kea

# Build Kea
WORKDIR /build/kea
RUN meson setup build \
    -Dprefix=/usr \
    -Dcrypto=openssl \
    -Dmysql=false \
    -Dpgsql=false

# Compile Kea (builds all binaries including kea-dhcp4, kea-dhcp6, kea-ctrl-agent)
RUN meson compile -C build

# Install to staging directory
RUN meson install -C build --destdir /build/stage

# ============================================================================
# Stage 2: Runtime Image
# ============================================================================
FROM ubuntu:22.04

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libboost-system1.74.0 \
    liblog4cplus-2.0.5 \
    libssl3 \
    libbotan-2-2 \
    ca-certificates \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Copy installed binaries and libraries from builder
COPY --from=builder /build/stage/usr/sbin/kea-dhcp4 /usr/sbin/kea-dhcp4
COPY --from=builder /build/stage/usr/sbin/kea-dhcp6 /usr/sbin/kea-dhcp6
COPY --from=builder /build/stage/usr/sbin/kea-ctrl-agent /usr/sbin/kea-ctrl-agent
COPY --from=builder /build/stage/usr/lib/ /usr/lib/
COPY --from=builder /build/stage/usr/share/kea/ /usr/share/kea/

# Create necessary directories
RUN mkdir -p /etc/kea /var/lib/kea /var/log/kea /var/run/kea

# Expose ports
# - 67/udp: DHCP4 server
# - 547/udp: DHCP6 server  
# - 8000/tcp: Control Agent REST API
EXPOSE 67/udp 547/udp 8000/tcp

# Default Kea configuration directory
WORKDIR /etc/kea

# Default command runs Control Agent (which can manage both DHCP4 and DHCP6)
# Individual services can be started separately if needed
CMD ["kea-ctrl-agent", "-c", "/etc/kea/kea-dhcp4.conf"]

