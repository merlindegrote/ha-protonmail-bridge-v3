#!/usr/bin/env bash
# Non-interactive hydroxide auth runner (no /dev/tty)
# Reads credentials from /data/options.json or env overrides.

set -euo pipefail

OPTIONS_FILE="/data/options.json"
LOG_FILE="/data/hydroxide-auth.log"
CRED_FILE="/data/bridge_credentials.json"

umask 077
mkdir -p /data/.config/hydroxide
export HOME=/data
export XDG_CONFIG_HOME=/data/.config

# Start a fresh log for each auth run
: > "${LOG_FILE}"

log() {
  echo "[$(date '+%F %T')] $*" | tee -a "${LOG_FILE}"
}

log_err() {
  echo "[$(date '+%F %T')] ERROR: $*" | tee -a "${LOG_FILE}" >&2
}

read_opt() {
  local query="$1"
  if command -v jq >/dev/null 2>&1 && [ -f "${OPTIONS_FILE}" ]; then
    jq -r "${query} // empty" "${OPTIONS_FILE}" 2>/dev/null || true
  fi
}

USERNAME="${PM_USERNAME:-$(read_opt '.username')}"
PASSWORD="${PM_PASSWORD:-$(read_opt '.password')}"
TOTP_CODE="${PM_TOTP:-$(read_opt '.totp_code')}"
MAILBOX_PASSWORD="${PM_MAILBOX_PASSWORD:-$(read_opt '.mailbox_password')}"
DEBUG_AUTH="${PM_DEBUG_AUTH:-$(read_opt '.debug_auth')}"

if [ -z "${USERNAME}" ]; then
  log_err "username not configured"
  exit 1
fi
if [ -z "${PASSWORD}" ]; then
  log_err "password not configured"
  exit 1
fi

if [ ! -x "/protonmail/hydroxide" ]; then
  log_err "/protonmail/hydroxide not found or not executable"
  exit 1
fi
if [ ! -f "/auth.expect" ]; then
  log_err "/auth.expect not found"
  exit 1
fi

if [ "${DEBUG_AUTH}" = "true" ] || [ "${DEBUG_AUTH}" = "1" ]; then
  DEBUG_AUTH=1
else
  DEBUG_AUTH=0
fi

if [ ${DEBUG_AUTH} -eq 1 ]; then
  log "Auth debug enabled: extra details in normal add-on logs"
fi

log "Starting hydroxide auth for ${USERNAME}"

set +e
PMPASSWORD="${PASSWORD}" PMTOTP="${TOTP_CODE}" PMMAILBOX="${MAILBOX_PASSWORD}" PMDEBUG_AUTH="${DEBUG_AUTH}" \
  /auth.expect "${USERNAME}" 2>&1 | tee -a "${LOG_FILE}"
EXPECT_EXIT=${PIPESTATUS[0]}
set -e

if [ ${EXPECT_EXIT} -ne 0 ]; then
  log_err "hydroxide auth failed (expect exit ${EXPECT_EXIT})"
  exit ${EXPECT_EXIT}
fi

if grep -Fq "[8002]" "${LOG_FILE}" || grep -qi "password is not correct" "${LOG_FILE}"; then
  log_err "ProtonMail rejected the password ([8002])"
  exit 2
fi

BRIDGE_PASS=$(grep -i -E "bridge password|imap/smtp password|imap password|smtp password" "${LOG_FILE}" \
  | tail -n 1 \
  | sed -E 's/.*: *//; s/\r//g; s/[^A-Za-z0-9+\/=].*$//')

if [ -z "${BRIDGE_PASS}" ]; then
  BRIDGE_PASS=$(grep -Eo "[A-Za-z0-9+\/=]{20,}" "${LOG_FILE}" | tail -n 1)
fi

if [ -z "${BRIDGE_PASS}" ]; then
  log_err "bridge password not found in hydroxide output"
  exit 3
fi

log "BRIDGE PASSWORD: ${BRIDGE_PASS}"
log "Use this in IMAP/SMTP clients (not your ProtonMail account password)"

IMAP_HOST="${IMAP_HOST:-127.0.0.1}"
IMAP_PORT="${IMAP_PORT:-1143}"
SMTP_HOST="${SMTP_HOST:-127.0.0.1}"
SMTP_PORT="${SMTP_PORT:-1025}"

cat > "${CRED_FILE}" <<EOF
{
  "username": "${USERNAME}",
  "bridge_password": "${BRIDGE_PASS}",
  "imap": {
    "host": "${IMAP_HOST}",
    "port": ${IMAP_PORT},
    "tls": false
  },
  "smtp": {
    "host": "${SMTP_HOST}",
    "port": ${SMTP_PORT},
    "tls": false
  },
  "forwarded_ports": {
    "imap": 143,
    "smtp": 25
  },
  "generated_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF

log "Bridge credentials saved to ${CRED_FILE}"
