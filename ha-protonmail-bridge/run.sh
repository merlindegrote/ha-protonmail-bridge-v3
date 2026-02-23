#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# =============================================================================
# ProtonMail Bridge - Home Assistant Add-on run script (via hydroxide)
# =============================================================================
# hydroxide is a pure-Go, open-source ProtonMail bridge that works headlessly
# on all architectures (armv7, aarch64, amd64) without needing dbus/keyring.
# Ref: https://github.com/emersion/hydroxide
#
# HOW IT WORKS:
# 1. On first start, hydroxide authenticates with your ProtonMail credentials
#    and prints a "bridge password". This password is stored in /data.
# 2. hydroxide then serves SMTP on port 1025 and IMAP on port 1143 locally.
# 3. socat forwards port 25->1025 and 143->1143 for HA access.
# 4. Use the BRIDGE PASSWORD (from the logs) in HA SMTP config - NOT your
#    ProtonMail password.
# =============================================================================

log() { echo "[$(date '+%F %T')] $*" 1>&2; }
log_info() { log "INFO: $*"; }
log_warning() { log "WARNING: $*"; }
log_error() { log "ERROR: $*"; }

log_info "Starting ProtonMail Bridge add-on (via hydroxide)"

# --- Read config from /data/options.json (HA standard location) ---
OPTIONS_FILE="/data/options.json"
if [ ! -f "${OPTIONS_FILE}" ]; then
    log_error "/data/options.json not found! Cannot read configuration."
    exit 1
fi

if ! command -v jq &>/dev/null; then
    log_error "jq not found - installing..."
    apk add --no-cache jq || true
fi

USERNAME=$(jq -r '.username' "${OPTIONS_FILE}" 2>/dev/null || true)
PASSWORD=$(jq -r '.password' "${OPTIONS_FILE}" 2>/dev/null || true)

if [ -z "${USERNAME}" ] || [ "${USERNAME}" = "null" ]; then
    log_error "username is not configured in add-on options!"
    exit 1
fi
if [ -z "${PASSWORD}" ] || [ "${PASSWORD}" = "null" ]; then
    log_error "password is not configured in add-on options!"
    exit 1
fi

log_info "Username: ${USERNAME}"

# --- Persistent data directory ---
# hydroxide stores auth data in ~/.config/hydroxide/
mkdir -p /data/.config/hydroxide
export HOME=/data
export XDG_CONFIG_HOME=/data/.config

log_info "Data directory: /data/.config/hydroxide"

# --- Check if already authenticated ---
AUTH_FILE="/data/.config/hydroxide/auth"
if [ -f "${AUTH_FILE}" ]; then
    log_info "Existing hydroxide auth found - starting bridge directly"
else
    log_info "No auth found - authenticating with ProtonMail..."
    log_info "Username: ${USERNAME}"
    log_info ""
    log_info "Authenticating via hydroxide..."

    # hydroxide auth reads username/password from stdin
    printf '%s\n%s\n' "${USERNAME}" "${PASSWORD}" \
        | /protonmail/hydroxide auth "${USERNAME}" 2>&1 | tee /tmp/hydroxide_auth.log

    if grep -q "bridge password" /tmp/hydroxide_auth.log 2>/dev/null; then
        BRIDGE_PASS=$(grep "bridge password" /tmp/hydroxide_auth.log | awk '{print $NF}')
        log_info ""
        log_info "============================================================"
        log_info " BRIDGE PASSWORD: ${BRIDGE_PASS}"
        log_info " Use this password in Home Assistant SMTP config!"
        log_info " (NOT your ProtonMail account password)"
        log_info "============================================================"
        log_info ""
    else
        log_warning "Could not extract bridge password from auth output."
        log_warning "Check logs above for the bridge password."
    fi
fi

# --- Port forwarding via socat ---
log_info "Starting socat port forwarders (SMTP 25->1025, IMAP 143->1143)"
socat TCP-LISTEN:25,fork,reuseaddr TCP:127.0.0.1:1025 &
SOCAT_SMTP_PID=$!
socat TCP-LISTEN:143,fork,reuseaddr TCP:127.0.0.1:1143 &
SOCAT_IMAP_PID=$!

# --- Start hydroxide bridge ---
log_info "Launching hydroxide serve (SMTP + IMAP)"
log_info "SMTP available on port 25 (->1025)"
log_info "IMAP available on port 143 (->1143)"
log_info ""

set +o errexit
/protonmail/hydroxide serve 2>&1
EXIT_CODE=$?

log_error "hydroxide exited with code: ${EXIT_CODE}"
log_error ""
log_error "Troubleshooting:"
log_error " 1. Wrong credentials: correct username/password in add-on config"
log_error " 2. 2FA account: hydroxide may need interactive 2FA on first run"
log_error " 3. Delete /data/.config/hydroxide/auth to force re-authentication"

# Clean up socat
kill ${SOCAT_SMTP_PID} ${SOCAT_IMAP_PID} 2>/dev/null || true
exit ${EXIT_CODE}
