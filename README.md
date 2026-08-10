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
~/aen             -> /root/dev/aen, when present
~/.codex          -> /host-codex and CODEX_HOME inside Docker
~/.sdvi           -> /root/.sdvi
~/.aws            -> /root/.aws
~/.config/gh      -> /root/.config/gh
~/.gitconfig      -> /root/.gitconfig, when present
~/.ssh            -> /root/.ssh, when present
~/dotfiles        -> /root/dotfiles, when present
~/.docker/run/docker.sock -> /var/run/docker.sock, when present
```

When started from inside `~/dev`, the container working directory is set to the matching path under
`/root/dev`.  When started from inside `~/aen`, the working directory is set to the matching path
under `/root/dev/aen`.  This keeps Mac Git config rules such as `includeIf "gitdir:~/dev/aen/"`
working inside the container even when the project lives at `~/aen` on the Mac.  The `~/dev` tree is
still available at `/workspace/dev` for compatibility.  If started outside these trees, the
container starts in `/root/dev`.

The launcher does not modify the Mac `~/.gitconfig`; it only mounts it into the container and maps
Docker paths so the existing `~/dev/aen` include rule can match.  To make normal Mac-side Git
commands under `~/aen` use the same AEN config, add this separate include on the Mac:

```gitconfig
[includeIf "gitdir:~/aen/"]
    path = ~/dotfiles/.gitconfig_aen
```

`codex-sandbox-entrypoint.sh` runs inside the container before Bash starts. It prepares a
Docker-specific Codex home under the host's `~/.codex/docker-home` and points `/root/.codex` at it.
Auth, keys, skills, plugins, rules, caches, sessions, and history remain shared with the host Codex
home through links.

Docker Codex uses a separate home at `/host-codex/docker-home`. The launcher reads all user-specific
settings and MCP definitions from `~/.config/codex_sandbox.cfg`. The entrypoint seeds a Linux-safe
Codex config, strips inherited MCP settings, links shared state from the host `~/.codex`, and loads
the MCP tables from that file. The example defines `rally_dev`, `rally_qa`, and `rally_prod`. Dev
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
connection, or MCP servers. Values beginning with `~/` are expanded against the host home directory.

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

The host Codex state is mounted at:

```text
~/.codex/docker-home
```

as Docker Codex's persistent `CODEX_HOME`.

The entrypoint does not rewrite the host `~/.codex/config.toml`. It creates the Docker-specific
configuration under `~/.codex/docker-home`, retaining compatible non-MCP settings and replacing
the inherited MCP sections with the contents of `~/.config/codex_sandbox.cfg` on every start.

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
