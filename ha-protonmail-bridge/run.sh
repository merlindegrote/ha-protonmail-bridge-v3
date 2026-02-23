#!/usr/bin/env bash
# ProtonMail Bridge via hydroxide - HA Add-on run script
# All output also written to /data/debug.log for troubleshooting

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

echo "[$(date '+%F %T')] INFO: /data/options.json exists:"
cat "${OPTIONS_FILE}"

# Install jq if missing
if ! command -v jq &>/dev/null; then
  echo "[$(date '+%F %T')] INFO: Installing jq..."
  apk add --no-cache jq || true
fi

USERNAME=$(jq -r '.username // empty' "${OPTIONS_FILE}" 2>/dev/null)
PASSWORD=$(jq -r '.password // empty' "${OPTIONS_FILE}" 2>/dev/null)

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

# Check hydroxide binary
if [ ! -f "/protonmail/hydroxide" ]; then
  echo "[$(date '+%F %T')] ERROR: /protonmail/hydroxide not found!"
  ls -la /protonmail/ || true
  exit 1
fi

echo "[$(date '+%F %T')] INFO: hydroxide binary found:"
ls -la /protonmail/hydroxide
/protonmail/hydroxide --version 2>/dev/null || echo "(version flag not supported)"

# Set up data directory
mkdir -p /data/.config/hydroxide
export HOME=/data
export XDG_CONFIG_HOME=/data/.config
echo "[$(date '+%F %T')] INFO: Data directory: /data/.config/hydroxide"

AUTH_FILE="/data/.config/hydroxide/auth"
if [ -f "${AUTH_FILE}" ]; then
  echo "[$(date '+%F %T')] INFO: Existing auth found - starting bridge directly"
else
  echo "[$(date '+%F %T')] INFO: No auth found - authenticating..."
  echo "[$(date '+%F %T')] INFO: Running: hydroxide auth ${USERNAME}"

  # Run auth with credentials piped in (non-interactive)
  AUTH_OUTPUT=$(printf '%s\n%s\n' "${USERNAME}" "${PASSWORD}" | \
    /protonmail/hydroxide auth "${USERNAME}" 2>&1) || true

  echo "[$(date '+%F %T')] INFO: Auth output:"
  echo "${AUTH_OUTPUT}"
  echo "---"

  # Extract bridge password if present
  if echo "${AUTH_OUTPUT}" | grep -qi "bridge password"; then
    BRIDGE_PASS=$(echo "${AUTH_OUTPUT}" | grep -i "bridge password" | awk '{print $NF}')
    echo "[$(date '+%F %T')] =================================================="
    echo "[$(date '+%F %T')] BRIDGE PASSWORD: ${BRIDGE_PASS}"
    echo "[$(date '+%F %T')] Use this in IMAP/SMTP clients, NOT your PM password"
    echo "[$(date '+%F %T')] =================================================="
  fi

  if [ ! -f "${AUTH_FILE}" ]; then
    echo "[$(date '+%F %T')] WARNING: Auth file not created after auth attempt."
    echo "[$(date '+%F %T')] WARNING: Continuing anyway to try bridge start..."
  fi
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
