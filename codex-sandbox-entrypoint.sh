#!/usr/bin/env bash
set -euo pipefail

HOST_CODEX_DIR="${HOST_CODEX_DIR:-/host-codex}"
CONTAINER_CODEX_DIR="${CODEX_HOME:-$HOST_CODEX_DIR}"
SANDBOX_CONFIG_FILE="/etc/codex-sandbox/codex_sandbox.cfg"
export HOST_CODEX_DIR

mkdir -p "$CONTAINER_CODEX_DIR"

if [[ -d "$HOST_CODEX_DIR" && "$CONTAINER_CODEX_DIR" != "$HOST_CODEX_DIR" ]]; then
  for name in auth.json keys skills plugins rules cache vendor_imports installation_id models_cache.json version.json; do
    source="$HOST_CODEX_DIR/$name"
    target="$CONTAINER_CODEX_DIR/$name"

    if [[ -e "$source" && ! -e "$target" && ! -L "$target" ]]; then
      ln -s "$source" "$target"
    fi
  done

  for name in sessions archived_sessions session_index.jsonl history.jsonl; do
    source="$HOST_CODEX_DIR/$name"
    target="$CONTAINER_CODEX_DIR/$name"

    if [[ -e "$source" && ! -e "$target" && ! -L "$target" ]]; then
      ln -s "$source" "$target"
    fi
  done

  if [[ -f "$HOST_CODEX_DIR/config.toml" && ! -e "$CONTAINER_CODEX_DIR/config.toml" ]]; then
    awk '
      function replace_all(value, from, to,   i) {
        if (from == "" || from == to) {
          return value
        }
        while ((i = index(value, from)) > 0) {
          value = substr(value, 1, i - 1) to substr(value, i + length(from))
        }
        return value
      }
      BEGIN {
        host_source = ENVIRON["HOST_CODEX_SOURCE_DIR"]
        host_real = ENVIRON["HOST_CODEX_REAL_DIR"]
        host_mount = ENVIRON["HOST_CODEX_DIR"]
      }
      /^notify =/ { next }
      /^\[mcp_servers\.node_repl\]$/ { skip = 1; next }
      /^\[mcp_servers\.node_repl\.env\]$/ { skip = 1; next }
      /^\[/ { skip = 0 }
      !skip {
        line = replace_all($0, host_real, host_mount)
        line = replace_all(line, host_source, host_mount)
        print line
      }
    ' "$HOST_CODEX_DIR/config.toml" > "$CONTAINER_CODEX_DIR/config.toml"
  fi

fi

CONFIG_FILE="$CONTAINER_CODEX_DIR/config.toml"
touch "$CONFIG_FILE"

# Normalize host-only settings and paths in the effective config. This is an
# in-place atomic update when /host-codex is the configured Codex home.
tmp_config="$(mktemp)"
awk '
  function replace_all(value, from, to,   i) {
    if (from == "" || from == to) {
      return value
    }
    while ((i = index(value, from)) > 0) {
      value = substr(value, 1, i - 1) to substr(value, i + length(from))
    }
    return value
  }
  BEGIN {
    host_source = ENVIRON["HOST_CODEX_SOURCE_DIR"]
    host_real = ENVIRON["HOST_CODEX_REAL_DIR"]
    host_mount = ENVIRON["HOST_CODEX_DIR"]
  }
  /^notify =/ { next }
  /^\[mcp_servers\.node_repl\]$/ { skip = 1; next }
  /^\[mcp_servers\.node_repl\.env\]$/ { skip = 1; next }
  /^\[/ { skip = 0 }
  !skip {
    line = replace_all($0, host_real, host_mount)
    line = replace_all(line, host_source, host_mount)
    print line
  }
' "$CONFIG_FILE" > "$tmp_config"
mv "$tmp_config" "$CONFIG_FILE"

tmp_config="$(mktemp)"
awk '
    BEGIN { replaced = 0; inserted = 0; in_top_level = 1 }
    /^\[/ {
      if (!replaced && !inserted) {
        print "sandbox_mode = \"danger-full-access\""
        print ""
        inserted = 1
      }
      in_top_level = 0
      print
      next
    }
    in_top_level && /^sandbox_mode[[:space:]]*=/ {
      if (!replaced) {
        print "sandbox_mode = \"danger-full-access\""
        replaced = 1
      }
      next
    }
    { print }
    END {
      if (!replaced && !inserted) {
        print ""
        print "sandbox_mode = \"danger-full-access\""
      }
    }
  ' "$CONFIG_FILE" > "$tmp_config"
mv "$tmp_config" "$CONFIG_FILE"

if [[ -f "$SANDBOX_CONFIG_FILE" ]]; then
  tmp_config="$(mktemp)"
  awk '
      /^\[mcp_servers\./ { skip = 1; next }
      /^\[/ { skip = 0 }
      !skip { print }
  ' "$CONFIG_FILE" > "$tmp_config"

  host_sdvi_dir="${HOST_SDVI_SOURCE_DIR:-$HOME/.sdvi}"
  host_aws_dir="${HOST_AWS_SOURCE_DIR:-$HOME/.aws}"
  host_sdvi_dir="${host_sdvi_dir//\\/\\\\}"
  host_sdvi_dir="${host_sdvi_dir//&/\\&}"
  host_sdvi_dir="${host_sdvi_dir//|/\\|}"
  host_aws_dir="${host_aws_dir//\\/\\\\}"
  host_aws_dir="${host_aws_dir//&/\\&}"
  host_aws_dir="${host_aws_dir//|/\\|}"

  printf '\n' >> "$tmp_config"
  awk '
      /^\[mcp_servers\./ { in_mcp = 1 }
      /^\[/ && !/^\[mcp_servers\./ { in_mcp = 0 }
      in_mcp { print }
  ' "$SANDBOX_CONFIG_FILE" | sed \
      -e "s|@HOST_SDVI_DIR@|$host_sdvi_dir|g" \
      -e "s|@HOST_AWS_DIR@|$host_aws_dir|g" \
      >> "$tmp_config"
  mv "$tmp_config" "$CONFIG_FILE"
fi

if [[ "$CONTAINER_CODEX_DIR" != "/root/.codex" && -d /root && -w /root && ! -e /root/.codex && ! -L /root/.codex ]]; then
  ln -s "$CONTAINER_CODEX_DIR" /root/.codex
fi

exec "$@"
