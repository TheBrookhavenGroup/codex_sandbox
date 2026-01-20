
# Sandbox Codex


OpenAI Codex is an amazing tool useful beyond just having a ChatGPT style conversation.
It can also read and modify files.  A common use is modifying or writing new computer code.
However, unchecked it has full access to all information on the computer it runs on.
With a couple of simple scripts in this repo codex can be sandboxed restricting access to only
relevant directories using [Docker](https://www.docker.com/).

The Dockerfile defines an image that installs dependent code and isolates codex.  Running inside
Docker it only has access to the `/workspace` root and any subdirectories.  The `docker_codex.zsh`
Z shell convenience script maps the current working directory on the host computer to the `/workspace`
directory giving codex access only to the host computer working directory and its children.


The script will prompt the user to open a sandbox shell and if so, prompts to start codex.

The following few lines added to the `~/.zshrc` runs `docker_codex.zsh` if the directory where zsh is started
is in the `$HOME/Documents/dev` directory or any of its chidren.  This is nice because an IDE, say PyCharm, shell will
offer to sandbox the terminal shell and then offer to start codex.

```zsh
DEVPATH=$HOME/Documents/dev

run_codex() {
    if [[ "$PWD" == "$DEVPATH" || "$PWD" == "$DEVPATH"/* ]]; then
	source "$DEVPATH/codex_sandbox/docker_codex.zsh"
    fi
}

run_codex

```


## Build

Use this command to build the Docker image.  Sometimes codex informs us that a new version of codex
is available and offers to update it.  That would only update it for the one run.  Re-running the follwoing
`docker build` will make a new Docker image with the latest version of codex so the upgrade would not be
needed each time the sandbox is started.


```bash

docker build --no-cache -t codex-sandbox .
```


## Authentication

Codex needs authentication.  It should only need that once and will save credentials to `~/.codex`.

Use this command to authenticate:

```bash
# codex login --device-auth
```


## Stopping


Use `Ctrl-D` to exit codex and docker.