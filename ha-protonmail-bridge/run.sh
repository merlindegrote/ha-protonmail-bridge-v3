#!/usr/bin/env bash
# ProtonMail Bridge via hydroxide - HA Add-on run script
# Uses /auth.expect for non-interactive authentication (no /dev/tty needed)

DEBUG_LOG="/data/debug.log"
exec > >(tee -a "${DEBUG_LOG}") 2>&1

echo "[$(date '+%F %T')] === Starting ProtonMail Bridge add-on ==="

# --- Read config ---
OPTIONS_FILE="/data/options.json"
if [ ! -f "${OPTIONS_FILE}" ]; then
  echo "[$(date '+%F %T')] ERROR: /data/options.json not found!"
  ls -la /data/ || true
  exit 1
fi

echo "[$(date '+%F %T')] INFO: /data/options.json exists"

USERNAME=$(jq -r '.username // empty' "${OPTIONS_FILE}" 2>/dev/null)
PASSWORD=$(jq -r '.password // empty' "${OPTIONS_FILE}" 2>/dev/null)
# Optional: TOTP code for 2FA accounts (leave empty if no 2FA)
TOTP_CODE=$(jq -r '.totp_code // empty' "${OPTIONS_FILE}" 2>/dev/null)
# Optional: mailbox password for two-password mode accounts
MAILBOX_PASSWORD=$(jq -r '.mailbox_password // empty' "${OPTIONS_FILE}" 2>/dev/null)

if [ -z "${USERNAME}" ]; then
  echo "[$(date '+%F %T')] ERROR: username not configured!"
  exit 1
fi
if [ -z "${PASSWORD}" ]; then
  echo "[$(date '+%F %T')] ERROR: password not configured!"
  exit 1
fi

echo "[$(date '+%F %T')] INFO: Username: ${USERNAME}"
echo "[$(date '+%F %T')] INFO: Password length: ${#PASSWORD}"
[ -n "${TOTP_CODE}" ] && echo "[$(date '+%F %T')] INFO: TOTP code provided (2FA mode)"
[ -n "${MAILBOX_PASSWORD}" ] && echo "[$(date '+%F %T')] INFO: Mailbox password provided (two-password mode)"

# Check hydroxide binary
if [ ! -f "/protonmail/hydroxide" ]; then
  echo "[$(date '+%F %T')] ERROR: /protonmail/hydroxide not found!"
  ls -la /protonmail/ || true
  exit 1
fi

# Check expect script
if [ ! -f "/auth.expect" ]; then
  echo "[$(date '+%F %T')] ERROR: /auth.expect not found!"
  exit 1
fi

# Set up data directory
mkdir -p /data/.config/hydroxide
export HOME=/data
export XDG_CONFIG_HOME=/data/.config

AUTH_FILE="/data/.config/hydroxide/auth.json"
CRED_FILE="/data/bridge_credentials.json"

FORCE_AUTH="${FORCE_AUTH:-}"
if [ -z "${FORCE_AUTH}" ]; then
  FORCE_AUTH=$(jq -r '.force_auth // empty' "${OPTIONS_FILE}" 2>/dev/null)
fi
if [ "${FORCE_AUTH}" = "true" ] || [ "${FORCE_AUTH}" = "1" ]; then
  FORCE_AUTH=1
else
  FORCE_AUTH=0
fi

if [ ${FORCE_AUTH} -eq 0 ] && [ -s "${CRED_FILE}" ] && jq -e '.bridge_password' "${CRED_FILE}" >/dev/null 2>&1; then
  # Check if username matches - if not, re-authenticate
  STORED_USERNAME=$(jq -r '.username // empty' "${CRED_FILE}" 2>/dev/null)
  if [ "${STORED_USERNAME}" = "${USERNAME}" ]; then
    echo "[$(date '+%F %T')] INFO: bridge_credentials.json found - skipping auth"
  else
    echo "[$(date '+%F %T')] INFO: Username changed - re-authenticating..."
    rm -f "${CRED_FILE}"
    FORCE_AUTH=1
  fi
fi

if [ ${FORCE_AUTH} -eq 1 ] || [ ! -f "${CRED_FILE}" ]; then
  if [ ${FORCE_AUTH} -eq 1 ]; then
    echo "[$(date '+%F %T')] INFO: Force auth requested"
  fi
  echo "[$(date '+%F %T')] INFO: Running non-interactive auth..."
  /run_auth.sh
fi

if [ -f "${AUTH_FILE}" ]; then
  echo "[$(date '+%F %T')] INFO: Auth file present - starting bridge"
else
  echo "[$(date '+%F %T')] WARNING: Auth file not created. Starting hydroxide anyway"
fi

# Start socat port forwarders
echo "[$(date '+%F %T')] INFO: Starting socat forwarders..."
if command -v socat &>/dev/null; then
  socat TCP-LISTEN:25,fork,reuseaddr TCP:127.0.0.1:1025 &
  SOCAT_SMTP=$!
  socat TCP-LISTEN:143,fork,reuseaddr TCP:127.0.0.1:1143 &
  SOCAT_IMAP=$!
  echo "[$(date '+%F %T')] INFO: socat SMTP PID=${SOCAT_SMTP}, IMAP PID=${SOCAT_IMAP}"
else
  echo "[$(date '+%F %T')] WARNING: socat not found, ports 25/143 not forwarded"
fi

# Start hydroxide serve
echo "[$(date '+%F %T')] INFO: Starting hydroxide serve..."
echo "[$(date '+%F %T')] INFO: SMTP on port 25 (->1025), IMAP on port 143 (->1143)"
/protonmail/hydroxide serve 2>&1
EXIT_CODE=$?
echo "[$(date '+%F %T')] ERROR: hydroxide exited with code: ${EXIT_CODE}"
kill ${SOCAT_SMTP:-0} ${SOCAT_IMAP:-0} 2>/dev/null || true
exit ${EXIT_CODE}
