# Scripts Reference

This document describes the purpose and behavior of each script in `scripts/`.

See also:
- `Systemd.md`
- `Configuration.md`
- `Makefile.md`

## borg_nightly.sh
Purpose: nightly backup workflow with snapshot + create + prune + email summary.

Key actions:
- Validates ZFS datasets and mountpoints.
- Creates a ZFS snapshot for a consistent backup source.
- Runs `borg create` with stats and lock-wait.
- Runs `borg prune` with retention rules and stats.
- Collects post-prune size summaries from `borg info`.
- Sends a structured email (text + HTML) and attaches the full log.
- Removes the snapshot after backup.

Primary inputs:
- `BORG_REPO`, `SOURCE_PATH`, `ZFS_DATASET`, `ARCHIVE_PREFIX`, `BORG_LOCK_WAIT`.

Primary outputs:
- Per-run log in `/var/log/borg/runs/backup_<timestamp>.log`.
- Latest symlink at `/var/log/borg/backup_latest.log`.
- Email summary via `msmtp`.

## borg_check.sh
Purpose: weekly repository integrity check.

Key actions:
- Validates repo availability and mountpoints.
- Runs `borg check` with lock-wait.
- Sends a structured email (text + HTML) and attaches the log.

Primary inputs:
- `BORG_REPO`, `BORG_LOCK_WAIT`.

Primary outputs:
- Per-run log in `/var/log/borg/runs/check_<timestamp>.log`.
- Latest symlink at `/var/log/borg/check_latest.log`.

## borg_check_verify.sh
Purpose: monthly data verification with `borg check --verify-data`.

Key actions:
- Validates repo availability and mountpoints.
- Runs `borg check --verify-data` with lock-wait.
- Sends a structured email (text + HTML) and attaches the log.

Primary inputs:
- `BORG_REPO`, `BORG_LOCK_WAIT`.

Primary outputs:
- Per-run log in `/var/log/borg/runs/check_verify_<timestamp>.log`.
- Latest symlink at `/var/log/borg/check_verify_latest.log`.

## borg_log_cleanup.sh
Purpose: deletes per-run logs older than `LOG_RETENTION_DAYS`.

Key actions:
- Removes old log files under `/var/log/borg/runs`.
- Logs the number of deleted files.

Primary inputs:
- `LOG_DIR`, `LOG_RUN_DIR`, `LOG_RETENTION_DAYS`.

Primary outputs:
- Log entry in the cleanup run log.

## borg_lib.sh
Purpose: shared helper functions used by all scripts.

Key actions:
- Loads environment, validates passphrase, and sets up logging.
- Creates run IDs, log paths, and latest symlinks.
- Provides mail helpers for HTML + text emails.
- Provides reusable sanity checks and mount checks.
