FROM postgres:16

ENV DEBIAN_FRONTEND=noninteractive

# ------------------------------------------------------------
# Base tools
# ------------------------------------------------------------
RUN apt-get update && apt-get install -y \
    git \
    curl \
    ca-certificates \
    python3 \
    python3-pip \
    ripgrep \
    less \
    vim \
    bash \
    gnupg \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# Install uv (optional, does NOT replace pip)
# ------------------------------------------------------------
RUN set -eux; \
    curl -LsSf https://astral.sh/uv/install.sh | sh; \
    ln -s /root/.local/bin/uv /usr/local/bin/uv; \
    ln -s /root/.local/bin/uvx /usr/local/bin/uvx; \
    uv --version

# ------------------------------------------------------------
# Install Node.js 20 LTS
# ------------------------------------------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && node --version \
    && npm --version

# ------------------------------------------------------------
# Install Codex CLI
# ------------------------------------------------------------
RUN npm install -g @openai/codex

# ------------------------------------------------------------
# Prepare Codex home from the host-mounted Mac config
# ------------------------------------------------------------
COPY codex-sandbox-entrypoint.sh /usr/local/bin/codex-sandbox-entrypoint
RUN chmod +x /usr/local/bin/codex-sandbox-entrypoint
COPY .bashrc /root/.bashrc

# ------------------------------------------------------------
# Codex startup prompt (login + interactive shell)
# ------------------------------------------------------------
RUN cat <<'EOF' >/etc/profile.d/codex.sh
if [[ $- == *i* ]] && [[ -z "$CODEX_PROMPTED" ]] && command -v codex >/dev/null 2>&1; then
  export CODEX_PROMPTED=1
  read -p "Start Codex CLI? [Y/n] " answer
  case "$answer" in
    ""|y|Y|yes|YES)
      codex resume --all
      ;;
  esac
fi
EOF

# ------------------------------------------------------------
# Workspace
# ------------------------------------------------------------
WORKDIR /workspace

# ------------------------------------------------------------
# Start login + interactive shell
# ------------------------------------------------------------
ENTRYPOINT ["/usr/local/bin/codex-sandbox-entrypoint"]
CMD ["/bin/bash", "-il"]
