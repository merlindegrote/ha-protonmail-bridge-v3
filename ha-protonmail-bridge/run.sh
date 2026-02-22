#!/usr/bin/env bashio
# =============================================================================
# ProtonMail Bridge v3.x - Home Assistant Add-on run script
# =============================================================================
# Bridge v3.x uses a gRPC API for authentication and stores credentials
# in a keystore. We use 'pass' (GPG-based) as the keystore provider,
# which works headlessly without dbus or gnome-keyring.
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

# Link persistent dirs into expected locations
export HOME=/data
export GNUPGHOME=/data/.gnupg
export PASSWORD_STORE_DIR=/data/.password-store
export XDG_CONFIG_HOME=/data/.config
export XDG_DATA_HOME=/data/.local/share
export XDG_CACHE_HOME=/data/.cache

bashio::log.info "Persistent data directories ready at /data"

# --- GPG key setup for 'pass' keystore ---
# Bridge v3.x requires a keystore to store its vault password.
# We use 'pass' with a passphrase-free GPG key, which works headlessly.
GPG_KEY_NAME="ProtonBridge"
GPG_KEY_ID=""

if gpg --homedir "${GNUPGHOME}" --list-keys "${GPG_KEY_NAME}" > /dev/null 2>&1; then
    bashio::log.info "Existing GPG key found for pass keystore"
    GPG_KEY_ID=$(gpg --homedir "${GNUPGHOME}" --list-keys --with-colons "${GPG_KEY_NAME}" \
        | grep '^pub' | cut -d: -f5)
else
    bashio::log.info "Generating new GPG key for pass keystore (no passphrase)..."
    gpg --homedir "${GNUPGHOME}" \
        --batch \
        --passphrase '' \
        --quick-gen-key "${GPG_KEY_NAME}" \
        default default never
    GPG_KEY_ID=$(gpg --homedir "${GNUPGHOME}" --list-keys --with-colons "${GPG_KEY_NAME}" \
        | grep '^pub' | cut -d: -f5)
    bashio::log.info "GPG key generated: ${GPG_KEY_ID}"
fi

# --- Initialize pass store ---
if [ ! -f "${PASSWORD_STORE_DIR}/.gpg-id" ]; then
    bashio::log.info "Initializing pass store with GPG key: ${GPG_KEY_ID}"
    pass init "${GPG_KEY_ID}"
else
    bashio::log.info "Pass store already initialized"
fi

# --- Port forwarding via socat ---
# Bridge v3.x listens on 127.0.0.1:1025 (SMTP) and 127.0.0.1:1143 (IMAP)
# socat exposes these on 0.0.0.0:25 and 0.0.0.0:143
bashio::log.info "Starting socat port forwarders (SMTP 25->1025, IMAP 143->1143)"
socat TCP-LISTEN:25,fork,reuseaddr TCP:127.0.0.1:1025 &
SOCAT_SMTP_PID=$!
socat TCP-LISTEN:143,fork,reuseaddr TCP:127.0.0.1:1143 &
SOCAT_IMAP_PID=$!

# --- Start ProtonMail Bridge ---
bashio::log.info "Launching ProtonMail Bridge v3 (--noninteractive)"
bashio::log.info "Username: ${USERNAME}"
bashio::log.info ""
bashio::log.info "IMPORTANT: On first run, Bridge initializes its vault."
bashio::log.info "After successful start, find the Bridge SMTP password in the logs."
bashio::log.info "Use THAT password (not your ProtonMail password) in HA SMTP config."
bashio::log.info ""

set +o errexit
/protonmail/proton-bridge --noninteractive 2>&1
EXIT_CODE=$?

bashio::log.error "ProtonMail Bridge exited with code: ${EXIT_CODE}"
bashio::log.error "Check the output above for errors."
bashio::log.error ""
bashio::log.error "Troubleshooting:"
bashio::log.error " 1. First run: restart the add-on once to let Bridge initialize"
bashio::log.error " 2. Check username/password in add-on config"
bashio::log.error " 3. 2FA accounts: create an app password in ProtonMail settings"

# Clean up socat
kill ${SOCAT_SMTP_PID} ${SOCAT_IMAP_PID} 2>/dev/null || true
exit ${EXIT_CODE}
