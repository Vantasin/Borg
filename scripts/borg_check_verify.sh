#!/usr/bin/env bash
set -euo pipefail

# Monthly data verification (borg check --verify-data) with structured email summary.

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
BORG_LOCK_WAIT="${BORG_LOCK_WAIT:-3600}"

LOG_DIR="${LOG_DIR:-/var/log/borg}"
LOG_RUN_DIR="${LOG_RUN_DIR:-${LOG_DIR}/runs}"

MAIL_TO="${MAIL_TO:-alerts@example.com}"
MAIL_FROM="${MAIL_FROM:-borg@localhost}"
MAIL_ON_SUCCESS="${MAIL_ON_SUCCESS:-true}"
MAIL_ON_FAILURE="${MAIL_ON_FAILURE:-true}"
MAIL_ON_SKIP="${MAIL_ON_SKIP:-true}"
TEST_STATUS="$(normalize_test_status "${TEST_STATUS:-${BORG_TEST_STATUS:-}}")"

if [ -z "${TEST_STATUS}" ]; then
  require_passphrase
fi
setup_logging "${JOB_NAME}"

RUN_START_EPOCH=$(date +%s)
RUN_START_HUMAN="$(date '+%a %d %b %Y %H:%M:%S %Z')"
HOSTNAME="$(hostname)"

CHECK_EXIT=0
SKIPPED=0
SKIP_REASON=""

