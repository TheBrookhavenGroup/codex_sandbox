# Sandbox Codex

Author: Marc Schwarzschild

This repo builds a Docker image for running OpenAI Codex with a narrower view of the host
filesystem.  The container gets the tools Codex needs, a Bash startup file from this repo, and
controlled mounts for source code and Codex state.

## How It Works

`Dockerfile` builds the `codex-sandbox` image.  It installs Codex, common development tools, the
Docker CLI, and copies this repo's `.bashrc` to `/root/.bashrc` in the image.

`docker_codex.zsh` is the host-side launcher.  It mounts:

```text
~/dev             -> /workspace/dev
~/.codex          -> /host-codex and CODEX_HOME inside Docker
~/.docker/run/docker.sock -> /var/run/docker.sock, when present
```

When started from inside `~/dev`, the container working directory is set to the matching path under
`/workspace/dev`.  If started outside `~/dev`, the container starts in `/workspace/dev`.

`codex-sandbox-entrypoint.sh` runs inside the container before Bash starts.  It prepares the Docker
Codex home and points `/root/.codex` at it.  By default, Docker Codex uses the host `~/.codex`
directly, so config, auth, keys, skills, plugins, rules, caches, sessions, and history all live in
one persistent Codex home.

If you opt into a separate Docker Codex home with `CODEX_DOCKER_HOME=/host-codex/docker-home`, the
entrypoint seeds a Linux-safe config, strips macOS-only `node_repl` MCP settings, links shared state
from the host `~/.codex`, and ensures the Docker Codex config contains a `rally_qa` MCP server that
runs:

```bash
docker run --rm -i rally-qa-mcp
```

## Shell Setup

Your `~/.zshrc` defines these helpers:

```zsh
run_codex() {
    source "$DEVPATH/tbg/codex_sandbox/docker_codex.zsh"
}

alias codex=run_codex

build_codex() {
    cd $DEVPATH/tbg/codex_sandbox
    echo `pwd`
    docker build --no-cache -t codex-sandbox .
}

alias update_codex=build_codex
```

With that setup:

```zsh
codex
```

starts the Docker sandbox, and:

```zsh
update_codex
```

rebuilds the image.

## Build

Build or refresh the image with:

```bash
docker build --no-cache -t codex-sandbox .
```

The image starts `/bin/bash -il`.  Inside the container, the profile script asks whether to start
Codex.  Answering yes runs:

```bash
codex resume --all
```

When you exit Codex with `/exit`, you return to the Linux Bash prompt inside the container.

## Codex State

Docker Codex uses:

```text
~/.codex
```

as its persistent `CODEX_HOME` on the Mac.  Its config and SQLite state databases are saved there.

The entrypoint does not rewrite `~/.codex/config.toml` in this default shared-home mode.  If the
shared config contains host-only settings, make those settings work in both places or start the
launcher with a separate Docker home:

```zsh
export CODEX_DOCKER_HOME="/host-codex/docker-home"
codex
```

Docker is the filesystem boundary here: the launcher only mounts the host paths Codex should be
allowed to see and change.

The launcher mounts Docker Desktop's socket from `~/.docker/run/docker.sock` into the sandbox at
`/var/run/docker.sock`.  That lets Codex inside `codex-sandbox` start Docker-backed MCP servers,
including the local `rally-qa-mcp` image.  If your Docker socket lives somewhere else, set:

```zsh
export CODEX_DOCKER_SOCKET="/path/to/docker.sock"
```

To use a different host Codex directory:

```zsh
export CODEX_HOST_DIR="$HOME/.codex-work"
codex
```

To use a different host dev directory:

```zsh
export CODEX_HOST_DEV_DIR="$HOME/dev"
codex
```

## Host Postgres

The launcher makes Postgres running natively on the Mac reachable from inside the sandbox at:

```text
host.docker.internal:5432
```

It also sets these environment variables in the container:

```text
PGHOST=host.docker.internal
PGPORT=5432
POSTGRES_HOST=host.docker.internal
POSTGRES_PORT=5432
```

The image is based on `postgres:16`, so it includes a PostgreSQL 16 `psql` client that matches a PostgreSQL 16 server on the Mac.
After rebuilding the image, verify from inside the container with:

```bash
psql --version
psql -d postgres -c "select version();"
```

Override the defaults before starting Codex if needed:

```zsh
export CODEX_POSTGRES_HOST="host.docker.internal"
export CODEX_POSTGRES_PORT="5432"
codex
```

On the Mac, Postgres must accept TCP connections on that port. For a standard local setup, make sure it is listening on `localhost` or `*` and that `pg_hba.conf` allows local TCP connections.

## Authentication

If Codex is not already authenticated through the shared host Codex directory, run this inside the
container:

```bash
codex login --device-auth
```

## Stopping

Use `/exit` to leave Codex and return to the Linux shell.  Use `Ctrl-D` or `exit` from that shell to
leave Docker and return to the Mac prompt.
