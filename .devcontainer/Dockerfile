FROM mcr.microsoft.com/devcontainers/python:3.15-bookworm

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root

COPY config/mcp-runtime-versions.env /tmp/rldyour-mcp-runtime-versions.env

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      gnupg \
      jq \
      ripgrep \
      shellcheck \
      xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN set -a \
    && source /tmp/rldyour-mcp-runtime-versions.env \
    && set +a \
    && curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR_VERSION}.x" | bash - \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub \
      | gpg --dearmor -o /etc/apt/keyrings/dart.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/dart.gpg arch=amd64] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main" \
      > /etc/apt/sources.list.d/dart_stable.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends dart \
    && rm -rf /var/lib/apt/lists/*

RUN set -a \
    && source /tmp/rldyour-mcp-runtime-versions.env \
    && set +a \
    && python3 -m pip install --no-cache-dir uv \
    && npm install -g "bun@${BUN_VERSION}"

RUN set -a \
    && source /tmp/rldyour-mcp-runtime-versions.env \
    && set +a \
    && npm install -g "@openai/codex@${CODEX_CLI_VERSION}" \
    && rm /tmp/rldyour-mcp-runtime-versions.env

USER vscode

RUN mkdir -p /home/vscode/.codex
