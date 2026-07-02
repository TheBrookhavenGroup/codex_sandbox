#!/usr/bin/env bash
set -euo pipefail

HOST_CODEX_DIR="${HOST_CODEX_DIR:-/host-codex}"
CONTAINER_CODEX_DIR="${CODEX_HOME:-$HOST_CODEX_DIR/docker-home}"
export HOST_CODEX_DIR

mkdir -p "$CONTAINER_CODEX_DIR"

if [[ -d "$HOST_CODEX_DIR" ]]; then
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

if [[ -f "$CONFIG_FILE" ]]; then
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
fi

if [[ -f "$CONFIG_FILE" ]] && ! grep -q '^\[mcp_servers\.rally_qa\]$' "$CONFIG_FILE"; then
  cat >> "$CONFIG_FILE" <<'EOF'

[mcp_servers.rally_qa]
command = "docker"
args = ["run", "--rm", "-i", "rally-qa-mcp"]
startup_timeout_sec = 120
EOF
fi

if [[ "$CONTAINER_CODEX_DIR" != "/root/.codex" && -d /root && -w /root && ! -e /root/.codex && ! -L /root/.codex ]]; then
  ln -s "$CONTAINER_CODEX_DIR" /root/.codex
fi

exec "$@"
