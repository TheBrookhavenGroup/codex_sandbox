#!/usr/bin/env zsh

set -euo pipefail

IMAGE="codex-sandbox"
HOST_DIR="$(pwd -P)"
HOST_DEV_DIR="${CODEX_HOST_DEV_DIR:-$HOME/dev}"
HOST_AEN_DIR="${CODEX_HOST_AEN_DIR:-$HOME/aen}"
HOST_CODEX_DIR="${CODEX_HOST_DIR:-$HOME/.codex}"
HOST_SDVI_DIR="${CODEX_HOST_SDVI_DIR:-$HOME/.sdvi}"
HOST_AWS_DIR="${CODEX_HOST_AWS_DIR:-$HOME/.aws}"
HOST_GITCONFIG_FILE="${CODEX_HOST_GITCONFIG_FILE:-$HOME/.gitconfig}"
HOST_GH_CONFIG_DIR="${CODEX_HOST_GH_CONFIG_DIR:-$HOME/.config/gh}"
HOST_SSH_DIR="${CODEX_HOST_SSH_DIR:-$HOME/.ssh}"
HOST_DOTFILES_DIR="${CODEX_HOST_DOTFILES_DIR:-$HOME/dotfiles}"
DOCKER_CODEX_HOME="${CODEX_DOCKER_HOME:-/host-codex}"
mkdir -p "$HOST_CODEX_DIR"
mkdir -p "$HOST_SDVI_DIR"
mkdir -p "$HOST_AWS_DIR"
mkdir -p "$HOST_GH_CONFIG_DIR"
HOST_CODEX_REAL_DIR="$(cd "$HOST_CODEX_DIR" && pwd -P)"

if [[ -d "$HOST_DEV_DIR" ]]; then
  HOST_DEV_REAL_DIR="$(cd "$HOST_DEV_DIR" && pwd -P)"
else
  HOST_DEV_REAL_DIR=""
fi

if [[ -d "$HOST_AEN_DIR" ]]; then
  HOST_AEN_REAL_DIR="$(cd "$HOST_AEN_DIR" && pwd -P)"
else
  HOST_AEN_REAL_DIR=""
fi

if [[ -z "$HOST_DEV_REAL_DIR" && -z "$HOST_AEN_REAL_DIR" ]]; then
  echo "❌ Neither host dev nor AEN directory exists:"
  echo "  $HOST_DEV_DIR"
  echo "  $HOST_AEN_DIR"
  return 1 2>/dev/null || exit 1
fi

DOCKER_VOLUMES=(
  -v "$HOST_CODEX_DIR:/host-codex:rw"
  -v "$HOST_SDVI_DIR:/root/.sdvi:rw"
  -v "$HOST_AWS_DIR:/root/.aws:rw"
  -v "$HOST_GH_CONFIG_DIR:/root/.config/gh:rw"
)

if [[ -n "$HOST_DEV_REAL_DIR" ]]; then
  DOCKER_VOLUMES+=(
    -v "$HOST_DEV_DIR:/workspace/dev:rw"
    -v "$HOST_DEV_DIR:/root/dev:rw"
  )
fi

if [[ -n "$HOST_AEN_REAL_DIR" ]]; then
  DOCKER_VOLUMES+=(
    -v "$HOST_AEN_DIR:/root/dev/aen:rw"
  )
fi

if [[ -f "$HOST_GITCONFIG_FILE" ]]; then
  DOCKER_VOLUMES+=(
    -v "$HOST_GITCONFIG_FILE:/root/.gitconfig:rw"
  )
fi

if [[ -d "$HOST_SSH_DIR" ]]; then
  DOCKER_VOLUMES+=(
    -v "$HOST_SSH_DIR:/root/.ssh:rw"
  )
fi

if [[ -d "$HOST_DOTFILES_DIR" ]]; then
  DOCKER_VOLUMES+=(
    -v "$HOST_DOTFILES_DIR:/root/dotfiles:ro"
  )
fi

DOCKER_NETWORK_ARGS=(
  --add-host host.docker.internal:host-gateway
)

POSTGRES_HOST="${CODEX_POSTGRES_HOST:-host.docker.internal}"
POSTGRES_PORT="${CODEX_POSTGRES_PORT:-5432}"
POSTGRES_ENV=(
  -e PGHOST="$POSTGRES_HOST"
  -e PGPORT="$POSTGRES_PORT"
  -e POSTGRES_HOST="$POSTGRES_HOST"
  -e POSTGRES_PORT="$POSTGRES_PORT"
)

DOCKER_SOCKET="${CODEX_DOCKER_SOCKET:-$HOME/.docker/run/docker.sock}"
if [[ -S "$DOCKER_SOCKET" ]]; then
  DOCKER_VOLUMES+=(
    -v "$DOCKER_SOCKET:/var/run/docker.sock:rw"
  )
