# Sandbox Codex

Author: Marc Schwarzschild

This repo builds a Docker image for running OpenAI Codex with a narrower view of the host
filesystem.  The container gets the tools Codex needs, a Bash startup file from this repo, and
controlled mounts for source code and Codex state.

## How It Works

`Dockerfile` builds the `codex-sandbox` image.  It installs Codex, common development tools,
pre-commit, the AWS CLI, Git LFS, the GitHub CLI, the Docker CLI, and copies this repo's `.bashrc`
to `/root/.bashrc` in the image.

`docker_codex.zsh` is the host-side launcher.  It mounts:

```text
~/dev             -> /workspace/dev
~/dev             -> /root/dev
~/.codex          -> /host-codex (persistent credentials and sessions)
~/.sdvi           -> /root/.sdvi
~/.aws            -> /root/.aws
~/.config/gh      -> /root/.config/gh
~/.gitconfig      -> /root/.gitconfig, when present
~/.ssh            -> /root/.ssh, when present
~/dotfiles        -> /root/dotfiles, read-write when present
~/.docker/run/docker.sock -> /var/run/docker.sock, when present
```

When started from inside `~/dev`, the container working directory is set to the matching path under
`/root/dev`. This includes `~/dev/aen`, which needs no separate mount. The `~/dev` tree is
also available at `/workspace/dev` for compatibility. When started from an additional
`host_dirs` directory, the container keeps its physical working directory; otherwise it
starts in `/root/dev`.

The launcher mounts the Mac `~/.gitconfig` without modifying it. Existing Git config rules
such as `includeIf "gitdir:~/dev/aen/"` can match the corresponding container path.

The launcher mounts this repo's current `codex-sandbox-entrypoint.sh` into the
container, so startup policy changes do not require rebuilding the image. It runs
before Bash starts. The host's `~/.codex` is mounted at `/host-codex`.
Each container uses `/tmp/codex-home` as `CODEX_HOME`, with persistent credentials
and session history linked from the configured `docker_codex_home`.
The launcher reads sandbox settings and MCP definitions from
`~/.config/codex_sandbox.cfg`. On every start, the entrypoint updates the container's `config.toml` with
Linux-safe sandbox settings, replaces its MCP sections with the tables from that file, and leaves
all other Codex state in place. The example defines `rally_dev`, `rally_qa`, and `rally_prod`. Dev
permits confirmed writes, while QA and production enforce read-only access. All three pass SDVI and
AWS credentials through to the MCP container's `/home/app` runtime:

```bash
docker run --rm -i \
  -e RALLY_PROFILE=qa \
  -e RALLY_READ_ONLY=true \
  -e RALLY_ALLOW_UNSAFE_TOOLS=true \
  -v "$HOME/.sdvi:/home/app/.sdvi:ro" \
  -v "$HOME/.aws:/home/app/.aws:ro" \
  rally-qa-mcp
```

## Shell Setup

Create the user configuration once on the host Mac:

```zsh
mkdir -p ~/.config
cp "$DEVPATH/tbg/codex_sandbox/codex_sandbox.cfg.example" \
  ~/.config/codex_sandbox.cfg
```

Edit that one file to change host paths, the image, Docker Codex home, Docker socket, Postgres
connection, port forwards, or MCP servers. Values beginning with `~/` are expanded against the host home directory.

The host launcher requires Python 3.11 or newer to parse the TOML configuration.
Use the optional `host_dirs` list in `[sandbox]` for additional directories:

```toml
host_dirs = [
  "~/Library/Mobile Documents/com~apple~CloudDocs/DevCloud",
]
```

Each directory is mounted read-write at its original absolute Mac path, preserving
absolute symlinks from `~/dev`. This iCloud path is `DEVICLOUDPATH` from `dotfiles/.zshrc`
(it already includes `DevCloud`). Launching from any listed directory preserves its
physical working directory, unless the existing dev mapping applies. Every listed
path must exist; omit `host_dirs` or use `[]` for no additional mounts. The existing
settings for mounts with specific container destinations remain supported.
Add more paths to this list without changing the launcher. Restart the sandbox after
changing mounts; an image rebuild is unnecessary.

By default, Docker forwards sandbox port 8000 to an available desktop localhost
port. Each session gets its own port, so multiple sandbox sessions can run together.
The launcher attaches as the container starts and prints the assigned address once
Docker allocates it, keeping startup prompts visible. The address looks like, for
example `8000/tcp -> 127.0.0.1:49153`; open `http://localhost:49153` on the desktop.

A project can override the port mappings with `.codex/sandbox.toml` in its launch
directory. For example, BEDS uses:

```toml
[port_forward]
ports = ["55080:8000"]
```

This keeps BEDS at `http://127.0.0.1:55080` on the Mac. Projects without this
override keep the global settings, which default to an available desktop port.
If a fixed port is already published by a running container, the launcher shows
that container and stops before creating another. Exit the existing sandbox's
shell (`/exit` leaves Codex; `exit` then leaves the shell), or use
`docker stop <container-ID>` if that container is no longer needed. To run sessions
alongside one another, change the project's mapping to `ports = ["0:8000"]`.
The launcher preserves fixed URLs; Docker still reports conflicts with non-Docker
processes or ports claimed during startup. On the Mac, `lsof -nP -iTCP:55080 -sTCP:LISTEN`
can help identify another process using the port. Project port configuration is
read on the Mac before container creation.

