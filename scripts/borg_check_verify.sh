#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/borg_lib.sh"

JOB_NAME="check_verify"
load_env

############################################################
# Config (overridable via env)
############################################################
BORG_REPO="${BORG_REPO:-/tank/Secure/Borg/backup-repo}"
REPO_DATASET="${REPO_DATASET:-}"

LOG_DIR="${LOG_DIR:-/var/log/borg}"
LOG_RUN_DIR="${LOG_RUN_DIR:-${LOG_DIR}/runs}"

MAIL_TO="${MAIL_TO:-alerts@example.com}"
MAIL_FROM="${MAIL_FROM:-borg@localhost}"
MAIL_ON_SUCCESS="${MAIL_ON_SUCCESS:-true}"
MAIL_ON_FAILURE="${MAIL_ON_FAILURE:-true}"
MAIL_ON_SKIP="${MAIL_ON_SKIP:-true}"

require_passphrase
setup_logging "${JOB_NAME}"

RUN_START_EPOCH=$(date +%s)
RUN_START_HUMAN="$(date -Is)"
HOSTNAME="$(hostname)"

CHECK_EXIT=0
SKIPPED=0
SKIP_REASON=""

finalize() {
  local exit_code="$1"
  local run_end_epoch
  local run_end_human
  local run_duration
  local status
  local final_exit
  local warn_count
  local warn_lines
  local subject
  local body
  local attachment

  run_end_epoch=$(date +%s)
  run_end_human="$(date -Is)"
  run_duration=$(format_duration $((run_end_epoch - RUN_START_EPOCH)))

  if [ "${SKIPPED}" -eq 1 ]; then
    local skip_subject
    local skip_body
    local skip_reason

    skip_reason="${SKIP_REASON:-Unspecified skip reason}"
    skip_subject="[SKIP] Borg verify-data check on ${HOSTNAME}"
    skip_body=$(cat <<'EOF_BODY'
Borg Verify-Data Skipped
Host: __HOST__
Repository: __REPO__

Start: __START__
End: __END__
Duration: __DURATION__

Reason: __REASON__

Log: __LOG__
EOF_BODY
)
    skip_body=${skip_body//__HOST__/${HOSTNAME}}
    skip_body=${skip_body//__REPO__/${BORG_REPO}}
    skip_body=${skip_body//__START__/${RUN_START_HUMAN}}
    skip_body=${skip_body//__END__/${run_end_human}}
    skip_body=${skip_body//__DURATION__/${run_duration}}
    skip_body=${skip_body//__REASON__/${skip_reason}}
    skip_body=${skip_body//__LOG__/${RUN_LOG}}

    if is_enabled "${MAIL_ON_SKIP}"; then
      set +e
      send_mail "${skip_subject}" "${skip_body}"
      MAIL_EXIT=$?
      set -e
      if [ "${MAIL_EXIT}" -eq 0 ]; then
        log "Skip email notification sent."
      else
        log "WARNING: Skip email notification failed (exit ${MAIL_EXIT})."
      fi
    else
      log "Skip email suppressed (MAIL_ON_SKIP=false)"
    fi

    log "===== Borg Check --verify-data Skipped: $(date -Is) ====="
    exit 0
  fi

  status="OK"
  if [ "${exit_code}" -ne 0 ] || [ "${CHECK_EXIT}" -ge 2 ]; then
    status="FAIL"
  elif [ "${CHECK_EXIT}" -eq 1 ]; then
    status="WARN"
  fi

  final_exit=0
  if [ "${status}" != "OK" ]; then
    final_exit=1
  fi

  warn_count=$(count_matching '(WARNING|ERROR|Error:|CRITICAL|FAILED)' "${RUN_LOG}")
  warn_lines=$(collect_warnings "${RUN_LOG}" 30)
  if [ -z "${warn_lines}" ]; then
    warn_lines="None"
  fi

  subject="[${status}] Borg verify-data check on ${HOSTNAME}"
  body=$(cat <<'EOF_BODY'
Borg Verify-Data Summary
Status: __STATUS__
Host: __HOST__
Repository: __REPO__

Start: __START__
End: __END__
Duration: __DURATION__

Exit code: __CHECK_EXIT__

Warnings/Errors (__WARN_COUNT__):
__WARN_LINES__

Log: __LOG__
EOF_BODY
)
  body=${body//__STATUS__/${status}}
  body=${body//__HOST__/${HOSTNAME}}
  body=${body//__REPO__/${BORG_REPO}}
  body=${body//__START__/${RUN_START_HUMAN}}
  body=${body//__END__/${run_end_human}}
  body=${body//__DURATION__/${run_duration}}
  body=${body//__CHECK_EXIT__/${CHECK_EXIT}}
  body=${body//__WARN_COUNT__/${warn_count}}
  body=${body//__WARN_LINES__/${warn_lines}}
  body=${body//__LOG__/${RUN_LOG}}

  attachment=""
  if [ "${status}" != "OK" ]; then
    attachment="${RUN_LOG}"
  fi

  if [ "${status}" = "OK" ]; then
    if is_enabled "${MAIL_ON_SUCCESS}"; then
      set +e
      send_mail "${subject}" "${body}" "${attachment}"
      MAIL_EXIT=$?
      set -e
      if [ "${MAIL_EXIT}" -eq 0 ]; then
        log "Email notification sent: SUCCESS"
      else
        log "WARNING: Email notification failed (exit ${MAIL_EXIT})."
      fi
    else
      log "Success email suppressed (MAIL_ON_SUCCESS=false)"
    fi
  else
    if is_enabled "${MAIL_ON_FAILURE}"; then
      set +e
      send_mail "${subject}" "${body}" "${attachment}"
      MAIL_EXIT=$?
      set -e
      if [ "${MAIL_EXIT}" -eq 0 ]; then
        log "Email notification sent: FAILURE"
      else
        log "WARNING: Email notification failed (exit ${MAIL_EXIT})."
      fi
    else
      log "Failure email suppressed (MAIL_ON_FAILURE=false)"
    fi
  fi

  if [ "${status}" = "OK" ]; then
    log "===== Borg Check --verify-data Finished Successfully: $(date -Is) ====="
  else
    log "===== Borg Check --verify-data Finished With Errors: $(date -Is) ====="
  fi

  exit "${final_exit}"
}

trap 'finalize $?' EXIT

log "===== Borg Check --verify-data Started: ${RUN_START_HUMAN} ====="

############################################################
# Ensure repository location is reachable
############################################################
if [ -n "${REPO_DATASET}" ]; then
  if ! command -v zfs >/dev/null 2>&1; then
    skip_run "zfs command not found; skipping verify-data run."
  fi

  if ! zfs list -H -o name "${REPO_DATASET}" >/dev/null 2>&1; then
    skip_run "ZFS dataset ${REPO_DATASET} unavailable; skipping verify-data run."
  fi
fi

if ! require_mounted "${BORG_REPO}" "Borg repo parent"; then
  skip_run "Borg repo parent (${BORG_REPO}) not mounted; skipping verify-data run."
fi

if [ ! -d "${BORG_REPO}" ]; then
  skip_run "Borg repo ${BORG_REPO} unavailable; skipping verify-data run."
fi

############################################################
# Begin Borg Check --verify-data
############################################################
set +e
borg check --verify-data "${BORG_REPO}"
CHECK_EXIT=$?
set -e