fi

if [[ -n "$HOST_AEN_REAL_DIR" && "$HOST_DIR" == "$HOST_AEN_REAL_DIR" ]]; then
  CONTAINER_WORKDIR="/root/dev/aen"
elif [[ -n "$HOST_AEN_REAL_DIR" && "$HOST_DIR" == "$HOST_AEN_REAL_DIR"/* ]]; then
  CONTAINER_WORKDIR="/root/dev/aen/${HOST_DIR#$HOST_AEN_REAL_DIR/}"
elif [[ -n "$HOST_DEV_REAL_DIR" && "$HOST_DIR" == "$HOST_DEV_REAL_DIR" ]]; then
  CONTAINER_WORKDIR="/root/dev"
elif [[ -n "$HOST_DEV_REAL_DIR" && "$HOST_DIR" == "$HOST_DEV_REAL_DIR"/* ]]; then
  CONTAINER_WORKDIR="/root/dev/${HOST_DIR#$HOST_DEV_REAL_DIR/}"
else
  CONTAINER_WORKDIR="/root/dev"
fi

echo
echo "🐳 Codex Docker Sandbox"
echo "──────────────────────"
echo "This will start Codex with access to:"
if [[ -n "$HOST_DEV_REAL_DIR" ]]; then
  echo "  $HOST_DEV_DIR -> /workspace/dev"
  echo "  $HOST_DEV_DIR -> /root/dev"
else
  echo "Dev directory was not found at:"
  echo "  $HOST_DEV_DIR"
fi
if [[ -n "$HOST_AEN_REAL_DIR" ]]; then
  echo "  $HOST_AEN_DIR -> /root/dev/aen"
else
  echo "AEN directory was not found at:"
  echo "  $HOST_AEN_DIR"
fi
echo "Working directory in container:"
echo "  $CONTAINER_WORKDIR"
echo "Codex config/auth will be mounted from:"
echo "  $HOST_CODEX_DIR"
echo "SDVI config will be mounted from:"
echo "  $HOST_SDVI_DIR -> /root/.sdvi"
echo "AWS config/credentials will be mounted from:"
echo "  $HOST_AWS_DIR -> /root/.aws"
echo "GitHub CLI config will be mounted from:"
echo "  $HOST_GH_CONFIG_DIR -> /root/.config/gh"
if [[ -f "$HOST_GITCONFIG_FILE" ]]; then
  echo "Git config will be mounted from:"
  echo "  $HOST_GITCONFIG_FILE -> /root/.gitconfig"
else
  echo "Git config was not found at:"
  echo "  $HOST_GITCONFIG_FILE"
fi
if [[ -d "$HOST_SSH_DIR" ]]; then
  echo "SSH config/keys will be mounted from:"
  echo "  $HOST_SSH_DIR -> /root/.ssh"
else
  echo "SSH directory was not found at:"
  echo "  $HOST_SSH_DIR"
fi
if [[ -d "$HOST_DOTFILES_DIR" ]]; then
  echo "Dotfiles will be mounted from:"
  echo "  $HOST_DOTFILES_DIR -> /root/dotfiles"
else
  echo "Dotfiles directory was not found at:"
  echo "  $HOST_DOTFILES_DIR"
fi
echo "Docker Codex home will persist at:"
echo "  $HOST_CODEX_DIR"
echo "Host Postgres will be reachable in the container at:"
echo "  $POSTGRES_HOST:$POSTGRES_PORT"
if [[ -S "$DOCKER_SOCKET" ]]; then
  echo "Docker socket will be mounted from:"
  echo "  $DOCKER_SOCKET -> /var/run/docker.sock"
else
  echo "Docker socket was not found at:"
  echo "  $DOCKER_SOCKET"
fi
echo

if ! docker info >/dev/null 2>&1; then
  echo "❌ Docker is not running."
else
  echo
  echo "Starting container..."
  echo

  docker run -it --rm \
    -e CODEX_HOME="$DOCKER_CODEX_HOME" \
    -e HOST_CODEX_SOURCE_DIR="$HOST_CODEX_DIR" \
    -e HOST_CODEX_REAL_DIR="$HOST_CODEX_REAL_DIR" \
    -e HOST_SDVI_SOURCE_DIR="$HOST_SDVI_DIR" \
    -e HOST_AWS_SOURCE_DIR="$HOST_AWS_DIR" \
    "${POSTGRES_ENV[@]}" \
    "${DOCKER_NETWORK_ARGS[@]}" \
    "${DOCKER_VOLUMES[@]}" \
    -w "$CONTAINER_WORKDIR" \
    "$IMAGE"
fi
