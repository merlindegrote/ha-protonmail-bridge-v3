ARG BUILD_FROM
ARG BUILD_ARCH

# Runtime image provided by Home Assistant
FROM $BUILD_FROM

# Hydroxide version (open-source ProtonMail bridge, works on all architectures)
# Pure Go - no CGO, no libsecret, no dbus needed
ARG HYDROXIDE_VERSION="0.2.31"
ARG BUILD_ARCH

# Runtime files
COPY run.sh /

# Install hydroxide + runtime dependencies
# hydroxide is a pure-Go open-source ProtonMail bridge that works on arm/v7,
# aarch64 and amd64 without requiring libsecret or dbus.
# Ref: https://github.com/emersion/hydroxide
RUN mkdir -p /protonmail \
    && apk add --no-cache \
        socat \
        ca-certificates \
        git \
        go \
    && git clone --depth=1 --branch "v${HYDROXIDE_VERSION}" \
        https://github.com/emersion/hydroxide.git /tmp/hydroxide \
    && cd /tmp/hydroxide \
    && go build -o /protonmail/hydroxide ./cmd/hydroxide \
    && cd / \
    && rm -rf /tmp/hydroxide \
    && apk del go git \
    && chmod +x /protonmail/hydroxide \
    && chmod +x /run.sh

# Expose SMTP and IMAP ports
# hydroxide listens on 1025 (SMTP) and 1143 (IMAP) by default
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
    org.opencontainers.image.title="ProtonMail Bridge (hydroxide)" \
    org.opencontainers.image.description="ProtonMail Bridge for Home Assistant using hydroxide (armv7/aarch64/amd64)" \
    org.opencontainers.image.version="${BUILD_VERSION}" \
    org.opencontainers.image.source="https://github.com/merlindegrote/ha-protonmail-bridge-v3" \
    org.opencontainers.image.licenses="MIT"

CMD ["/run.sh"]
