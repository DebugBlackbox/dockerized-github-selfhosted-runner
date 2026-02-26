# GitHub Actions Self-Hosted Runner
# Builds for the host's native architecture automatically (amd64, arm64, …).
FROM ubuntu:24.04

# ── Arguments (override at build time) ────────────────────────────────────────
ARG RUNNER_VERSION=2.323.0
# Optional: pass --build-arg TARGETARCH=arm64 to cross-compile.
# If not set, the arch is detected dynamically from the build host (uname -m).
ARG TARGETARCH

# ── Environment ────────────────────────────────────────────────────────────────
ENV DEBIAN_FRONTEND=noninteractive \
    RUNNER_HOME=/home/runner/actions-runner

# ── System dependencies ────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Runner prerequisites
    curl \
    wget \
    unzip \
    git \
    jq \
    # TLS / CA
    ca-certificates \
    # Docker-in-docker is NOT included here; mount the host socket instead
    # Extra tools commonly needed by CI jobs
    build-essential \
    libssl-dev \
    gnupg \
    lsb-release \
    software-properties-common \
    sudo \
    # Node.js LTS (for JS/TS projects like dbwrap)
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# ── Install yarn via corepack ──────────────────────────────────────────────────
RUN npm install -g corepack && corepack enable

# ── Runner user ────────────────────────────────────────────────────────────────
RUN useradd -m -s /bin/bash runner \
    && echo "runner ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/runner \
    && chmod 0440 /etc/sudoers.d/runner

# ── Download & verify the runner package ──────────────────────────────────────
# Resolve arch: prefer the explicit TARGETARCH build-arg; fall back to uname -m.
# uname reports "x86_64" / "aarch64" — map these to Docker's "amd64" / "arm64".
RUN mkdir -p "${RUNNER_HOME}" \
    && ARCH="${TARGETARCH:-$(uname -m)}" \
    && case "${ARCH}" in \
    x86_64)  ARCH=amd64 ;; \
    aarch64) ARCH=arm64 ;; \
    armv7l)  ARCH=arm   ;; \
    esac \
    && curl -fsSL \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${ARCH}-${RUNNER_VERSION}.tar.gz" \
    -o /tmp/runner.tar.gz \
    && tar -xzf /tmp/runner.tar.gz -C "${RUNNER_HOME}" \
    && rm /tmp/runner.tar.gz \
    && chown -R runner:runner "${RUNNER_HOME}"

# ── Install runner dependencies (as root, runner user will execute) ────────────
RUN "${RUNNER_HOME}/bin/installdependencies.sh"

# ── Copy entrypoint ───────────────────────────────────────────────────────────
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER runner
WORKDIR ${RUNNER_HOME}

ENTRYPOINT ["/entrypoint.sh"]
