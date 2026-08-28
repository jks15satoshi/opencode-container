# syntax=docker/dockerfile:1

# ============================================
# Base stage
# ============================================
FROM node:26-trixie-slim@sha256:c0753125a3789977aefe869cbebccf70e3cfd7ea84ca48547458f02e4f1d7146 AS base

# renovate: datasource=npm depName=bun
ARG BUN_VERSION=1.4.0
ARG BUN_SHA256_AMD64=2d03fb5fb83ac8b567aca0a281b2ce1a1a19d488f56c2968d88c3f25e92fe452
ARG BUN_SHA256_ARM64=4b1a332ee861983eb93bcfe6f770fff94e3e31b2c388bdaea3c8ed35e58eed0e

# Install common agent tools / dev dependencies + gosu for privilege dropping
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    dnsutils \
    git \
    gosu \
    htop \
    jq \
    less \
    libssl-dev \
    openssh-client \
    pkg-config \
    procps \
    python3 \
    ripgrep \
    tree \
    unzip \
    wget \
    zip && \
    rm -rf /var/lib/apt/lists/*

# Install common LSP servers and tools
RUN npm install -g \
    bash-language-server \
    yaml-language-server \
    dockerfile-language-server-nodejs \
    prettier && \
    npm cache clean --force

# Install Mise for managing runtime devtools
ENV MISE_DATA_DIR=/mise
ENV MISE_CACHE_DIR=/mise/cache
ENV MISE_INSTALL_PATH=/usr/local/bin/mise
ENV MISE_TRUSTED_CONFIG_PATHS="/"
ENV PATH="/mise/shims:${PATH}"

RUN curl -fsSL https://mise.run | sh

# Install Bun for plugin auto-install
ARG TARGETARCH
ARG BUN_VERSION
ARG BUN_SHA256_AMD64
ARG BUN_SHA256_ARM64
RUN set -eux; \
    case "${TARGETARCH}" in \
    amd64) BUN_ARCH="x64"; BUN_SHA256="${BUN_SHA256_AMD64}" ;; \
    arm64) BUN_ARCH="aarch64"; BUN_SHA256="${BUN_SHA256_ARM64}" ;; \
    *) echo "Unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-linux-${BUN_ARCH}.zip" \
    -o /tmp/bun.zip; \
    echo "${BUN_SHA256}  /tmp/bun.zip" | sha256sum -c; \
    unzip -q -o /tmp/bun.zip -d /tmp/bun-extract; \
    cp "/tmp/bun-extract/bun-linux-${BUN_ARCH}/bun" /usr/local/bin/bun; \
    chmod +x /usr/local/bin/bun; \
    rm -rf /tmp/bun.zip /tmp/bun-extract; \
    bun --version

# ============================================
# Create unified system user
# ============================================
RUN userdel -r node && \
    groupadd -g 1000 opencode && \
    useradd -m -u 1000 -g 1000 -s /bin/bash opencode && \
    mkdir -p /workspace /mise /secrets/ssh && \
    ln -s /workspace /home/opencode/workspace && \
    chown -R 1000:1000 /workspace /mise /home/opencode /secrets

COPY --chmod=+x entrypoint.sh /usr/local/bin/entrypoint.sh
ENV SYSTEM_USER=opencode

# ============================================
# Global build arguments
# ============================================
# renovate: datasource=npm depName=opencode-ai
ARG OPENCODE_VERSION=1.18.25
ARG OPENCODE_SHA256=9be29b0858b3c9bb1214569f1d8e48a783956c8f5093cc6dcd86717e2cd8c5a3

# ============================================
# Stage: OpenCode
# ============================================
FROM base AS opencode

ENV APP=opencode

ARG OPENCODE_VERSION
ARG OPENCODE_SHA256

# Install OpenCode
RUN set -eux; \
    curl -fsSL "https://registry.npmjs.org/opencode-ai/-/opencode-ai-${OPENCODE_VERSION}.tgz" -o /tmp/opencode-ai.tgz; \
    echo "${OPENCODE_SHA256}  /tmp/opencode-ai.tgz" | sha256sum -c; \
    npm install -g /tmp/opencode-ai.tgz && \
    rm /tmp/opencode-ai.tgz && \
    npm cache clean --force

EXPOSE 4096
WORKDIR /workspace
VOLUME ["/home/opencode/.config/opencode", "/home/opencode/.local/share/opencode", "/mise"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["opencode", "serve", "--hostname", "0.0.0.0", "--port", "4096", "--print-logs"]

# ============================================
# Stage: OpenChamber
# ============================================
FROM base AS openchamber

ENV APP=openchamber

ARG OPENCODE_VERSION
ARG OPENCODE_SHA256

# Install OpenCode (whose CLI is required by OpenChamber)
RUN set -eux; \
    curl -fsSL "https://registry.npmjs.org/opencode-ai/-/opencode-ai-${OPENCODE_VERSION}.tgz" -o /tmp/opencode-ai.tgz; \
    echo "${OPENCODE_SHA256}  /tmp/opencode-ai.tgz" | sha256sum -c; \
    npm install -g /tmp/opencode-ai.tgz && \
    rm /tmp/opencode-ai.tgz && \
    npm cache clean --force

# Install OpenChamber
# renovate: datasource=npm depName=@openchamber/web
ARG OPENCHAMBER_VERSION=1.21.0
ARG OPENCHAMBER_SHA256=c3d72eed1834dc74632408d1bc21d471f0ffa3b4efb82fb740ca534a8d26e1f9
RUN set -eux; \
    curl -fsSL "https://registry.npmjs.org/@openchamber/web/-/web-${OPENCHAMBER_VERSION}.tgz" -o /tmp/openchamber-web.tgz; \
    echo "${OPENCHAMBER_SHA256}  /tmp/openchamber-web.tgz" | sha256sum -c; \
    npm install -g /tmp/openchamber-web.tgz && \
    rm /tmp/openchamber-web.tgz && \
    npm cache clean --force

EXPOSE 3000
WORKDIR /workspace
VOLUME ["/home/opencode/.config/openchamber", "/mise"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["openchamber", "serve", "--foreground", "--port", "3000", "--host", "0.0.0.0"]
