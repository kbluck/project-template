###################################################################################################################################
### Global Arguments. Note that you can override these on the `docker build` command line using `--build-arg <ARG_NAME>=<VALUE>`
###################################################################################################################################

### Default to latest Debian Slim Linux.
ARG DEBIAN_VERSION="trixie-slim"

### Path to Bun binaries
ARG BUN_INSTALL_BIN="/usr/local/bin"

### Disable Bun's runtime transpiler cache by default since cache is not very useful on ephemeral containers.
ARG BUN_RUNTIME_TRANSPILER_CACHE_PATH=0

### Default container username. Mainly important for working directory.
ARG DEV_GID=1000
ARG DEV_UID=1000
ARG DEV_SHELL="/bin/bash"
ARG DEV_USERNAME="dev"
ARG DEV_HOME="/home/${DEV_USERNAME}"
ARG DEV_WORKSPACE="/workspaces"


###################################################################################################################################
### Build Stage 1: Copy Bun binaries into fresh Debian image. This gets bun, bunx, docker-entrypoint.sh, and the node symlink.
###################################################################################################################################

### Start from a fresh Debian Slim image.
FROM debian:${DEBIAN_VERSION} AS build_stage_1

### Add needed arguments to stage scope.
ARG BUN_INSTALL_BIN \
    DEV_GID         \
    DEV_HOME        \
    DEV_SHELL       \
    DEV_UID         \
    DEV_USERNAME

### Copy over the contents of the Bun installation path. Add a `node` symlink pointing to `bun` so calls to `node` invoke `bun`.
COPY --from=oven/bun:1.4.2-slim ${BUN_INSTALL_BIN} ${BUN_INSTALL_BIN}
RUN ln -s ${BUN_INSTALL_BIN}/bun ${BUN_INSTALL_BIN}/node

### Add the `dev` group and system user, creating the home directory in the process.
RUN groupadd --gid "${DEV_GID}" "${DEV_USERNAME}"              \
 && useradd --system  --no-log-init --shell "${DEV_SHELL}"     \
    --create-home --home-dir "${DEV_HOME}"                     \
    --gid "${DEV_USERNAME}" --uid "${DEV_UID}" "${DEV_USERNAME}"


###################################################################################################################################
### Build Stage 2: Consolidate the optimized layers, add environment, and add entrypoint.
###################################################################################################################################

### Start from scratch blank image.
FROM scratch AS build_stage_2

### Add needed arguments to stage scope.
ARG BUN_INSTALL_BIN BUN_RUNTIME_TRANSPILER_CACHE_PATH  \
    DEV_HOME  DEV_USERNAME  DEV_WORKSPACE

### Copy entire optimized filesystem as single layer. Exclude caches, logs, mail, and temporary files.
COPY --from=build_stage_1 --exclude=**/cache/* --exclude=**/log/* --exclude=**/mail/* --exclude=**/temp/* --exclude=**/tmp/* / /

###  Set the same environment variables that are set by the official Anomaly.co image.
ENV BUN_INSTALL_BIN=${BUN_INSTALL_BIN}  BUN_RUNTIME_TRANSPILER_CACHE_PATH=${BUN_RUNTIME_TRANSPILER_CACHE_PATH} \
    LANG=en_US.UTF-8  LANGUAGE=en_US:en  LC_ALL=en_US.UTF-8 \
    HISTFILE=${DEV_HOME}/.local/state/bash/history

### Set the user and working directory.
WORKDIR ${DEV_WORKSPACE}
USER    ${DEV_USERNAME}

### `docker-entrypoint.sh` detects whether a shell command was passed to `docker run`. If not, it runs `bun` with any arguments
### passed at the end of `docker run` appended. Example: `docker run -it --rm bun run index.ts` (Invokes `bun run index.ts`).
### If a command is recognized in `docker run`, it runs that instead of bun. Example: `docker run -it --rm sh` (Invokes `sh`).
### Note that environment variables are not expanded, either at build or at run time. Therefore, you should not include environment
### variables in the ENTRYPOINT. In this case, `docker-entrypoint.sh` is in a directory that is on $PATH so no path is needed.
ENTRYPOINT [ "docker-entrypoint.sh" ]
