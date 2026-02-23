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
# Our run.sh is set as CMD. So /init -> exec $@ -> /run.sh
RUN printf '#!/bin/sh\nexec "$@"\n' > /init && chmod +x /init

# Copy the hydroxide binary from the builder stage
COPY --from=builder /hydroxide /protonmail/hydroxide

# Install runtime dependencies
RUN apk add --no-cache \
  socat \
  ca-certificates \
  jq \
  expect

# Copy scripts
COPY run.sh /run.sh
COPY run_auth.sh /run_auth.sh
COPY auth.expect /auth.expect
RUN chmod a+x /run.sh /run_auth.sh /auth.expect

# Labels
LABEL \
  io.hass.name="ProtonMail bridge" \
  io.hass.description="ProtonMail Bridge add-on for Home Assistant" \
  io.hass.arch="${BUILD_ARCH}" \
  io.hass.type="addon" \
  io.hass.version="${BUILD_VERSION}"

EXPOSE 25/tcp 143/tcp
CMD ["/run.sh"]
