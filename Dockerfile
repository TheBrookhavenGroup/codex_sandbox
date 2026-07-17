FROM postgres:16

ENV DEBIAN_FRONTEND=noninteractive

# ------------------------------------------------------------
# Base tools
# ------------------------------------------------------------
RUN apt-get update && apt-get install -y \
    git \
    git-lfs \
    curl \
    ca-certificates \
    unzip \
    python3 \
    python3-pip \
    fzf \
    pre-commit \
    ripgrep \
    less \
    vim \
    bash \
    gnupg \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# Install GitHub CLI
# ------------------------------------------------------------
RUN set -eux; \
    mkdir -p -m 755 /etc/apt/keyrings; \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg; \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list; \
    apt-get update; \
    apt-get install -y gh; \
    rm -rf /var/lib/apt/lists/*; \
    gh --version

RUN cat <<'EOF' >/usr/local/bin/git-credential-osxkeychain
#!/usr/bin/env bash
set -euo pipefail

if command -v gh >/dev/null 2>&1; then
  exec gh auth git-credential "$@"
fi

echo "git-credential-osxkeychain is not available in Linux, and gh is not installed" >&2
exit 1
EOF
RUN chmod +x /usr/local/bin/git-credential-osxkeychain

# ------------------------------------------------------------
# Install AWS CLI v2
# ------------------------------------------------------------
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
        amd64) aws_arch="x86_64" ;; \
        arm64) aws_arch="aarch64" ;; \
        *) echo "Unsupported architecture for AWS CLI: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip" -o /tmp/awscliv2.zip; \
    unzip -q /tmp/awscliv2.zip -d /tmp; \
    /tmp/aws/install; \
    rm -rf /tmp/aws /tmp/awscliv2.zip; \
    aws --version

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
COPY codex-delete-picker /usr/local/bin/codex-delete-picker
RUN chmod +x /usr/local/bin/codex-sandbox-entrypoint /usr/local/bin/codex-delete-picker
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
