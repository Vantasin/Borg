#!/usr/bin/env bash
set -euo pipefail

############################################################
# Optional env file load (services use EnvironmentFile)
############################################################
BORG_ENV_PATH=${BORG_ENV_PATH:-/usr/local/sbin/borg/borg.env}
if [ -z "${BORG_ENV_LOADED:-}" ] && [ -f "${BORG_ENV_PATH}" ]; then
  # shellcheck disable=SC1091
  source "${BORG_ENV_PATH}"
  BORG_ENV_LOADED=1
fi

LEGACY_BORG_ENV=${LEGACY_BORG_ENV:-/tank/Secure/Secrets/.borg_env}
if [ -z "${BORG_ENV_LOADED:-}" ] && [ -z "${BORG_PASSPHRASE:-}" ] && [ -f "${LEGACY_BORG_ENV}" ]; then
  # shellcheck disable=SC1091
  source "${LEGACY_BORG_ENV}"
  BORG_ENV_LOADED=1
fi

############################################################
# Config (overridable via env)
############################################################
BORG_REPO="${BORG_REPO:-/tank/Secure/Borg/backup-repo}"
REPO_DATASET="${REPO_DATASET:-}"

LOG_DIR="${LOG_DIR:-/var/log/borg}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/check_$(date +%F).log}"

MAIL_TO="${MAIL_TO:-alerts@example.com}"
MAIL_FROM="${MAIL_FROM:-borg@localhost}"

: "${BORG_PASSPHRASE:?BORG_PASSPHRASE is required}"

############################################################
# Prepare Logging
############################################################
mkdir -p "${LOG_DIR}"
exec >> "${LOG_FILE}" 2>&1

############################################################
# Ensure repository location is reachable
############################################################
require_mounted() {
  local path="$1"
  local label="$2"

  if command -v findmnt >/dev/null 2>&1; then
    if ! findmnt -T "${path}" >/dev/null 2>&1; then
      echo "${label} (${path}) not mounted; skipping check run."
      exit 0
    fi
  fi
}

if [ -n "${REPO_DATASET}" ]; then
  if ! command -v zfs >/dev/null 2>&1; then
    echo "zfs command not found; skipping check run."
    exit 0
  fi

  if ! zfs list -H -o name "${REPO_DATASET}" >/dev/null 2>&1; then
    echo "ZFS dataset ${REPO_DATASET} unavailable; skipping check run."
    exit 0
  fi
fi

require_mounted "${BORG_REPO}" "Borg repo parent"

if [ ! -d "${BORG_REPO}" ]; then
  echo "Borg repo ${BORG_REPO} unavailable; skipping check run."
  exit 0
fi

############################################################
# Email Helper (msmtp)
############################################################
send_mail() {
  local subject="$1"
  local body="$2"

  printf "From: %s\nTo: %s\nSubject: %s\n\n%s\n" \
    "${MAIL_FROM}" "${MAIL_TO}" "${subject}" "${body}" \
    | /usr/bin/msmtp -a default "${MAIL_TO}"
}

############################################################
# Begin Borg Check
############################################################
echo "===== Borg Check Started: $(date) ====="

# If you later want a heavy data-verify run, change this to:
#   borg check --verify-data "${BORG_REPO}"
# and maybe schedule it monthly instead.
set +e
borg check "${BORG_REPO}"
CHECK_EXIT=$?
set -e

############################################################
# Send Email Alert
############################################################
LOG_SNIPPET=$(tail -n 40 "${LOG_FILE}" 2>/dev/null || echo "No log content")

if [ ${CHECK_EXIT} -eq 0 ]; then
  send_mail \
    "[OK] Borg check on $(hostname)" \
    "Borg repository check completed successfully.

Host: $(hostname)
Time: $(date)

Log tail:
${LOG_SNIPPET}"

  echo "Email notification sent: SUCCESS"
  echo "===== Borg Check Finished Successfully: $(date) ====="
  exit 0
else
  send_mail \
    "[FAIL] Borg check on $(hostname)" \
    "Borg repository check FAILED.

Host: $(hostname)
Time: $(date)

borg check exit code: ${CHECK_EXIT}

Log tail:
${LOG_SNIPPET}"

  echo "Email notification sent: FAILURE"
  echo "===== Borg Check Finished With Errors: $(date) ====="
  exit 1
fi
