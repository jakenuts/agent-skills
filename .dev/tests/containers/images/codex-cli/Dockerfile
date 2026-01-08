FROM node:20-bookworm

ARG CODEX_VERSION=latest
ARG DOTNET_CHANNEL=10.0

RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  git \
  jq \
  bash \
  && rm -rf /var/lib/apt/lists/*

# Install .NET SDK for tool installation (SolarWinds logs CLI)
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
  && bash /tmp/dotnet-install.sh --channel "${DOTNET_CHANNEL}" --install-dir /usr/share/dotnet \
  && ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet \
  && rm /tmp/dotnet-install.sh

RUN npm install -g @openai/codex@${CODEX_VERSION}

ENV PATH="/root/.dotnet/tools:${PATH}"

WORKDIR /opt/agent-skills
