ARG BUILD_FROM
ARG BUILD_ARCH

# Runtime image provided by Home Assistant
FROM $BUILD_FROM

# ProtonMail Bridge version
ARG PMB_VERSION="3.22.0"
ARG BUILD_ARCH

# Runtime files
COPY run.sh /

# Install runtime dependencies + ProtonMail Bridge
# amd64:   uses official pre-built .deb binary from Proton
# aarch64: compiles from source (no official ARM binary available)
RUN mkdir -p /protonmail \
    && apk add --no-cache \
        socat \
        ca-certificates \
        gnupg \
        gnupg-keyboxd \
        gpg-agent \
        pass \
        coreutils \
        libgcc \
        gcompat \
        libc6-compat \
    && ARCH=$(cat /etc/apk/arch 2>/dev/null || echo "unknown") \
    && echo "Building for architecture: ${ARCH}" \
    && if [ "${BUILD_ARCH}" = "amd64" ]; then \
        echo "amd64: Installing pre-built binary" \
        && apk add --no-cache dpkg wget \
        && wget -q -O /tmp/bridge.deb \
            "https://github.com/ProtonMail/proton-bridge/releases/download/v${PMB_VERSION}/protonmail-bridge_${PMB_VERSION}-1_amd64.deb" \
        && dpkg -x /tmp/bridge.deb /tmp/bridge-extracted \
        && cp /tmp/bridge-extracted/usr/bin/bridge /protonmail/proton-bridge \
        && rm -rf /tmp/bridge.deb /tmp/bridge-extracted; \
    elif [ "${BUILD_ARCH}" = "aarch64" ]; then \
        echo "aarch64: Building from source" \
        && apk add --no-cache --virtual .build-deps \
            go \
            git \
            make \
            gcc \
            musl-dev \
            pkg-config \
            libsecret-dev \
        && git clone --depth=1 --branch "v${PMB_VERSION}" \
            https://github.com/ProtonMail/proton-bridge.git /tmp/proton-bridge \
        && cd /tmp/proton-bridge \
        && CGO_ENABLED=1 CGO_CFLAGS="-D_LARGEFILE64_SOURCE" make build-nogui \
        && cp bridge /protonmail/proton-bridge \
        && cd / \
        && rm -rf /tmp/proton-bridge \
        && apk del .build-deps; \
    else \
        echo "Unsupported architecture: ${BUILD_ARCH}" && exit 1; \
    fi \
    && chmod +x /protonmail/proton-bridge \
    && chmod +x /run.sh

# Expose SMTP and IMAP ports
# Bridge v3.x listens on 127.0.0.1:1025 (SMTP) and 127.0.0.1:1143 (IMAP)
# socat forwards 25->1025 and 143->1143
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
    org.opencontainers.image.description="ProtonMail Bridge v3.x for Home Assistant" \
    org.opencontainers.image.version="${BUILD_VERSION}" \
    org.opencontainers.image.source="https://github.com/merlindegrote/ha-protonmail-bridge-v3" \
    org.opencontainers.image.licenses="MIT"

CMD ["/run.sh"]
