# Global ARGs - must be declared before any FROM to be usable across all stages
ARG BUILD_FROM
ARG BUILD_ARCH

# Build stage: compile hydroxide for the target architecture
# Go supports cross-compilation natively - the builder always runs on amd64 (GHA)
# but produces binaries for the target platform via GOARCH/GOARM env vars.
# hydroxide 0.2.31 requires go >= 1.24
FROM --platform=$BUILDPLATFORM golang:1.24-alpine AS builder
ARG HYDROXIDE_VERSION="0.2.31"
ARG TARGETARCH
ARG TARGETVARIANT
# Build hydroxide - pure Go, CGO disabled for cross-compile
# Use printf+sh-safe substring extraction (${TARGETVARIANT#v} is bash-only)
RUN apk add --no-cache git ca-certificates \
 && git clone --depth=1 --branch "v${HYDROXIDE_VERSION}" \
 https://github.com/emersion/hydroxide.git /tmp/hydroxide \
 && cd /tmp/hydroxide \
 && GOARM=$(echo "${TARGETVARIANT}" | cut -c2-) \
 GOARCH=${TARGETARCH} CGO_ENABLED=0 \
 go build -ldflags='-s -w' -o /hydroxide ./cmd/hydroxide \
 && chmod +x /hydroxide

# Runtime stage: HA base image (armv7/aarch64/amd64 as specified by build.json)
FROM $BUILD_FROM
# Redeclare ARGs after FROM to make them available in this stage
ARG BUILD_ARCH
ARG BUILD_VERSION

# Override s6-overlay /init with a pass-through script.
# HA base images (3.x) use s6-overlay v3. With init: false in config.yaml,
# Docker no longer injects its own init. The image ENTRYPOINT is /init (s6).
# Our no-op /init simply exec's its arguments, so CMD (/run.sh) runs directly.
RUN printf '#!/bin/sh\nexec "$@"\n' > /init && chmod a+x /init

# Copy only the compiled hydroxide binary from the builder stage
RUN mkdir -p /protonmail
COPY --from=builder /hydroxide /protonmail/hydroxide
RUN chmod +x /protonmail/hydroxide

# Install runtime dependencies (socat for port forwarding, ca-certs for TLS)
RUN apk add --no-cache \
 socat \
 ca-certificates

# Runtime script
COPY run.sh /
RUN chmod +x /run.sh

# Expose SMTP and IMAP ports
# hydroxide: 1025 (SMTP), 1143 (IMAP)
# socat maps: 25->1025, 143->1143
EXPOSE 25/tcp
EXPOSE 143/tcp
WORKDIR /
SHELL ["/bin/bash", "-c"]
ENV LOG_TIMESTAMP "%F %T.%3N"
LABEL \
 io.hass.version="${BUILD_VERSION}" \
 io.hass.type="addon" \
 io.hass.arch="${BUILD_ARCH}" \
 maintainer="merlindegrote (fork of fboulay)" \
 org.opencontainers.image.title="ProtonMail Bridge (hydroxide)" \
 org.opencontainers.image.description="ProtonMail Bridge for HA using hydroxide (armv7/aarch64/amd64)" \
 org.opencontainers.image.version="${BUILD_VERSION}" \
 org.opencontainers.image.source="https://github.com/merlindegrote/ha-protonmail-bridge-v3" \
 org.opencontainers.image.licenses="MIT"
CMD ["/run.sh"]