If the container working directory contains `.codex/startup.sh`, the launcher runs
it with Bash after the port report and before opening the shell or Codex. Use this
project-owned script to start local services and print their desktop URLs. The
hook must return after starting any background services; its failure is reported
without preventing access to the sandbox. Only the current working directory is
checked. Starting a sandbox in a project with this file executes that project's
script. Hook support is in the host launcher and needs no image rebuild.

The image includes `uv`. The launcher sets `UV_PROJECT_ENVIRONMENT` to a
project-specific Linux path under `/opt/venv/` and `UV_CACHE_DIR` to `/opt/uv-cache`,
both inside the container. Hooks can use `uv run` without touching a Mac `.venv`.
These environments and caches disappear when the session's container is removed.
The hook prints the environment path before running; it must return after starting
services in the background.

The launcher also overlays Codex's global `AGENTS.override.md` inside the container.
It preserves the host's global override instructions (or `AGENTS.md` when no
override exists) and appends sandbox-only authorization to use `uv`. Repository-local
environments remain protected. The Mac's instruction files are not changed.
When switching projects inside a session, set `UV_PROJECT_ENVIRONMENT` to a
different project-specific path under `/opt/venv/` before running uv project commands.
Restart through the updated launcher to apply these changes; no rebuild is needed
if the image already includes `uv`.

To override this behavior, add this separate section to `~/.config/codex_sandbox.cfg`:

```toml
[port_forward]
ports = [
  "8000:8000",
  "8001:8010",
]
```

Add as many TCP mappings as needed, in `host:container` order. For example,
`"8000:8010"` exposes sandbox port 8010 at `http://localhost:8000` on the desktop.
Forwarded ports bind to desktop `127.0.0.1`. The server inside the sandbox must
listen on `0.0.0.0` (for example, `python3 -m http.server 8000 --bind 0.0.0.0`).
Port numbers must be between 1 and 65535, and each fixed host port must be unique.
Use host port 0 (for example `"0:8000"`) to let Docker allocate an available port.
Omit the section for automatic forwarding of port 8000, or use `ports = []` to
disable forwarding. Fixed host ports can only be used by one session at a time.
Restart the sandbox
after changing mappings; an image rebuild is unnecessary.

Your `~/.zshrc` defines these helpers:

```zsh
run_codex() {
    source "$DEVPATH/tbg/codex_sandbox/docker_codex.zsh" "$@"
}

alias codex=run_codex

build_codex() {
    cd $DEVPATH/tbg/codex_sandbox
    echo `pwd`
    docker build --no-cache -t codex-sandbox .
}

alias update_codex=build_codex
```

The launcher also provides an interactive session-deletion picker. A bare
`codex delete` opens the picker; passing a session ID or name continues to use
the native CLI behavior. The picker reads the host Codex session index without
modifying it, then runs the selected deletion through the Codex CLI in the
container:

```zsh
codex delete
# or
codex delete-picker
```

The picker and Codex CLI both run inside the container. No host installation
of Codex, `fzf`, or Python is used.

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

The persistent Codex home on the Mac is:

```text
~/.codex
```

It is mounted at `/host-codex`. The container uses a separate configuration in
`/tmp/codex-home` so starting another project cannot change its MCP configuration.

The entrypoint copies the host config into the container's Codex home and updates
that copy atomically on every start. It retains non-MCP
settings, forces the sandbox mode appropriate for the container, and replaces MCP sections with
the contents of `~/.config/codex_sandbox.cfg`. Rally MCP entries (`rally` and
`rally_*`, including their subtables) are included only when the sandbox starts
in a directory named exactly `aen` or any of its descendants, anywhere on the Mac.
The launcher checks the physical Mac launch directory and its ancestors before
mapping paths into Docker. Starting outside such a tree omits Rally; other MCP servers
remain available. Paths are resolved physically, including symlinks. Restart the
sandbox after changing projects to apply the appropriate MCP configuration.

The config supports `@HOST_SDVI_DIR@` and `@HOST_AWS_DIR@` placeholders in MCP tables. These expand to the
original host paths, which is required for bind mounts made by nested Docker commands. Literal
paths and MCP servers that do not use Docker can be written normally.

Docker is the filesystem boundary here: the launcher only mounts the host paths Codex should be
allowed to see and change.

The launcher mounts the Docker Desktop socket configured by `docker_socket` into the sandbox at
`/var/run/docker.sock`. That lets Codex inside `codex-sandbox` start Docker-backed MCP servers,
including the local `rally-qa-mcp` image. All mount source paths are controlled by the `[sandbox]`
table in `~/.config/codex_sandbox.cfg`.

Your Mac `credential.helper=osxkeychain` setting is supported in the Linux container by a small
`git-credential-osxkeychain` shim that delegates to `gh auth git-credential`.  The launcher mounts
`~/.config/gh` so GitHub CLI auth can persist between runs.

Host GitHub CLI, SSH, and dotfiles locations are also configured in that `[sandbox]` table.

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

Override `postgres_host` and `postgres_port` in `~/.config/codex_sandbox.cfg` if needed.

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

If present, `.codex/prestart.sh` runs on the host before port conflict checks
and container creation. It receives the new container working directory as its
first argument. A nonzero exit aborts startup. Use it for project-specific
handoff tasks such as stopping a previous dashboard sandbox.
