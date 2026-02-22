ARG BUILD_FROM
ARG BUILD_ARCH

# Runtime image provided by Home Assistant
FROM $BUILD_FROM

# ProtonMail Bridge version
ARG PMB_VERSION="3.22.0"

# Runtime files
COPY run.sh /

# Install ProtonMail Bridge using official pre-built binaries
# amd64: uses official .deb package
# aarch64 / armv7: compile from source (no official arm binary available)
RUN apk add --no-cache \
    # Needed to extract .deb on Alpine
    dpkg \
    # For socat port forwarding
    socat \
    # Shared libs needed by bridge binary
    gcompat \
    libsecret \
    libc6-compat \
    ca-certificates \
    # For keychain/pass (secret storage)
    pass \
    gnupg \
    coreutils \
  && mkdir -p /protonmail \
  && ARCH=$(uname -m) \
  && if [ "$ARCH" = "x86_64" ]; then \
    echo "Downloading official ProtonMail Bridge amd64 .deb for v${PMB_VERSION}" \
    && wget -q -O /tmp/bridge.deb \
       "https://github.com/ProtonMail/proton-bridge/releases/download/v${PMB_VERSION}/protonmail-bridge_${PMB_VERSION}-1_amd64.deb" \
    && dpkg -x /tmp/bridge.deb /tmp/bridge-extracted \
    && cp /tmp/bridge-extracted/usr/bin/bridge /protonmail/proton-bridge \
    && rm -rf /tmp/bridge.deb /tmp/bridge-extracted; \
  elif [ "$ARCH" = "aarch64" ]; then \
    echo "No official arm64 binary available - building from source for aarch64" \
    && apk add --no-cache --virtual .build-deps \
         go \
         git \
         make \
         gcc \
         musl-dev \
         libsecret-dev \
    && git clone --depth=1 --branch "v${PMB_VERSION}" \
         https://github.com/ProtonMail/proton-bridge.git /tmp/proton-bridge \
    && cd /tmp/proton-bridge \
    && make build-nogui \
    && cp bridge /protonmail/proton-bridge \
    && cd / \
    && rm -rf /tmp/proton-bridge \
    && apk del .build-deps; \
  else \
    echo "Unsupported architecture: $ARCH" && exit 1; \
  fi \
  && chmod +x /protonmail/proton-bridge \
  && chmod +x /run.sh \
  # Persistent data directory symlinks (stored in /data which is mapped by HA add-on)
  && mkdir -p /data \
  && ln -sf /data/.cache /root/.cache \
  && ln -sf /data/.gnupg /root/.gnupg \
  && ln -sf /data/.password-store /root/.password-store \
  && ln -sf /data/.config /root/.config \
  && ln -sf /data/.local /root/.local

# Expose SMTP and IMAP ports
# ProtonMail Bridge v3.x uses port 1025 (SMTP) and 1143 (IMAP) internally
# socat will forward 25 -> 1025 and 143 -> 1143
EXPOSE 25/tcp
EXPOSE 143/tcp

WORKDIR /

SHELL ["/bin/bash", "-c"]

ENV LOG_TIMESTAMP "%F %T.%3N"

ARG BUILD_VERSION
LABEL \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.type="addon" \
    io.hass.arch="${BUILD_ARCH}" \
    maintainer="merlindegrote (fork of fboulay)" \
    org.opencontainers.image.title="ProtonMail Bridge v3" \
    org.opencontainers.image.description="ProtonMail Bridge v3.x for Home Assistant - uses official pre-built binaries" \
    org.opencontainers.image.version="${BUILD_VERSION}" \
    org.opencontainers.image.source="https://github.com/merlindegrote/ha-protonmail-bridge-v3" \
    org.opencontainers.image.licenses="MIT"

CMD ["bashio", "/run.sh"]
