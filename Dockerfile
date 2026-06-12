# ==============================================================================
# PlexTraktSync Enhanced
#
# Multi-stage Docker build that clones PlexTraktSync from upstream source,
# applies optional .patch files from the Patches/ directory, then builds a
# minimal runtime image.
# ==============================================================================

# --- Clone Source --------------------------------------------------------------
FROM alpine/git:latest AS source
WORKDIR /src

ARG PTS_VERSION=main
ARG PTS_REPO=https://github.com/Taxel/PlexTraktSync.git

RUN git clone --depth 1 --branch ${PTS_VERSION} ${PTS_REPO} .


# --- Apply Patches ------------------------------------------------------------
FROM source AS patched

COPY Patches/ /patches/

RUN if ls /patches/*.patch 2>/dev/null; then \
        for patch in /patches/*.patch; do \
            echo "==> Applying: $(basename $patch)"; \
            patch -p1 -d /src < "$patch"; \
        done; \
    else \
        echo "No patches to apply"; \
    fi


# --- Build Wheels (dependencies) ----------------------------------------------
FROM python:3.14.6-alpine3.23 AS wheels
WORKDIR /dist

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_ROOT_USER_ACTION=ignore \
    PYTHONDONTWRITEBYTECODE=1

# Download all dependency wheels
COPY --from=patched /src/requirements.txt ./requirements.txt

RUN --mount=type=cache,id=pip,target=/root/.cache/pip \
    pip download --dest /wheels -r requirements.txt

# Build any source-only packages into wheels
RUN --mount=type=cache,id=pip,target=/root/.cache/pip \
    set -x && \
    files=$(ls /wheels/*.tar.gz /wheels/*.zip 2>/dev/null || true) && \
    if [ -n "$files" ]; then \
        pip wheel $files --wheel-dir=/wheels; \
    fi


# --- Install Dependencies -----------------------------------------------------
FROM python:3.14.6-alpine3.23 AS build

COPY --from=wheels /wheels /wheels
RUN pip install --prefix=/install --no-cache-dir /wheels/*.whl


# --- Compile Application ------------------------------------------------------
FROM python:3.14.6-alpine3.23 AS compile
ARG APP_VERSION
ENV APP_VERSION=$APP_VERSION

WORKDIR /app

COPY --from=patched /src/plextraktsync/ ./plextraktsync/
COPY --from=patched /src/plextraktsync.sh .

# Stamp version and verify
RUN echo "__version__ = '${APP_VERSION:-unknown}'" > plextraktsync/__init__.py && \
    python -c "from plextraktsync import __version__; print(f'Version: {__version__}')"

# Compile to bytecode for faster startup
RUN python -m compileall . && \
    chmod -R a+rX,g-w .


# --- Extract Runtime Tools ----------------------------------------------------
FROM python:3.14.6-alpine3.23 AS tools
WORKDIR /dist

RUN apk add --no-cache util-linux shadow

RUN <<EOF
    install -d ./usr/bin ./usr/lib ./usr/sbin
    install -p /usr/bin/setpriv ./usr/bin/
    install -p /usr/lib/libcap-ng.so.0 ./usr/lib/
    install -p /usr/lib/libbsd.so.0 ./usr/lib/
    install -p /usr/lib/libmd.so.0 ./usr/lib/
    install -p /usr/sbin/usermod /usr/sbin/groupmod ./usr/sbin/
EOF


# --- Final Runtime Image ------------------------------------------------------
FROM python:3.14.6-alpine3.23 AS runtime

WORKDIR /app

# 1. System setup: create non-root user
RUN <<EOF
    set -x
    apk add --no-cache su-exec tzdata
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

# 2. Environment variables
ENV \
    XDG_CACHE_HOME=/app/xdg/cache \
    XDG_CONFIG_HOME=/app/xdg/config \
    XDG_DATA_HOME=/app/xdg/data \
    PIPX_BIN_DIR=/app/xdg/bin \
    PIPX_HOME=/app/xdg/pipx \
    PYTHONUSERBASE=/app/xdg \
    HOME=/app/xdg \
    PTS_CONFIG_DIR=/app/config \
    PTS_CACHE_DIR=/app/config \
    PTS_LOG_DIR=/app/config \
    PTS_IN_DOCKER=1 \
    PYTHONUNBUFFERED=1 \
    PATH=/app/xdg/bin:/app/xdg/.local/bin:$PATH

# 3. Copy build artifacts
COPY --from=build /install /usr/local/
COPY --from=tools /dist /
COPY --from=compile --chown=plextraktsync:plextraktsync /app ./
COPY --chown=plextraktsync:plextraktsync entrypoint.sh /init

# 4. Final configuration
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
