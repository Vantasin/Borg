#!/usr/bin/env bash
set -euo pipefail

############################################################
# Optional env file load (services use EnvironmentFile)
############################################################
load_env() {
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
}

require_passphrase() {
  : "${BORG_PASSPHRASE:?BORG_PASSPHRASE is required}"
}

log() {
  printf '%s %s\n' "$(date '+%a %d %b %Y %H:%M:%S %Z')" "$*"
}

setup_logging() {
  local job_name="$1"
  local old_umask

  : "${LOG_DIR:=/var/log/borg}"
  : "${LOG_RUN_DIR:=${LOG_DIR}/runs}"

  RUN_ID="$(date +%Y%m%dT%H%M%S)"
  RUN_LOG="${LOG_RUN_DIR}/${job_name}_${RUN_ID}.log"
  LATEST_LOG="${LOG_DIR}/${job_name}_latest.log"

  old_umask=$(umask)
  umask 027
  mkdir -p "${LOG_DIR}" "${LOG_RUN_DIR}"
  : > "${RUN_LOG}"
  ln -sfn "${RUN_LOG}" "${LATEST_LOG}"
  umask "${old_umask}"

  exec > >(tee -a "${RUN_LOG}") 2>&1
}

require_mounted() {
  local path="$1"
  local label="$2"

  if command -v findmnt >/dev/null 2>&1; then
    if ! findmnt -T "${path}" >/dev/null 2>&1; then
      return 1
    fi
  fi

  return 0
}

is_enabled() {
  case "$1" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    0|false|FALSE|no|NO|off|OFF|"") return 1 ;;
    *) return 1 ;;
  esac
}

send_mail() {
  local subject="$1"
  local text_body="$2"
  local attachment="${3:-}"
  local html_body="${4:-}"
  local msmtp_bin
  local boundary
  local alt_boundary

  msmtp_bin="$(command -v msmtp || true)"
  if [ -z "${msmtp_bin}" ]; then
    log "WARNING: msmtp not found; unable to send email."
    return 1
  fi

  if [ -n "${html_body}" ]; then
    alt_boundary="====borg_alt_$(date +%s%N)===="
    if [ -n "${attachment}" ] && [ -f "${attachment}" ]; then
      boundary="====borg_mixed_$(date +%s%N)===="
      {
        printf "From: %s\n" "${MAIL_FROM}"
        printf "To: %s\n" "${MAIL_TO}"
        printf "Subject: %s\n" "${subject}"
        printf "MIME-Version: 1.0\n"
        printf "Content-Type: multipart/mixed; boundary=\"%s\"\n\n" "${boundary}"
        printf '%s\n' "--${boundary}"
        printf "Content-Type: multipart/alternative; boundary=\"%s\"\n\n" "${alt_boundary}"
        printf '%s\n' "--${alt_boundary}"
        printf "Content-Type: text/plain; charset=UTF-8\n"
        printf "Content-Transfer-Encoding: 8bit\n\n"
        printf "%s\n\n" "${text_body}"
        printf '%s\n' "--${alt_boundary}"
        printf "Content-Type: text/html; charset=UTF-8\n"
        printf "Content-Transfer-Encoding: 8bit\n\n"
        printf "%s\n\n" "${html_body}"
        printf '%s\n' "--${alt_boundary}--"
        printf '%s\n' "--${boundary}"
        printf "Content-Type: text/plain; name=\"%s\"\n" "$(basename "${attachment}")"
        printf "Content-Disposition: attachment; filename=\"%s\"\n" "$(basename "${attachment}")"
        printf "Content-Transfer-Encoding: 8bit\n\n"
        cat "${attachment}"
        printf '\n\n%s\n' "--${boundary}--"
      } | "${msmtp_bin}" -a default "${MAIL_TO}"
    else
      {
        printf "From: %s\n" "${MAIL_FROM}"
        printf "To: %s\n" "${MAIL_TO}"
        printf "Subject: %s\n" "${subject}"
        printf "MIME-Version: 1.0\n"
        printf "Content-Type: multipart/alternative; boundary=\"%s\"\n\n" "${alt_boundary}"
        printf '%s\n' "--${alt_boundary}"
        printf "Content-Type: text/plain; charset=UTF-8\n"
        printf "Content-Transfer-Encoding: 8bit\n\n"
        printf "%s\n\n" "${text_body}"
        printf '%s\n' "--${alt_boundary}"
        printf "Content-Type: text/html; charset=UTF-8\n"
        printf "Content-Transfer-Encoding: 8bit\n\n"
        printf "%s\n\n" "${html_body}"
        printf '%s\n' "--${alt_boundary}--"
      } | "${msmtp_bin}" -a default "${MAIL_TO}"
    fi
  elif [ -n "${attachment}" ] && [ -f "${attachment}" ]; then
    boundary="====borg_$(date +%s%N)===="
    {
      printf "From: %s\n" "${MAIL_FROM}"
      printf "To: %s\n" "${MAIL_TO}"
      printf "Subject: %s\n" "${subject}"
      printf "MIME-Version: 1.0\n"
      printf "Content-Type: multipart/mixed; boundary=\"%s\"\n\n" "${boundary}"
      printf '%s\n' "--${boundary}"
      printf "Content-Type: text/plain; charset=UTF-8\n"
      printf "Content-Transfer-Encoding: 8bit\n\n"
      printf "%s\n\n" "${text_body}"
      printf '%s\n' "--${boundary}"
      printf "Content-Type: text/plain; name=\"%s\"\n" "$(basename "${attachment}")"
      printf "Content-Disposition: attachment; filename=\"%s\"\n" "$(basename "${attachment}")"
      printf "Content-Transfer-Encoding: 8bit\n\n"
      cat "${attachment}"
      printf '\n\n%s\n' "--${boundary}--"
    } | "${msmtp_bin}" -a default "${MAIL_TO}"
  else
    printf "From: %s\nTo: %s\nSubject: %s\n\n%s\n" \
      "${MAIL_FROM}" "${MAIL_TO}" "${subject}" "${text_body}" \
      | "${msmtp_bin}" -a default "${MAIL_TO}"
  fi
}

