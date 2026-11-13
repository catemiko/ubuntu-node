# syntax=docker/dockerfile:1
# Ubuntu 24.04 Chisel slices + Node.js 24 + Canonical Pebble as container PID 1.
# This is a Node runtime image, not a repackage of ubuntu/python or Debian.
ARG UBUNTU_VERSION="24.04"

FROM ubuntu:${UBUNTU_VERSION} AS chiseled-rootfs
ARG UBUNTU_VERSION="24.04"
ARG CHISEL_VERSION="v1.5.1"
ARG PEBBLE_VERSION="v1.33.2"
ARG TARGETARCH="amd64"
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# Chisel release is pinned and authenticated with its published SHA384 file.
RUN set -eux; \
    filename="chisel_${CHISEL_VERSION}_linux_${TARGETARCH}.tar.gz"; \
    base="https://github.com/canonical/chisel/releases/download/${CHISEL_VERSION}"; \
    curl --fail --show-error --silent --location --retry 5 -O "${base}/${filename}"; \
    curl --fail --show-error --silent --location --retry 5 -O "${base}/${filename}.sha384"; \
    sha384sum --check "${filename}.sha384"; \
    tar -xzf "${filename}" -C /usr/local/bin chisel; \
    chmod 0755 /usr/local/bin/chisel; \
    rm "${filename}" "${filename}.sha384"

# Chisel requires the destination root to exist before extracting base-files.
# OS packages and libraries originate from Noble, not from Debian layers.
RUN mkdir -p /rootfs && \
    chisel cut --release "ubuntu-${UBUNTU_VERSION}" --root /rootfs \
      base-files_base \
      base-files_release-info \
      base-files_chisel \
      libc6_libs \
      libgcc-s1_libs \
      libstdc++6_libs \
      libatomic1_libs \
      ca-certificates_data \
      tzdata_zoneinfo

# User identity follows Canonical's ubuntu/python rock convention.
RUN mkdir -p /rootfs/etc /rootfs/tmp && \
    printf '_daemon_:x:584792:584792::/tmp:/usr/sbin/nologin\n' > /rootfs/etc/passwd && \
    printf '_daemon_:x:584792:\n' > /rootfs/etc/group && \
    chmod 1777 /rootfs/tmp

# Pebble release archives and SHA256s from the pinned canonical/pebble release.
# Per-arch checksum verification ensures the correct published artifact is used.
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) pebble_sha256='e9d84f9e461a89abb4437af26a784917bd85cf1612c8de142a3b4449dff332d0' ;; \
      arm64) pebble_sha256='0c19a80498da84e5615138bf804c85b782438c515832430fef8d40057418b4eb' ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    filename="pebble_${PEBBLE_VERSION}_linux_${TARGETARCH}.tar.gz"; \
    url="https://github.com/canonical/pebble/releases/download/${PEBBLE_VERSION}/${filename}"; \
    curl --fail --show-error --silent --location --retry 5 -o "/tmp/${filename}" "${url}"; \
    printf '%s  %s\n' "${pebble_sha256}" "/tmp/${filename}" | sha256sum --check -; \
    mkdir -p /rootfs/usr/bin /rootfs/usr/share/pebble/layers /rootfs/var/lib/pebble/default; \
    tar -xzf "/tmp/${filename}" -C /rootfs/usr/bin pebble; \
    chmod 0755 /rootfs/usr/bin/pebble; \
    chown 584792:584792 /rootfs/var/lib/pebble/default; \
    chmod 0700 /rootfs/var/lib/pebble/default; \
    rm -f "/tmp/${filename}"

FROM node:24-bookworm-slim AS node24

FROM scratch
LABEL org.opencontainers.image.title="Ubuntu 24.04 Chiseled Node.js 24 with Pebble" \
      org.opencontainers.image.description="Minimal non-root Noble Node 24 runtime; Canonical Pebble as PID 1" \
      org.opencontainers.image.vendor="Community-built (not an official Canonical rock)"
COPY --from=chiseled-rootfs /rootfs/ /
COPY --from=node24 /usr/local/bin/node /usr/local/bin/node
ENV NODE_ENV="production" \
    HOME="/tmp" \
    PATH="/usr/local/bin:/usr/bin:/bin" \
    SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt" \
    PEBBLE="/var/lib/pebble/default" \
    PEBBLE_COPY_ONCE="/usr/share/pebble" \
    PEBBLE_SOCKET="/tmp/.pebble.socket" \
    PEBBLE_PERSIST="never" \
    PEBBLE_VERBOSE="1"
WORKDIR /app
USER _daemon_:_daemon_
# With no CMD, no service runs until an application layer is supplied.
ENTRYPOINT ["/usr/bin/pebble", "enter"]
