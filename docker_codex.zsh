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
HOST_DIRS=()
PORT_FORWARDS=()
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

# Parse TOML before reading settings so invalid lists fail before Docker starts.
local config_settings
if ! config_settings="$(python3 - "$SANDBOX_CONFIG_FILE" <<'PYCONFIG'
import sys
try:
    import tomllib
except ImportError:
    sys.exit("The sandbox launcher requires Python 3.11 or newer (tomllib).")

try:
    with open(sys.argv[1], "rb") as config_file:
        config = tomllib.load(config_file)
        sandbox = config["sandbox"]
    if not isinstance(sandbox, dict):
        raise ValueError("sandbox must be a TOML table")
    for key, value in sandbox.items():
        if key == "host_dirs":
            if not isinstance(value, list) or any(not isinstance(p, str) or not p for p in value):
                raise ValueError("host_dirs must be a list of nonempty path strings")
            values = value
        else:
            values = [str(value)]
        for item in values:
            if any(c in item for c in "\t\r\n\0"):
                raise ValueError(f"{key} contains unsupported control characters")
            print(f"{key}\t{item}")
    port_forward = config.get("port_forward", {})
    if not isinstance(port_forward, dict):
        raise ValueError("port_forward must be a TOML table")
    mappings = port_forward.get("ports", []) if "port_forward" in config else ["0:8000"]
    if not isinstance(mappings, list):
        raise ValueError("port_forward.ports must be a list of host:container strings")
    host_ports = set()
    for mapping in mappings:
        if not isinstance(mapping, str):
            raise ValueError("port_forward.ports must contain host:container strings")
        ports = mapping.split(":")
        if len(ports) != 2 or any(
            not p.isascii() or not p.isdecimal() or not minimum <= int(p) <= 65535
            for p, minimum in zip(ports, (0, 1))
        ):
            raise ValueError(f"invalid port mapping {mapping!r}: use host:container (host 0 selects an available port)")
        host_port, container_port = map(int, ports)
        if host_port != 0 and host_port in host_ports:
            raise ValueError(f"duplicate host port in port_forward.ports: {host_port}")
        host_ports.add(host_port)
        print(f"port_forward\t{host_port}:{container_port}")
except (OSError, ValueError, KeyError, TypeError) as exc:
    sys.exit(f"Invalid sandbox configuration: {exc}")
PYCONFIG
)"; then
  return 1
fi

while IFS=$'\t' read -r config_key config_value; do
  [[ "$config_value" == "~/"* ]] && config_value="$HOME/${config_value#\~/}"
  case "$config_key" in
    image) IMAGE="$config_value" ;;
    host_dev_dir) HOST_DEV_DIR="$config_value" ;;
    host_dirs) HOST_DIRS+=("$config_value") ;;
    port_forward) PORT_FORWARDS+=("$config_value") ;;
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
done <<< "$config_settings"

missing_settings=()
[[ -z "$IMAGE" ]] && missing_settings+=(image)
[[ -z "$HOST_DEV_DIR" ]] && missing_settings+=(host_dev_dir)
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

local host_mount_dir host_mount_real_dir
local -a host_mount_paths
host_mount_paths=()
for host_mount_dir in "${HOST_DIRS[@]}"; do
  if [[ "$host_mount_dir" != /* || ! -d "$host_mount_dir" || "$host_mount_dir" == *:* ]]; then
    echo "❌ Each host_dirs entry must be an existing absolute directory without a colon:"
    echo "  $host_mount_dir"
    return 1
  fi
  host_mount_real_dir="$(cd "$host_mount_dir" && pwd -P)" || return 1
  if [[ "$host_mount_real_dir" == *:* ]]; then
    echo "❌ host_dirs resolves to a path containing a colon: $host_mount_real_dir"
    return 1
  fi
  while [[ "$host_mount_dir" != / && "$host_mount_dir" == */ ]]; do
    host_mount_dir="${host_mount_dir%/}"
  done
  host_mount_paths+=("$host_mount_dir" "$host_mount_real_dir")
done
# Mount both configured and physical paths, without duplicate destinations.
host_mount_paths=("${(@u)host_mount_paths}")

if [[ -z "$HOST_DEV_REAL_DIR" ]]; then
  echo "❌ Host dev directory does not exist:"
  echo "  $HOST_DEV_DIR"
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

# Keep host paths available so absolute symlinks under ~/dev still resolve.
for host_mount_dir in "${host_mount_paths[@]}"; do
  DOCKER_VOLUMES+=(-v "${host_mount_dir}:${host_mount_dir}:rw")
done

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
    -v "$HOST_DOTFILES_DIR:/root/dotfiles:rw"
  )
fi

DOCKER_NETWORK_ARGS=(
  --add-host host.docker.internal:host-gateway
)
local port_mapping
for port_mapping in "${PORT_FORWARDS[@]}"; do
  DOCKER_NETWORK_ARGS+=(-p "127.0.0.1:$port_mapping")
done

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

if [[ -n "$HOST_DEV_REAL_DIR" && "$HOST_DIR" == "$HOST_DEV_REAL_DIR" ]]; then
  CONTAINER_WORKDIR="/root/dev"
elif [[ -n "$HOST_DEV_REAL_DIR" && "$HOST_DIR" == "$HOST_DEV_REAL_DIR"/* ]]; then
  CONTAINER_WORKDIR="/root/dev/${HOST_DIR#$HOST_DEV_REAL_DIR/}"
else
  CONTAINER_WORKDIR="/root/dev"
  for host_mount_dir in "${host_mount_paths[@]}"; do
    if [[ "$HOST_DIR" == "$host_mount_dir" || "$HOST_DIR" == "$host_mount_dir"/* ]]; then
      CONTAINER_WORKDIR="$HOST_DIR"
      break
    fi
  done
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
for host_mount_dir in "${host_mount_paths[@]}"; do
  echo "  $host_mount_dir -> $host_mount_dir"
done
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
if (( ${#PORT_FORWARDS[@]} > 0 )); then
  echo "Port forwards (desktop localhost -> container):"
  for port_mapping in "${PORT_FORWARDS[@]}"; do
    if [[ "${port_mapping%%:*}" == 0 ]]; then
      echo "  Available desktop port -> ${port_mapping#*:} (TCP)"
    else
      echo "  127.0.0.1:${port_mapping%%:*} -> ${port_mapping#*:} (TCP)"
    fi
  done
fi
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

  local container_id container_exit_status
  container_id="$(docker create -it \
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
    "${CONTAINER_COMMAND[@]}")" || return $?
  # Start before inspecting ports: Docker allocates ephemeral host ports at startup.
  # Always remove this session's container, including when attach is interrupted.
  {
    docker start "$container_id" >/dev/null || return $?
    if (( ${#PORT_FORWARDS[@]} > 0 )); then
      echo "Desktop addresses (container port -> desktop):"
      docker port "$container_id"
      echo
    fi
    docker attach "$container_id"
    container_exit_status="$(docker inspect --format '{{.State.ExitCode}}' "$container_id")" || return $?
    return "$container_exit_status"
  } always {
    docker rm -f "$container_id" >/dev/null
  }
fi
}

# Keep launcher options local to the function. This file is normally sourced
# by an alias, so changing options at file scope would otherwise leak into the
# interactive shell.
_docker_codex_main "$@"
_docker_codex_status=$?
unfunction _docker_codex_main
return "$_docker_codex_status" 2>/dev/null || exit "$_docker_codex_status"
