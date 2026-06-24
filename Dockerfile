# syntax=docker/dockerfile:1

# ============================================
# Base stage
# ============================================
FROM node:26-trixie-slim@sha256:f9b8bd6c62fcd007c08ce2bb2907485b624b968fd76094445822e0ec14002cf0 AS base

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

# ============================================
# Global build arguments
# ============================================
# renovate: datasource=npm depName=opencode-ai
ARG OPENCODE_VERSION=1.17.10
ARG OPENCODE_SHA256=c943d8f0bde6192f0b8744a0cf9388b4d3d417bec010707da45d50dac960a369

# ============================================
# Stage: OpenCode
# ============================================
FROM base AS opencode

ENV APP_USER=opencode

ARG OPENCODE_VERSION
ARG OPENCODE_SHA256

# Install OpenCode
RUN set -eux; \
    curl -fsSL "https://registry.npmjs.org/opencode-ai/-/opencode-ai-${OPENCODE_VERSION}.tgz" -o /tmp/opencode-ai.tgz; \
    echo "${OPENCODE_SHA256}  /tmp/opencode-ai.tgz" | sha256sum -c; \
    npm install -g /tmp/opencode-ai.tgz && \
    rm /tmp/opencode-ai.tgz && \
    npm cache clean --force

# Remove default node user and create opencode user with UID 1000
RUN userdel -r node && \
    groupadd -g 1000 opencode && \
    useradd -m -u 1000 -g 1000 -s /bin/bash opencode && \
    mkdir -p /workspace /mise && \
    ln -s /workspace /home/opencode/workspace && \
    chown -R 1000:1000 /workspace /mise /home/opencode

# Runtime entrypoint
COPY --chmod=+x entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 4096
WORKDIR /workspace
VOLUME ["/home/opencode/.config/opencode", "/home/opencode/.local/share/opencode", "/mise"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["opencode", "serve", "--hostname", "0.0.0.0", "--port", "4096", "--print-logs"]

# ============================================
# Stage: OpenChamber
# ============================================
FROM base AS openchamber

ENV APP_USER=openchamber

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
ARG OPENCHAMBER_VERSION=1.13.3
ARG OPENCHAMBER_SHA256=df73063aaa245911d7c016bfbed7a2b761bc9fca33407161e8a26d527ee4a48f
RUN set -eux; \
    curl -fsSL "https://registry.npmjs.org/@openchamber/web/-/web-${OPENCHAMBER_VERSION}.tgz" -o /tmp/openchamber-web.tgz; \
    echo "${OPENCHAMBER_SHA256}  /tmp/openchamber-web.tgz" | sha256sum -c; \
    npm install -g /tmp/openchamber-web.tgz && \
    rm /tmp/openchamber-web.tgz && \
    npm cache clean --force

# Remove default node user and create openchamber user with UID 1000
RUN userdel -r node && \
    groupadd -g 1000 openchamber && \
    useradd -m -u 1000 -g 1000 -s /bin/bash openchamber && \
    mkdir -p /workspace /mise && \
    ln -s /workspace /home/openchamber/workspace && \
    chown -R 1000:1000 /workspace /mise /home/openchamber

# Runtime entrypoint
COPY --chmod=+x entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 3000
WORKDIR /workspace
VOLUME ["/home/openchamber/.config/openchamber", "/mise"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["openchamber", "serve", "--foreground", "--port", "3000", "--host", "0.0.0.0"]
