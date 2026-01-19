#!/usr/bin/env zsh

read "REPLY?Sandbox/codex? [y/N] "

if [[ "$REPLY" == [yY] || "$REPLY" == [yY][eE][sS] ]]; then
  set -euo pipefail

  IMAGE="codex-sandbox"
  HOST_DIR="$(pwd)"
  CODEX_VOLUME="codex-auth"

  echo
  echo "🐳 Codex Docker Sandbox"
  echo "──────────────────────"
  echo "This will start Codex with access to:"
  echo "  $HOST_DIR"
  echo

  if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker is not running."
  else
    if ! docker volume inspect "$CODEX_VOLUME" >/dev/null 2>&1; then
      echo "🔐 Creating Docker volume '$CODEX_VOLUME' for Codex auth..."
      docker volume create "$CODEX_VOLUME" >/dev/null
    fi

    echo
    echo "Starting container..."
    echo

    docker run -it --rm \
      -v "$CODEX_VOLUME:/root/.codex" \
      -v "$HOST_DIR:/workspace:rw" \
      -w /workspace \
      "codex-sandbox"
  fi
fi