html_escape() {
  local value="$1"
  value=${value//&/&amp;}
  value=${value//</&lt;}
  value=${value//>/&gt;}
  printf '%s' "${value}"
}

status_color() {
  case "$1" in
    OK) echo "#16a34a" ;;
    WARN) echo "#d97706" ;;
    FAIL) echo "#dc2626" ;;
    SKIP) echo "#6b7280" ;;
    *) echo "#2563eb" ;;
  esac
}

format_duration() {
  local total="$1"
  local hours
  local minutes
  local seconds

  hours=$((total / 3600))
  minutes=$(((total % 3600) / 60))
  seconds=$((total % 60))

  printf '%02d:%02d:%02d' "${hours}" "${minutes}" "${seconds}"
}

extract_value() {
  local key="$1"
  local file="$2"

  awk -F': ' -v k="${key}" '$1 == k {print $2; exit}' "${file}" 2>/dev/null || true
}

count_matching() {
  local pattern="$1"
  local file="$2"

  if [ -f "${file}" ]; then
    grep -E "${pattern}" "${file}" | wc -l | tr -d ' ' || true
  else
    echo 0
  fi
}

collect_warnings() {
  local file="$1"
  local limit="${2:-20}"

  if [ -f "${file}" ]; then
    grep -E '(WARNING|ERROR|Error:|CRITICAL|FAILED)' "${file}" | tail -n "${limit}" || true
  fi
}

skip_run() {
  SKIPPED=1
  SKIP_REASON="$1"
  log "$1"
  exit 0
}

sanity_check_source() {
  local mountpoint
  local src_dataset

  mountpoint="$(zfs get -H -o value mountpoint "${ZFS_DATASET}" 2>/dev/null || true)"
  if [ -z "${mountpoint}" ] || [ "${mountpoint}" = "legacy" ] || [ "${mountpoint}" = "-" ] || [ "${mountpoint}" = "none" ]; then
    log "WARNING: Cannot verify ZFS mountpoint for ${ZFS_DATASET}; mountpoint=${mountpoint:-unknown}."
    return 0
  fi

  case "${SOURCE_PATH}" in
    "${mountpoint}"|"${mountpoint}/"*) : ;;
    *)
      log "ERROR: SOURCE_PATH (${SOURCE_PATH}) is not within ZFS_DATASET mountpoint (${mountpoint})."
      return 1
      ;;
  esac

  src_dataset="$(findmnt -T "${SOURCE_PATH}" -n -o SOURCE 2>/dev/null || true)"
  if [ -n "${src_dataset}" ] && [ "${src_dataset}" != "${ZFS_DATASET}" ]; then
    log "ERROR: SOURCE_PATH resolves to dataset ${src_dataset}, expected ${ZFS_DATASET}."
    return 1
  fi

  return 0
}
