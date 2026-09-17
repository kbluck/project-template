###################################################################################################################################
### Global Arguments. Note that you can override these on the `docker build` command line using `--build-arg <ARG_NAME>=<VALUE>`
###################################################################################################################################

### Default to recent Debian Slim Linux minor version. Tag should be of form: `##.#-slim`
ARG DEBIAN_TAG="13.6-slim"

### Dev container remote user parameters. 
ARG DC_USERNAME="coder"                         # Linux username. This should be the dev container `remoteUser`.
ARG DC_UID=1000                                 # Linux UID (user ID). Note that "1000" is the typical default for dev containers.
ARG DC_GROUPNAME=${DC_USERNAME}                 # Linux user group name
ARG DC_GID=${DC_UID}                            # Linux GID (group ID)
ARG DC_SHELL="/bin/bash"                        # Default shell executable
ARG DC_HOMEBASE="/home"                         # The base path to the parent of user home folders
ARG DC_HOMEPATH="${DC_HOMEBASE}/${DC_USERNAME}" # Full path to the user home folder.

### Dev container miscellaneous environment variables
ARG DC_CHARSET="UTF-8"                          # The charset for the locale language.
ARG DC_LANGUAGE="en_US"                         # Prioritized language for `gettext` language translations.
ARG DC_LC_ALL="${DC_LANGUAGE}.${DC_CHARSET}"    # The locale name for language/culture.
ARG DC_TIMEZONE="America/Los_Angeles"           # Default timezone for container.

### Bash parameters
ARG BASH_HISTORY_PATH="${DC_HOMEPATH}/.local/state/bash/history"

### Bun parameters
ARG BUN_VERSION="1.4.2"
ARG BUN_BIN_PATH="/usr/local/bin"
ARG BUN_USER_PATH="${DC_HOMEPATH}/.bun"
ARG BUN_CACHE_PATH="${BUN_USER_PATH}/cache"

### Default path to code/project parent directory.
ARG DC_CODEROOT="${DC_HOMEPATH}/code"           # This should be the dev container `workspaceFolder`.


###################################################################################################################################
### Build Stage 1: Get official Bun image to copy binaries.
###################################################################################################################################

### Get official Bun image from which to copy binaries. This could theoretically be done directly in COPY --from but you can't use
### an argument for that, so making an empty stage is the workaround.
FROM oven/bun:${BUN_VERSION} AS build_stage_1


###################################################################################################################################
### Build Stage 2: Create curated Debian Slim image and copy Bun binaries.
###################################################################################################################################

### Start from a fresh Debian Slim image.
FROM debian:${DEBIAN_TAG} AS build_stage_2

### Update packages, install locale and set timezone
ARG DC_CHARSET  DC_LANGUAGE  DC_LC_ALL  DC_TIMEZONE
RUN <<-EOF

### Configure the default timezone
    echo "${DC_TIMEZONE}" > /etc/timezone
    ln -sf "/usr/share/zoneinfo/${DC_TIMEZONE}" /etc/localtime

### Configure the default locale and character set
    echo "${DC_LC_ALL} ${DC_CHARSET}" > /etc/locale.gen

### Set APT to non-interactive so it will not block to ask questions and update the package lists.
    export DEBIAN_FRONTEND=noninteractive
    apt-get update --quiet=2

### Upgrade remaining installed packages.
    apt-get upgrade --quiet=2 --no-install-recommends

### Install Locale and timezone data packages
    apt-get install --quiet=2 --no-install-recommends locales tzdata

### Install shell, editor and text-processing utilities. Set them as default for their related commands.
    apt-get install --quiet=2 --no-install-recommends bash-completion jq less nano-tiny vim-tiny
    update-alternatives --install /usr/bin/vim  vim  /usr/bin/vi    90
    update-alternatives --install /usr/bin/nano nano /bin/nano-tiny 90
    update-alternatives --set editor /bin/nano-tiny

### Install Git essential packages
    apt-get install --quiet=2 --no-install-recommends git gnupg2 openssh-client          

### Install network utilities
    apt-get install --quiet=2 --no-install-recommends ca-certificates curl iproute2

### Install system monitoring utilities
    apt-get install --quiet=2 --no-install-recommends lsb-release lsof procps psmisc

### Install archive utilities
    apt-get install --quiet=2 --no-install-recommends bzip2 unzip xz-utils zip zlib1g

### Install Python for scripting. Set Python3 as default Python.
    apt-get install --quiet=2 --no-install-recommends python3
    update-alternatives --install /usr/bin/python python /usr/bin/python3 90

### Clean up after APT. 
    apt-get autoremove --quiet=2
    apt-get clean      --quiet=2

