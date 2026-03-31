# syntax = docker/dockerfile:1.22-labs

# --- Base Image ---------------------------------------------------------------
FROM python:3.14.3-alpine3.23 AS base
WORKDIR /app
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_ROOT_USER_ACTION=ignore \
    PYTHONDONTWRITEBYTECODE=1


# --- Extracted Tools ----------------------------------------------------------
FROM base AS tools
WORKDIR /dist

# Fetch required binaries without bloating the cache
RUN apk add --no-cache util-linux shadow

# Replicate necessary directory structures and move binaries
RUN <<EOF
    install -d ./usr/bin ./usr/lib ./usr/sbin
    install -p /usr/bin/setpriv ./usr/bin/
    install -p /usr/lib/libcap-ng.so.0 ./usr/lib/
    install -p /usr/lib/libbsd.so.0 ./usr/lib/
    install -p /usr/lib/libmd.so.0 ./usr/lib/
    install -p /usr/sbin/usermod /usr/sbin/groupmod ./usr/sbin/
EOF


# --- Download & Build Wheels --------------------------------------------------
FROM base AS wheels

# Download source packages and pre-built wheels
RUN --mount=type=cache,id=pip,target=/root/.cache/pip \
    --mount=type=bind,source=./requirements.txt,target=./requirements.txt \
    pip download --dest /wheels -r requirements.txt

# Build any missing wheels from source
RUN --mount=type=cache,id=pip,target=/root/.cache/pip \
<<EOF
    set -x
    set -- $(ls /wheels/*.gz /wheels/*.zip 2>/dev/null || true)
    if [ $# -gt 0 ]; then
        pip wheel "$@" --wheel-dir=/wheels
    fi
EOF


# --- Install Dependencies -----------------------------------------------------
FROM base AS build

# Install the built wheels into an isolated prefix directory
RUN --mount=type=bind,from=wheels,source=/wheels,target=/wheels \
    pip install --prefix=/install --no-cache-dir /wheels/*.whl


# --- Compile Application ------------------------------------------------------
FROM base AS compile
ARG APP_VERSION
ENV APP_VERSION=$APP_VERSION

COPY plextraktsync ./plextraktsync/
COPY plextraktsync.sh .

# Stamp the version and verify it
RUN echo "__version__ = '${APP_VERSION:-unknown}'" > plextraktsync/__init__.py && \
    python -c "from plextraktsync import __version__; print(f'Version: {__version__}')"

# Compile Python files to bytecode for faster startup
RUN python -m compileall . && \
    chmod -R a+rX,g-w .


# --- Final Runtime Image ------------------------------------------------------
FROM base AS runtime

# 1. System Setup: Create the non-root application user and group
RUN <<EOF
    set -x
    apk add --no-cache su-exec
    addgroup --gid 1000 --system plextraktsync
    adduser \
        --disabled-password \
        --gecos "Plex Trakt Sync" \
        --home /app \
        --ingroup plextraktsync \
        --no-create-home \
        --uid 1000 \
        plextraktsync
EOF

# 2. Environment Variables
ENV \
    # XDG Base Directories
    XDG_CACHE_HOME=/app/xdg/cache \
    XDG_CONFIG_HOME=/app/xdg/config \
    XDG_DATA_HOME=/app/xdg/data \
    # Pipx and Python User Paths
    PIPX_BIN_DIR=/app/xdg/bin \
    PIPX_HOME=/app/xdg/pipx \
    PYTHONUSERBASE=/app/xdg \
    HOME=/app/xdg \
    # PlexTraktSync Configs
    PTS_CONFIG_DIR=/app/config \
    PTS_CACHE_DIR=/app/config \
    PTS_LOG_DIR=/app/config \
    PTS_IN_DOCKER=1 \
    # System and Paths
    PYTHONUNBUFFERED=1 \
    PATH=/app/xdg/bin:/app/xdg/.local/bin:$PATH

# 3. Copy Build Artifacts
COPY --from=build /install /usr/local/
COPY --from=tools /dist /
COPY --from=compile --chown=plextraktsync:plextraktsync /app ./
COPY --chown=plextraktsync:plextraktsync entrypoint.sh /init

# 4. Final Configurations
# Setup symlinks, permissions, and required directories
RUN ln -s /app/plextraktsync.sh /usr/bin/plextraktsync && \
    chmod +x /init /app/plextraktsync.sh && \
    mkdir -p /app/config /app/xdg && \
    chown -R plextraktsync:plextraktsync /app

VOLUME ["/app/config", "/app/xdg"]
ENTRYPOINT ["/init"]


# --- Test Target --------------------------------------------------------------
FROM runtime AS test
ENV TRACE=1
RUN ["/init", "test"]


# --- Default Target -----------------------------------------------------------
FROM runtime
