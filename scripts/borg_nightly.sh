#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/borg_lib.sh"

JOB_NAME="backup"
load_env

############################################################
# Config (overridable via env)
############################################################
ZFS_DATASET="${ZFS_DATASET:-tank/Secure/backup}"
SOURCE_PATH="${SOURCE_PATH:-/tank/Secure/backup}"
BORG_REPO="${BORG_REPO:-/tank/Secure/Borg/backup-repo}"
REPO_DATASET="${REPO_DATASET:-}"
ARCHIVE_PREFIX="${ARCHIVE_PREFIX:-backup}"

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
ARCHIVE_NAME="${ARCHIVE_PREFIX}-${HOSTNAME}-${RUN_ID}"
SNAP_NAME="${SNAP_NAME:-borg_${RUN_ID}}"

BORG_EXIT=0
PRUNE_EXIT=0
SNAP_EXIT=0
INFO_EXIT=0
SKIPPED=0
SKIP_REASON=""
SNAP_CREATED=0
SNAP_DESTROYED=0

CREATE_LOG=""
PRUNE_LOG=""
INFO_LOG=""

finalize() {
  local exit_code="$1"
  local run_end_epoch
  local run_end_human
  local run_duration
  local status
  local final_exit
  local warn_count
  local warn_lines
  local files
  local original_size
  local compressed_size
  local dedup_size
  local prune_keep
  local prune_prune
  local prune_deleted
  local subject
  local body
  local attachment

  run_end_epoch=$(date +%s)
  run_end_human="$(date -Is)"
  run_duration=$(format_duration $((run_end_epoch - RUN_START_EPOCH)))

  if [ "${SNAP_CREATED}" -eq 1 ] && [ "${SNAP_DESTROYED}" -eq 0 ]; then
    log "Destroying snapshot ${ZFS_DATASET}@${SNAP_NAME} (cleanup)"
    set +e
    zfs destroy -r "${ZFS_DATASET}@${SNAP_NAME}"
    if [ $? -eq 0 ]; then
      SNAP_DESTROYED=1
    else
      log "WARNING: Snapshot cleanup failed during exit handling."
    fi
    set -e
  fi

  if [ "${SKIPPED}" -eq 1 ]; then
    local skip_subject
    local skip_body
    local skip_reason

    skip_reason="${SKIP_REASON:-Unspecified skip reason}"
    skip_subject="[SKIP] Borg backup on ${HOSTNAME}"
    skip_body=$(cat <<'EOF_BODY'
Borg Backup Skipped
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

    log "===== Borg Backup Skipped: $(date -Is) ====="
    exit 0
  fi

  status="OK"
  if [ "${exit_code}" -ne 0 ] || [ "${SNAP_EXIT}" -ne 0 ] || [ "${BORG_EXIT}" -ge 2 ] || [ "${PRUNE_EXIT}" -ge 2 ]; then
    status="FAIL"
  elif [ "${BORG_EXIT}" -eq 1 ] || [ "${PRUNE_EXIT}" -eq 1 ]; then
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

  files="n/a"
  original_size="n/a"
  compressed_size="n/a"
  dedup_size="n/a"
  if [ -n "${INFO_LOG}" ] && [ -f "${INFO_LOG}" ]; then
    files=$(extract_value "Number of files" "${INFO_LOG}")
    original_size=$(extract_value "Original size" "${INFO_LOG}")
    compressed_size=$(extract_value "Compressed size" "${INFO_LOG}")
    dedup_size=$(extract_value "Deduplicated size" "${INFO_LOG}")
    files=${files:-n/a}
    original_size=${original_size:-n/a}
    compressed_size=${compressed_size:-n/a}
    dedup_size=${dedup_size:-n/a}
  fi

  prune_keep="n/a"
  prune_prune="n/a"
  prune_deleted="n/a"
  if [ -n "${PRUNE_LOG}" ] && [ -f "${PRUNE_LOG}" ]; then
    prune_keep=$(count_matching '^Keeping archive:' "${PRUNE_LOG}")
    prune_prune=$(count_matching '^Pruning archive:' "${PRUNE_LOG}")
    prune_deleted=$(extract_value "Deleted data" "${PRUNE_LOG}")
    prune_deleted=${prune_deleted:-n/a}
  fi

  subject="[${status}] Borg backup on ${HOSTNAME}"
  body=$(cat <<'EOF_BODY'
Borg Backup Summary
Status: __STATUS__
Host: __HOST__
Archive: __ARCHIVE__
Repository: __REPO__

Start: __START__
End: __END__
Duration: __DURATION__

Exit codes:
- borg create: __BORG_EXIT__
- borg prune: __PRUNE_EXIT__
- snapshot: __SNAP_EXIT__

Create stats:
- Files: __FILES__
- Original size: __ORIGINAL__
- Compressed size: __COMPRESSED__
- Deduplicated size: __DEDUP__

Prune stats:
- Kept: __KEPT__
- Pruned: __PRUNED__
- Deleted data: __DELETED__

Warnings/Errors (__WARN_COUNT__):
__WARN_LINES__

Log: __LOG__
EOF_BODY
)
  body=${body//__STATUS__/${status}}
  body=${body//__HOST__/${HOSTNAME}}
  body=${body//__ARCHIVE__/${ARCHIVE_NAME}}
  body=${body//__REPO__/${BORG_REPO}}
  body=${body//__START__/${RUN_START_HUMAN}}
  body=${body//__END__/${run_end_human}}
  body=${body//__DURATION__/${run_duration}}
  body=${body//__BORG_EXIT__/${BORG_EXIT}}
  body=${body//__PRUNE_EXIT__/${PRUNE_EXIT}}
  body=${body//__SNAP_EXIT__/${SNAP_EXIT}}
  body=${body//__FILES__/${files}}
  body=${body//__ORIGINAL__/${original_size}}
  body=${body//__COMPRESSED__/${compressed_size}}
  body=${body//__DEDUP__/${dedup_size}}
  body=${body//__KEPT__/${prune_keep}}
  body=${body//__PRUNED__/${prune_prune}}
  body=${body//__DELETED__/${prune_deleted}}
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

  rm -f "${CREATE_LOG}" "${PRUNE_LOG}" "${INFO_LOG}" 2>/dev/null || true

  if [ "${status}" = "OK" ]; then
    log "===== Borg Backup Finished Successfully: $(date -Is) ====="
  else
    log "===== Borg Backup Finished With Errors: $(date -Is) ====="
  fi

  exit "${final_exit}"
}

trap 'finalize $?' EXIT

log "===== Borg Backup Started: ${RUN_START_HUMAN} ====="

############################################################
# Ensure required datasets are mounted before running
############################################################
if ! command -v zfs >/dev/null 2>&1; then
  skip_run "zfs command not found; skipping run."
fi

if ! zfs list -H -o name "${ZFS_DATASET}" >/dev/null 2>&1; then
  skip_run "ZFS dataset ${ZFS_DATASET} unavailable; skipping run."
fi

if ! require_mounted "${SOURCE_PATH}" "Source path"; then
  skip_run "Source path (${SOURCE_PATH}) not mounted; skipping run."
fi

if ! sanity_check_source; then
  exit 1
fi

if [ -n "${REPO_DATASET}" ] && ! zfs list -H -o name "${REPO_DATASET}" >/dev/null 2>&1; then
  skip_run "ZFS dataset ${REPO_DATASET} unavailable; skipping run."
fi

if ! require_mounted "${BORG_REPO}" "Borg repo parent"; then
  skip_run "Borg repo parent (${BORG_REPO}) not mounted; skipping run."
fi

if [ ! -d "${BORG_REPO}" ]; then
  skip_run "Borg repo ${BORG_REPO} unavailable; skipping run."
fi

############################################################
# 1. Create ZFS Snapshot
############################################################
log "Creating snapshot ${ZFS_DATASET}@${SNAP_NAME}"
set +e
zfs snapshot -r "${ZFS_DATASET}@${SNAP_NAME}"
SNAP_EXIT=$?
set -e

if [ "${SNAP_EXIT}" -ne 0 ]; then
  log "ERROR: Failed to create snapshot (exit ${SNAP_EXIT})."
  exit 1
fi
SNAP_CREATED=1

############################################################
# 2. Run Borg Backup
############################################################
log "Running Borg backup: ${ARCHIVE_NAME}"
CREATE_LOG=$(mktemp)
set +e
borg create \
  --stats \
  --compression zstd,6 \
  "${BORG_REPO}::${ARCHIVE_NAME}" \
  "${SOURCE_PATH}" \
  --exclude "${SOURCE_PATH}/.zfs" \
  2>&1 | tee "${CREATE_LOG}"
BORG_EXIT=${PIPESTATUS[0]}
set -e

if [ "${BORG_EXIT}" -le 1 ]; then
  INFO_LOG=$(mktemp)
  set +e
  borg info "${BORG_REPO}::${ARCHIVE_NAME}" 2>&1 | tee "${INFO_LOG}"
  INFO_EXIT=${PIPESTATUS[0]}
  set -e

  if [ "${INFO_EXIT}" -ne 0 ]; then
    log "WARNING: borg info failed (exit ${INFO_EXIT})."
  fi
fi

############################################################
# 3. Prune Old Backups
############################################################
log "Pruning old Borg archives"
PRUNE_LOG=$(mktemp)
set +e
borg prune -v "${BORG_REPO}" \
  --list \
  --stats \
  --keep-daily=7 \
  --keep-weekly=4 \
  --keep-monthly=12 \
  2>&1 | tee "${PRUNE_LOG}"
PRUNE_EXIT=${PIPESTATUS[0]}
set -e

############################################################
# 4. Destroy ZFS Snapshot
############################################################
log "Destroying snapshot ${ZFS_DATASET}@${SNAP_NAME}"
set +e
zfs destroy -r "${ZFS_DATASET}@${SNAP_NAME}"
if [ $? -eq 0 ]; then
  SNAP_DESTROYED=1
else
  log "WARNING: Snapshot cleanup failed!"
fi
set -e