### APT may have added a bunch of locales. Rewrite locale configuration, clean up locale data and re-generate locale.
    echo "${DC_LC_ALL} ${DC_CHARSET}" > /etc/locale.gen
    rm -rf /usr/lib/locale/*
    locale-gen
EOF

### Copy Bun binaries from prior stage. Set Bun as the default Node.
ARG  BUN_BIN_PATH
COPY --from=build_stage_1 ${BUN_BIN_PATH} ${BUN_BIN_PATH}
RUN  update-alternatives --install ${BUN_BIN_PATH}/node node ${BUN_BIN_PATH}/bun 90

### Add the `remoteUser` group and user, creating the home directory in the process.
ARG DC_USERNAME  DC_UID  DC_GROUPNAME  DC_GID  DC_SHELL  DC_HOMEPATH
RUN groupadd --gid "${DC_GID}" "${DC_USERNAME}"        \
 && useradd  --no-log-init --shell "${DC_SHELL}"       \
             --create-home --home-dir "${DC_HOMEPATH}" \
             --gid "${DC_USERNAME}" --uid "${DC_UID}" "${DC_USERNAME}"




###################################################################################################################################
### Build Stage 3: Consolidate the optimized layers, add environment, and add entrypoint.
###################################################################################################################################

### Start from scratch blank image.
FROM scratch AS build_stage_3

### Copy entire optimized filesystem as single layer. Exclude APT lists, caches, docs, hardware, logs, mail, and tempfiles.
COPY --from=build_stage_2         \
     --exclude=**/lib/apt/lists/* \
     --exclude=**/lib/firmware/*  \
     --exclude=**/share/bug/*     \
     --exclude=**/cache/*         \
     --exclude=**/doc/*           \
     --exclude=**/info/*          \
     --exclude=**/log/*           \
     --exclude=**/man/*           \
     --exclude=**/mail/*          \
     --exclude=**/temp/*          \
     --exclude=**/tmp/*           \
     / /

### Include global arguments in this stage's scope.
ARG DC_USERNAME  DC_HOMEPATH  DC_CODEROOT  DC_LC_ALL  DC_LANGUAGE  DC_TIMEZONE  \
    BASH_HISTORY_PATH  BUN_CACHE_PATH

### Set DevContainer metadata on the image
LABEL devcontainer.metadata='[{                            \
      "containerUser": "'${DC_USERNAME}'",                 \
      "remoteUser":    "'${DC_USERNAME}'",                 \
      "mounts": [                                          \
        {                                                  \
          "type":   "bind",                                \
          "options": [ "ro" ],                             \
          "source": "${localEnv:HOME}/.ssh",               \
          "target": "'${DC_HOMEPATH}'/.ssh"                \
        },                                                 \
        {                                                  \
          "type":   "volume",                              \
          "source": "'${DC_USERNAME}'-bash-history",       \
          "target": "'${BASH_HISTORY_PATH}'"               \
        },                                                 \
        {                                                  \
          "type":   "volume",                              \ 
          "source": "'${DC_USERNAME}'-bun-cache",          \
          "target": "'${BUN_CACHE_PATH}'"                  \
        }                                                  \
      ],                                                   \
      "securityOpt": [                                     \
          "no-new-privileges=true"                         \
      ],                                                   \
      "init":                true,                         \
      "updateRemoteUserUID": true,                         \
      "shutdownAction":      "stopContainer",              \
      "userEnvProbe":        "loginInteractiveShell"       \
}]'

### Set the same environment variables that are set by the official Anomaly.co image.
ENV HISTFILE=${BASH_HISTORY_PATH}  TZ=${DC_TIMEZONE}                \
    LANG=${DC_LC_ALL}  LC_ALL=${DC_LC_ALL}  LANGUAGE=${DC_LANGUAGE} \
    BUN_INSTALL_CACHE_DIR=${BUN_CACHE_PATH}/install                 \
    BUN_RUNTIME_TRANSPILER_CACHE_PATH=${BUN_CACHE_PATH}/transpiler

### Set the user and working directory.
WORKDIR ${DC_CODEROOT}
USER    ${DC_USERNAME}

### `docker-entrypoint.sh` detects whether a shell command was passed to `docker run`. If not, it runs `bun` with any arguments
### passed at the end of `docker run` appended. Example: `docker run -it --rm bun run index.ts` (Invokes `bun run index.ts`).
### If a command is recognized in `docker run`, it runs that instead of bun. Example: `docker run -it --rm sh` (Invokes `sh`).
### Note that environment variables are not expanded, either at build or at run time. Therefore, you should not include environment
### variables in the ENTRYPOINT. In this case, `docker-entrypoint.sh` is in a directory that is on $PATH so no path is needed.
ENTRYPOINT [ "/bin/bash" ]
