FROM docker.io/library/alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6

COPY --from=ghcr.io/astral-sh/uv:0.11@sha256:b46b03ddfcfbf8f547af7e9eaefdf8a39c8cebcba7c98858d3162bd28cf536f6 /uv /uvx /bin/

RUN apk add --no-cache \
    clamav \
    clamav-daemon \
    clamav-libunrar \
    freshclam \
    ca-certificates \
    tzdata \
    python3 \
    sqlite && \
    mkdir -p /app /var/lib/clamav /run/clamav /var/lib/fangfrisch /etc/fangfrisch && \
    chown -R clamav:clamav /app /var/lib/clamav /run/clamav /var/lib/fangfrisch /etc/fangfrisch

WORKDIR /app
# Pin uv to Alpine's system CPython and forbid interpreter downloads:
# requires-python >=3.12 is satisfied by the apk `python3`, so there's no
# need to fetch a ~30 MB python-build-standalone interpreter at build time.
ENV UV_PYTHON_DOWNLOADS=never \
    UV_PYTHON=/usr/bin/python3
COPY pyproject.toml uv.lock ./
# Buildah keeps this cache across builds without committing it to the image.
USER clamav
# Bytecode is compiled at build time (UV_COMPILE_BYTECODE, compileall):
# the containers run ReadOnly=true, so Python could never cache it and
# would recompile every import on each start.  SOURCE_DATE_EPOCH makes
# each .pyc hash-based instead of stamped with the source mtime,
# PYTHONHASHSEED fixes the order of set constants, so a rebuild hashes
# the same (image-content-hash.sh).
# Per RUN, never ENV: the services keep hash randomization at runtime.
RUN --mount=type=cache,id=uv-clamd,target=/tmp/uv-cache,uid=100,gid=101 \
    HOME=/tmp UV_CACHE_DIR=/tmp/uv-cache UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 SOURCE_DATE_EPOCH=0 PYTHONHASHSEED=0 \
    uv sync --frozen --no-dev --no-install-project
USER root

COPY clamd.conf /etc/clamav/clamd.conf
COPY freshclam.conf /etc/clamav/freshclam.conf
# fangfrisch.conf is written by entrypoint.sh from environment variables
# (SECURITEINFO_CUSTOMER_ID, MALWAREPATROL_RECEIPT) so secrets are not baked in.

EXPOSE 3310

COPY --chmod=0755 entrypoint.sh /entrypoint.sh
RUN test ! -d /tmp/uv-cache || test -z "$(ls -A /tmp/uv-cache)"

USER clamav
ENV PATH="/app/.venv/bin:$PATH"
ENTRYPOINT ["/entrypoint.sh"]
