#!/usr/bin/env zsh

set -euo pipefail

IMAGE="codex-sandbox"
HOST_DIR="$(pwd -P)"
HOST_DEV_DIR="${CODEX_HOST_DEV_DIR:-$HOME/dev}"
HOST_CODEX_DIR="${CODEX_HOST_DIR:-$HOME/.codex}"
HOST_SDVI_DIR="${CODEX_HOST_SDVI_DIR:-$HOME/.sdvi}"
HOST_AWS_DIR="${CODEX_HOST_AWS_DIR:-$HOME/.aws}"
DOCKER_CODEX_HOME="${CODEX_DOCKER_HOME:-/host-codex}"
mkdir -p "$HOST_CODEX_DIR"
mkdir -p "$HOST_SDVI_DIR"
mkdir -p "$HOST_AWS_DIR"
HOST_CODEX_REAL_DIR="$(cd "$HOST_CODEX_DIR" && pwd -P)"

if [[ ! -d "$HOST_DEV_DIR" ]]; then
  echo "❌ Host dev directory does not exist: $HOST_DEV_DIR"
  return 1 2>/dev/null || exit 1
fi

HOST_DEV_REAL_DIR="$(cd "$HOST_DEV_DIR" && pwd -P)"

DOCKER_VOLUMES=(
  -v "$HOST_CODEX_DIR:/host-codex:rw"
  -v "$HOST_SDVI_DIR:/root/.sdvi:rw"
  -v "$HOST_AWS_DIR:/root/.aws:rw"
  -v "$HOST_DEV_DIR:/workspace/dev:rw"
)

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

if [[ "$HOST_DIR" == "$HOST_DEV_REAL_DIR" ]]; then
  CONTAINER_WORKDIR="/workspace/dev"
elif [[ "$HOST_DIR" == "$HOST_DEV_REAL_DIR"/* ]]; then
  CONTAINER_WORKDIR="/workspace/dev/${HOST_DIR#$HOST_DEV_REAL_DIR/}"
else
  CONTAINER_WORKDIR="/workspace/dev"
fi

echo
echo "🐳 Codex Docker Sandbox"
echo "──────────────────────"
echo "This will start Codex with access to:"
echo "  $HOST_DEV_DIR -> /workspace/dev"
echo "Working directory in container:"
echo "  $CONTAINER_WORKDIR"
echo "Codex config/auth will be mounted from:"
echo "  $HOST_CODEX_DIR"
echo "SDVI config will be mounted from:"
echo "  $HOST_SDVI_DIR -> /root/.sdvi"
echo "AWS config/credentials will be mounted from:"
echo "  $HOST_AWS_DIR -> /root/.aws"
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
