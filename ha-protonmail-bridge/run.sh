#!/usr/bin/env bashio
# =============================================================================
# ProtonMail Bridge - Home Assistant Add-on run script (via hydroxide)
# =============================================================================
# hydroxide is a pure-Go, open-source ProtonMail bridge that works headlessly
# on all architectures (armv7, aarch64, amd64) without needing dbus/keyring.
# Ref: https://github.com/emersion/hydroxide
#
# HOW IT WORKS:
# 1. On first start, hydroxide authenticates with your ProtonMail credentials
#    and prints a "bridge password". This password is stored encrypted in /data.
# 2. hydroxide then serves SMTP on port 1025 and IMAP on port 1143 locally.
# 3. socat forwards port 25->1025 and 143->1143 for HA access.
# 4. Use the BRIDGE PASSWORD (from the logs) in HA SMTP config - NOT your
#    ProtonMail password.
# =============================================================================

bashio::log.info "Starting ProtonMail Bridge add-on (via hydroxide)"

# --- Validate required config ---
bashio::config.require username
bashio::config.require password

USERNAME=$(bashio::config 'username')
PASSWORD=$(bashio::config 'password')

# --- Persistent data directory ---
# hydroxide stores auth data in ~/.config/hydroxide/
mkdir -p /data/.config/hydroxide
export HOME=/data
export XDG_CONFIG_HOME=/data/.config

bashio::log.info "Data directory: /data/.config/hydroxide"

# --- Check if already authenticated ---
AUTH_FILE="/data/.config/hydroxide/auth"

if [ -f "${AUTH_FILE}" ]; then
    bashio::log.info "Existing hydroxide auth found - starting bridge directly"
else
    bashio::log.info "No auth found - authenticating with ProtonMail..."
    bashio::log.info "Username: ${USERNAME}"
    bashio::log.info ""
    bashio::log.info "Authenticating via hydroxide..."

    # hydroxide auth reads username/password and optionally 2FA from stdin
    # Format: username\npassword\n (2FA prompt will follow if needed)
    printf '%s\n%s\n' "${USERNAME}" "${PASSWORD}" \
        | /protonmail/hydroxide auth "${USERNAME}" 2>&1 | tee /tmp/hydroxide_auth.log

    if grep -q "bridge password" /tmp/hydroxide_auth.log 2>/dev/null; then
        BRIDGE_PASS=$(grep "bridge password" /tmp/hydroxide_auth.log | awk '{print $NF}')
        bashio::log.info ""
        bashio::log.info "============================================================"
        bashio::log.info " BRIDGE PASSWORD: ${BRIDGE_PASS}"
        bashio::log.info " Use this password in Home Assistant SMTP config!"
        bashio::log.info " (NOT your ProtonMail account password)"
        bashio::log.info "============================================================"
        bashio::log.info ""
    else
        bashio::log.warning "Could not extract bridge password from auth output."
        bashio::log.warning "Check logs above for the bridge password."
    fi
fi

# --- Port forwarding via socat ---
bashio::log.info "Starting socat port forwarders (SMTP 25->1025, IMAP 143->1143)"
socat TCP-LISTEN:25,fork,reuseaddr TCP:127.0.0.1:1025 &
SOCAT_SMTP_PID=$!
socat TCP-LISTEN:143,fork,reuseaddr TCP:127.0.0.1:1143 &
SOCAT_IMAP_PID=$!

# --- Start hydroxide bridge ---
bashio::log.info "Launching hydroxide serve (SMTP + IMAP)"
bashio::log.info "SMTP available on port 25 (->1025)"
bashio::log.info "IMAP available on port 143 (->1143)"
bashio::log.info ""

set +o errexit
/protonmail/hydroxide serve 2>&1
EXIT_CODE=$?

bashio::log.error "hydroxide exited with code: ${EXIT_CODE}"
bashio::log.error ""
bashio::log.error "Troubleshooting:"
bashio::log.error " 1. Wrong credentials: correct username/password in add-on config"
bashio::log.error " 2. 2FA account: hydroxide may need interactive 2FA on first run"
bashio::log.error " 3. Delete /data/.config/hydroxide/auth to force re-authentication"

# Clean up socat
kill ${SOCAT_SMTP_PID} ${SOCAT_IMAP_PID} 2>/dev/null || true
exit ${EXIT_CODE}
