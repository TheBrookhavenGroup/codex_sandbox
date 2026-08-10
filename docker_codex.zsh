#!/usr/bin/env zsh

_docker_codex_main() {
emulate -L zsh
setopt PIPE_FAIL

HOST_DIR="$(pwd -P)"
SANDBOX_CONFIG_FILE="$HOME/.config/codex_sandbox.cfg"
LAUNCHER_DIR="${${(%):-%x}:A:h}"

if [[ ! -f "$SANDBOX_CONFIG_FILE" ]]; then
  echo "❌ Codex sandbox configuration was not found:"
  echo "  $SANDBOX_CONFIG_FILE"
  echo
  echo "Create it from the supplied template:"
  echo "  mkdir -p $HOME/.config"
  echo "  cp $LAUNCHER_DIR/codex_sandbox.cfg.example $SANDBOX_CONFIG_FILE"
  return 1 2>/dev/null || exit 1
fi

IMAGE=""
HOST_DEV_DIR=""
HOST_AEN_DIR=""
HOST_CODEX_DIR=""
HOST_SDVI_DIR=""
HOST_AWS_DIR=""
HOST_GITCONFIG_FILE=""
HOST_GH_CONFIG_DIR=""
HOST_SSH_DIR=""
HOST_DOTFILES_DIR=""
DOCKER_CODEX_HOME=""
POSTGRES_HOST=""
POSTGRES_PORT=""
DOCKER_SOCKET=""

while IFS=$'\t' read -r config_key config_value; do
  [[ "$config_value" == "~/"* ]] && config_value="$HOME/${config_value#\~/}"
  case "$config_key" in
    image) IMAGE="$config_value" ;;
    host_dev_dir) HOST_DEV_DIR="$config_value" ;;
    host_aen_dir) HOST_AEN_DIR="$config_value" ;;
    host_codex_dir) HOST_CODEX_DIR="$config_value" ;;
    host_sdvi_dir) HOST_SDVI_DIR="$config_value" ;;
    host_aws_dir) HOST_AWS_DIR="$config_value" ;;
    host_gitconfig_file) HOST_GITCONFIG_FILE="$config_value" ;;
    host_gh_config_dir) HOST_GH_CONFIG_DIR="$config_value" ;;
    host_ssh_dir) HOST_SSH_DIR="$config_value" ;;
    host_dotfiles_dir) HOST_DOTFILES_DIR="$config_value" ;;
    docker_codex_home) DOCKER_CODEX_HOME="$config_value" ;;
    docker_socket) DOCKER_SOCKET="$config_value" ;;
    postgres_host) POSTGRES_HOST="$config_value" ;;
    postgres_port) POSTGRES_PORT="$config_value" ;;
  esac
done < <(
  awk '
    /^\[sandbox\][[:space:]]*$/ { in_sandbox = 1; next }
    /^\[/ { in_sandbox = 0 }
    in_sandbox && /^[[:space:]]*[a-z_]+[[:space:]]*=/ {
      key = $0
      sub(/[[:space:]]*=.*/, "", key)
      sub(/^[[:space:]]*/, "", key)
      value = $0
      sub(/^[^=]*=[[:space:]]*/, "", value)
      sub(/[[:space:]]*#[^\"]*$/, "", value)
      sub(/^[\"]/, "", value)
      sub(/[\"][[:space:]]*$/, "", value)
      print key "\t" value
    }
  ' "$SANDBOX_CONFIG_FILE"
)

missing_settings=()
[[ -z "$IMAGE" ]] && missing_settings+=(image)
[[ -z "$HOST_DEV_DIR" ]] && missing_settings+=(host_dev_dir)
[[ -z "$HOST_AEN_DIR" ]] && missing_settings+=(host_aen_dir)
[[ -z "$HOST_CODEX_DIR" ]] && missing_settings+=(host_codex_dir)
[[ -z "$HOST_SDVI_DIR" ]] && missing_settings+=(host_sdvi_dir)
[[ -z "$HOST_AWS_DIR" ]] && missing_settings+=(host_aws_dir)
[[ -z "$HOST_GITCONFIG_FILE" ]] && missing_settings+=(host_gitconfig_file)
[[ -z "$HOST_GH_CONFIG_DIR" ]] && missing_settings+=(host_gh_config_dir)
[[ -z "$HOST_SSH_DIR" ]] && missing_settings+=(host_ssh_dir)
[[ -z "$HOST_DOTFILES_DIR" ]] && missing_settings+=(host_dotfiles_dir)
[[ -z "$DOCKER_CODEX_HOME" ]] && missing_settings+=(docker_codex_home)
[[ -z "$DOCKER_SOCKET" ]] && missing_settings+=(docker_socket)
[[ -z "$POSTGRES_HOST" ]] && missing_settings+=(postgres_host)
[[ -z "$POSTGRES_PORT" ]] && missing_settings+=(postgres_port)

if (( ${#missing_settings[@]} > 0 )); then
  echo "❌ Missing required settings in $SANDBOX_CONFIG_FILE:"
  printf '  %s\n' "${missing_settings[@]}"
  return 1 2>/dev/null || exit 1
fi

# Preserve the image's default interactive shell when invoked with no
# arguments. When the launcher receives arguments, forward them verbatim to
# the Codex CLI so subcommands, flags, and prompts behave like the native CLI.
CONTAINER_COMMAND=()
if [[ "${1:-}" == "delete-picker" ]]; then
  CONTAINER_COMMAND=(codex-delete-picker "${@:2}")
elif [[ "${1:-}" == "delete" && $# -eq 1 ]]; then
  CONTAINER_COMMAND=(codex-delete-picker)
elif (( $# > 0 )); then
  CONTAINER_COMMAND=(codex "$@")
fi

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

DOCKER_VOLUMES+=(
  -v "$SANDBOX_CONFIG_FILE:/etc/codex-sandbox/codex_sandbox.cfg:ro"
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

POSTGRES_ENV=(
  -e PGHOST="$POSTGRES_HOST"
  -e PGPORT="$POSTGRES_PORT"
  -e POSTGRES_HOST="$POSTGRES_HOST"
  -e POSTGRES_PORT="$POSTGRES_PORT"
)

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
if [[ "$DOCKER_CODEX_HOME" == "/host-codex" ]]; then
  echo "  $HOST_CODEX_DIR"
elif [[ "$DOCKER_CODEX_HOME" == "/host-codex/"* ]]; then
  echo "  $HOST_CODEX_DIR/${DOCKER_CODEX_HOME#/host-codex/}"
else
  echo "  $DOCKER_CODEX_HOME (inside the container)"
fi
echo "Sandbox configuration will be loaded from:"
echo "  $SANDBOX_CONFIG_FILE"
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
    "$IMAGE" \
    "${CONTAINER_COMMAND[@]}"
fi
}

# Keep launcher options local to the function. This file is normally sourced
# by an alias, so changing options at file scope would otherwise leak into the
# interactive shell.
_docker_codex_main "$@"
_docker_codex_status=$?
unfunction _docker_codex_main
return "$_docker_codex_status" 2>/dev/null || exit "$_docker_codex_status"
