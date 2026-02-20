#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/borg_lib.sh"

load_env

LOG_DIR="${LOG_DIR:-/var/log/borg}"
LOG_RUN_DIR="${LOG_RUN_DIR:-${LOG_DIR}/runs}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-90}"

log "===== Borg Log Cleanup Started: $(date '+%a %d %b %Y %H:%M:%S %Z') ====="
log "Log directory: ${LOG_RUN_DIR}"
log "Retention (days): ${LOG_RETENTION_DAYS}"

if [ ! -d "${LOG_RUN_DIR}" ]; then
  log "Log directory does not exist; nothing to clean."
  exit 0
fi

if ! [[ "${LOG_RETENTION_DAYS}" =~ ^[0-9]+$ ]]; then
  log "ERROR: LOG_RETENTION_DAYS must be an integer; got '${LOG_RETENTION_DAYS}'."
  exit 1
fi

if [ "${LOG_RETENTION_DAYS}" -le 0 ]; then
  log "Retention set to ${LOG_RETENTION_DAYS}; skipping cleanup."
  exit 0
fi

set +e
DELETED=$(find "${LOG_RUN_DIR}" -type f -name '*.log' -mtime +"${LOG_RETENTION_DAYS}" -print -delete 2>/dev/null | wc -l | tr -d ' ')
set -e

log "Deleted ${DELETED} log files older than ${LOG_RETENTION_DAYS} days."
log "===== Borg Log Cleanup Finished: $(date '+%a %d %b %Y %H:%M:%S %Z') ====="
