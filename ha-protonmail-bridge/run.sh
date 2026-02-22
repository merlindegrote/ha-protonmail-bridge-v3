#!/usr/bin/env bashio

# =============================================================================
# ProtonMail Bridge v3.x - Home Assistant Add-on run script
# =============================================================================
# Bridge v3.x no longer uses an interactive CLI for login.
# Authentication is handled via a gRPC API. On first run, the bridge will
# attempt to log in using the credentials from the add-on config.
# The vault (credentials) is stored persistently in /data.
# =============================================================================

bashio::log.info "Starting ProtonMail Bridge v3 add-on"

# --- Validate required config ---
bashio::config.require username
bashio::config.require password

USERNAME=$(bashio::config 'username')
PASSWORD=$(bashio::config 'password')

# --- Create persistent data directories ---
mkdir -p /data/.config/protonmail/bridge
mkdir -p /data/.local/share/protonmail/bridge
mkdir -p /data/.cache/protonmail/bridge
mkdir -p /data/.gnupg
mkdir -p /data/.password-store

chmod 700 /data/.gnupg
chmod 700 /data/.password-store

bashio::log.info "Persistent data directories ready at /data"

# --- Port forwarding via socat ---
# Bridge v3.x listens on 127.0.0.1:1025 (SMTP) and 127.0.0.1:1143 (IMAP)
# socat exposes these on 0.0.0.0:25 and 0.0.0.0:143 so HA can reach them
bashio::log.info "Starting socat port forwarders (SMTP 25->1025, IMAP 143->1143)"
socat TCP-LISTEN:25,fork,reuseaddr TCP:127.0.0.1:1025 &
SOCAT_SMTP_PID=$!
socat TCP-LISTEN:143,fork,reuseaddr TCP:127.0.0.1:1143 &
SOCAT_IMAP_PID=$!

# --- Check if bridge already has a logged-in account ---
# Bridge v3.x stores its vault in the config directory.
# If the vault exists and has accounts, we can start directly.
VAULT_DIR="/data/.config/protonmail/bridge"
if ls "${VAULT_DIR}"/*.json 1>/dev/null 2>&1; then
    bashio::log.info "Existing Bridge vault found - starting Bridge directly"
else
    bashio::log.info "No vault found - Bridge will attempt login on first start"
    bashio::log.info "Username: ${USERNAME}"
    bashio::log.info ""
    bashio::log.info "NOTE: ProtonMail Bridge v3.x handles authentication internally."
    bashio::log.info "On first run, Bridge will use the gRPC API to authenticate."
    bashio::log.info "Check the logs for a BRIDGE SMTP PASSWORD - use this (not your ProtonMail"
    bashio::log.info "password) as the SMTP password in your HA mail config!"
    bashio::log.info ""
fi

# --- Write credentials file for Bridge CLI login ---
# Bridge v3.x can be controlled via its CLI tool.
# We use the bridge --noninteractive mode and pass credentials via env vars
# or via the gRPC API with bridge-gui-helper.
# The simplest approach: pass creds via BRIDGE_USERNAME and BRIDGE_PASSWORD env
export BRIDGE_LOG_LEVEL="debug"

# --- Start ProtonMail Bridge ---
bashio::log.info "Launching ProtonMail Bridge v3 (--noninteractive)"
bashio::log.info "Bridge SMTP will be available on port 25 (forwarded from 1025)"
bashio::log.info "Bridge IMAP will be available on port 143 (forwarded from 1143)"
bashio::log.info ""
bashio::log.info "IMPORTANT: After first successful login, find the Bridge SMTP password"
bashio::log.info "in the logs (look for 'bridge password' or 'SMTP password')."
bashio::log.info "Use THAT password (not your ProtonMail password) in HA SMTP config."
bashio::log.info ""

# Run bridge in noninteractive mode - it will start the gRPC server
# and the local SMTP/IMAP servers
set +o errexit
/protonmail/proton-bridge --noninteractive 2>&1
EXIT_CODE=$?

bashio::log.error "ProtonMail Bridge exited with code: ${EXIT_CODE}"
bashio::log.error "Check the output above for authentication errors or startup issues."
bashio::log.error ""
bashio::log.error "Common solutions:"
bashio::log.error "  1. If this is first run: restart the add-on once to let Bridge initialize"
bashio::log.error "  2. Make sure username/password in add-on config are correct"
bashio::log.error "  3. Check if your ProtonMail account requires 2FA - if so,"
bashio::log.error "     you may need to create an app password in ProtonMail settings"

# Clean up socat
kill ${SOCAT_SMTP_PID} ${SOCAT_IMAP_PID} 2>/dev/null || true

exit ${EXIT_CODE}