# Finalizer: always runs via trap to send notifications.
finalize() {
  local exit_code="$1"
  local run_end_epoch
  local run_end_human
  local run_duration
  local status
  local final_exit
  local warn_count
  local warn_lines
  local check_result
  local note_text
  local subject
  local body
  local html_body
  local h_status
  local h_host
  local h_repo
  local h_start
  local h_end
  local h_duration
  local h_check_result
  local h_check_exit
  local h_warn_count
  local h_warn_lines
  local h_note
  local h_log
  local badge_color
  local note_section_html
  local attachment

  run_end_epoch=$(date +%s)
  run_end_human="$(date '+%a %d %b %Y %H:%M:%S %Z')"
  run_duration=$(format_duration $((run_end_epoch - RUN_START_EPOCH)))

  if [ "${SKIPPED}" -eq 1 ]; then
    local skip_subject
    local skip_body
    local skip_reason
    local skip_html
    local h_status
    local h_host
    local h_repo
    local h_start
    local h_end
    local h_duration
    local h_reason
    local h_log
    local badge_color

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

    h_status=$(html_escape "SKIP")
    h_host=$(html_escape "${HOSTNAME}")
    h_repo=$(html_escape "${BORG_REPO}")
    h_start=$(html_escape "${RUN_START_HUMAN}")
    h_end=$(html_escape "${run_end_human}")
    h_duration=$(html_escape "${run_duration}")
    h_reason=$(html_escape "${skip_reason}")
    h_log=$(html_escape "${RUN_LOG}")
    badge_color=$(status_color "SKIP")

    skip_html=$(cat <<'EOF_HTML'
<html>
<body style="margin:0;padding:16px;background:#f3f4f6;">
  <div style="max-width:720px;margin:0 auto;background:#ffffff;border:1px solid #e5e7eb;border-radius:12px;padding:16px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;color:#111827;">
    <div style="display:flex;align-items:center;gap:10px;">
      <span style="display:inline-block;padding:4px 10px;border-radius:999px;background:__BADGE_COLOR__;color:#fff;font-size:12px;font-weight:600;letter-spacing:0.3px;">__STATUS__</span>
      <span style="font-size:16px;font-weight:600;">Borg Verify-Data Skipped</span>
    </div>
    <table style="width:100%;border-collapse:collapse;margin-top:12px;font-size:14px;">
      <tr><td style="padding:4px 0;color:#6b7280;width:140px;">Host</td><td style="padding:4px 0;">__HOST__</td></tr>
      <tr><td style="padding:4px 0;color:#6b7280;">Repository</td><td style="padding:4px 0;">__REPO__</td></tr>
      <tr><td style="padding:4px 0;color:#6b7280;">Start</td><td style="padding:4px 0;">__START__</td></tr>
      <tr><td style="padding:4px 0;color:#6b7280;">End</td><td style="padding:4px 0;">__END__</td></tr>
      <tr><td style="padding:4px 0;color:#6b7280;">Duration</td><td style="padding:4px 0;">__DURATION__</td></tr>
    </table>
    <div style="margin-top:12px;font-weight:600;font-size:14px;">Reason</div>
    <pre style="margin-top:6px;background:#f9fafb;border:1px solid #e5e7eb;border-radius:8px;padding:8px;font-size:12px;white-space:pre-wrap;">__REASON__</pre>
    <div style="margin-top:12px;color:#6b7280;font-size:13px;">Log: __LOG__</div>
  </div>
</body>
</html>
EOF_HTML
)
    skip_html=${skip_html//__BADGE_COLOR__/${badge_color}}
    skip_html=${skip_html//__STATUS__/${h_status}}
    skip_html=${skip_html//__HOST__/${h_host}}
    skip_html=${skip_html//__REPO__/${h_repo}}
    skip_html=${skip_html//__START__/${h_start}}
    skip_html=${skip_html//__END__/${h_end}}
    skip_html=${skip_html//__DURATION__/${h_duration}}
    skip_html=${skip_html//__REASON__/${h_reason}}
    skip_html=${skip_html//__LOG__/${h_log}}

    if is_enabled "${MAIL_ON_SKIP}"; then
      set +e
      send_mail "${skip_subject}" "${skip_body}" "" "${skip_html}"
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

    log "===== Borg Check --verify-data Skipped: $(date '+%a %d %b %Y %H:%M:%S %Z') ====="
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
  warn_lines=""
  if [ "${warn_count}" -gt 0 ]; then
    warn_lines=$(collect_warnings "${RUN_LOG}" 30)
    if [ -z "${warn_lines}" ]; then
      warn_lines="See log for details."
    fi
  fi

  check_result=$(borg_check_exit_summary "${CHECK_EXIT}")
  note_text=""
  if [ -n "${TEST_STATUS}" ]; then
    note_text="Email test mode: borg was not executed; this is a simulated result (TEST_STATUS=${TEST_STATUS})."
  elif [ "${CHECK_EXIT}" -eq 0 ] && [ "${warn_count}" -eq 0 ]; then
    note_text="Successful Borg checks are often silent, so a short log is expected unless Borg reports warnings or errors."
  fi

  log "Check summary: status=${status}, borg_exit=${CHECK_EXIT}, warnings=${warn_count}, duration=${run_duration}"
  if [ -n "${note_text}" ]; then
    log "${note_text}"
  fi

  if [ "${status}" = "OK" ]; then
    log "===== Borg Check --verify-data Finished Successfully: ${run_end_human} ====="
  else
    log "===== Borg Check --verify-data Finished With Errors: ${run_end_human} ====="
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

Check result: __CHECK_RESULT__
Borg exit code: __CHECK_EXIT__
Warnings/Errors: __WARN_COUNT__
__NOTE_BLOCK__

Log: __LOG__
EOF_BODY
)
  body=${body//__STATUS__/${status}}
  body=${body//__HOST__/${HOSTNAME}}
  body=${body//__REPO__/${BORG_REPO}}
  body=${body//__START__/${RUN_START_HUMAN}}
  body=${body//__END__/${run_end_human}}
  body=${body//__DURATION__/${run_duration}}
  body=${body//__CHECK_RESULT__/${check_result}}
  body=${body//__CHECK_EXIT__/${CHECK_EXIT}}
  body=${body//__WARN_COUNT__/${warn_count}}
  if [ -n "${note_text}" ]; then
    body=${body//__NOTE_BLOCK__/Note: ${note_text}}
  else
    body=${body//__NOTE_BLOCK__/}
  fi
  body=${body//__LOG__/${RUN_LOG}}

  if [ "${warn_count}" -gt 0 ]; then
    body+=$'\nWarnings/Errors ('"${warn_count}"'):\n'
    body+="${warn_lines}"$'\n'
  fi

  h_status=$(html_escape "${status}")
  h_host=$(html_escape "${HOSTNAME}")
  h_repo=$(html_escape "${BORG_REPO}")
  h_start=$(html_escape "${RUN_START_HUMAN}")
  h_end=$(html_escape "${run_end_human}")
  h_duration=$(html_escape "${run_duration}")
  h_check_result=$(html_escape "${check_result}")
  h_check_exit=$(html_escape "${CHECK_EXIT}")
  h_warn_count=$(html_escape "${warn_count}")
  h_warn_lines=$(html_escape "${warn_lines}")
  h_note=$(html_escape "${note_text}")
  h_log=$(html_escape "${RUN_LOG}")
  badge_color=$(status_color "${status}")

  html_body=$(cat <<'EOF_HTML'
<html>
<body style="margin:0;padding:16px;background:#f3f4f6;">
  <div style="max-width:720px;margin:0 auto;background:#ffffff;border:1px solid #e5e7eb;border-radius:12px;padding:16px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;color:#111827;">
    <div style="display:flex;align-items:center;gap:10px;">
      <span style="display:inline-block;padding:4px 10px;border-radius:999px;background:__BADGE_COLOR__;color:#fff;font-size:12px;font-weight:600;letter-spacing:0.3px;">__STATUS__</span>
      <span style="font-size:16px;font-weight:600;">Borg Verify-Data Summary</span>
    </div>
    <table style="width:100%;border-collapse:collapse;margin-top:12px;font-size:14px;">
      <tr><td style="padding:4px 0;color:#6b7280;width:140px;">Host</td><td style="padding:4px 0;">__HOST__</td></tr>
      <tr><td style="padding:4px 0;color:#6b7280;">Repository</td><td style="padding:4px 0;">__REPO__</td></tr>
      <tr><td style="padding:4px 0;color:#6b7280;">Start</td><td style="padding:4px 0;">__START__</td></tr>
      <tr><td style="padding:4px 0;color:#6b7280;">End</td><td style="padding:4px 0;">__END__</td></tr>
      <tr><td style="padding:4px 0;color:#6b7280;">Duration</td><td style="padding:4px 0;">__DURATION__</td></tr>
      <tr><td style="padding:4px 0;color:#6b7280;">Check result</td><td style="padding:4px 0;">__CHECK_RESULT__</td></tr>
      <tr><td style="padding:4px 0;color:#6b7280;">Borg exit code</td><td style="padding:4px 0;">__CHECK_EXIT__</td></tr>
      <tr><td style="padding:4px 0;color:#6b7280;">Warnings/Errors</td><td style="padding:4px 0;">__WARN_COUNT__</td></tr>
    </table>
    __NOTE_SECTION_HTML__
    __WARN_SECTION_HTML__
    <div style="margin-top:12px;color:#6b7280;font-size:13px;">Log: __LOG__</div>
  </div>
</body>
</html>
EOF_HTML
)
  html_body=${html_body//__BADGE_COLOR__/${badge_color}}
  html_body=${html_body//__STATUS__/${h_status}}
  html_body=${html_body//__HOST__/${h_host}}
  html_body=${html_body//__REPO__/${h_repo}}
  html_body=${html_body//__START__/${h_start}}
  html_body=${html_body//__END__/${h_end}}
  html_body=${html_body//__DURATION__/${h_duration}}
  html_body=${html_body//__CHECK_RESULT__/${h_check_result}}
  html_body=${html_body//__CHECK_EXIT__/${h_check_exit}}
  html_body=${html_body//__WARN_COUNT__/${h_warn_count}}
  html_body=${html_body//__LOG__/${h_log}}

  note_section_html=""
  if [ -n "${note_text}" ]; then
    note_section_html=$(cat <<'EOF_NOTE_HTML'
    <div style="margin-top:12px;color:#6b7280;font-size:12px;">__NOTE__</div>
EOF_NOTE_HTML
)
    note_section_html=${note_section_html//__NOTE__/${h_note}}
  fi

  warn_section_html=""
  if [ "${warn_count}" -gt 0 ]; then
    warn_section_html=$(cat <<'EOF_WARN_HTML'
    <div style="margin-top:12px;font-weight:600;font-size:14px;">Warnings/Errors (__WARN_COUNT__)</div>
    <pre style="margin-top:6px;background:#f9fafb;border:1px solid #e5e7eb;border-radius:8px;padding:8px;font-size:12px;white-space:pre-wrap;">__WARN_LINES__</pre>
EOF_WARN_HTML
)
    warn_section_html=${warn_section_html//__WARN_COUNT__/${h_warn_count}}
    warn_section_html=${warn_section_html//__WARN_LINES__/${h_warn_lines}}
  fi

  html_body=${html_body//__NOTE_SECTION_HTML__/${note_section_html}}
  html_body=${html_body//__WARN_SECTION_HTML__/${warn_section_html}}

  attachment="${RUN_LOG}"

  if [ "${status}" = "OK" ]; then
    if is_enabled "${MAIL_ON_SUCCESS}"; then
      set +e
      send_mail "${subject}" "${body}" "${attachment}" "${html_body}"
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
      send_mail "${subject}" "${body}" "${attachment}" "${html_body}"
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

  exit "${final_exit}"
}

trap 'finalize $?' EXIT

log "===== Borg Check --verify-data Started: ${RUN_START_HUMAN} ====="

if [ -n "${TEST_STATUS}" ]; then
  simulate_check_test_run "${TEST_STATUS}" "borg check --verify-data"
  exit $?
fi

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
log "Running borg check --verify-data against ${BORG_REPO} with lock wait ${BORG_LOCK_WAIT}s."
set +e
borg check --verify-data --lock-wait "${BORG_LOCK_WAIT}" "${BORG_REPO}"
CHECK_EXIT=$?
set -e
log "borg check --verify-data exited with code ${CHECK_EXIT} ($(borg_check_exit_summary "${CHECK_EXIT}"))."
