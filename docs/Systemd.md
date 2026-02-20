# Systemd Units Reference

This document describes the systemd services and timers under `systemd/`.

See also:
- `Scripts.md`
- `Configuration.md`
- `Makefile.md`

All services:
- Run as root (`Type=oneshot`).
- Load `/usr/local/sbin/borg/borg.env`.
- Execute the corresponding script in `/usr/local/sbin/borg/`.

## Services

borg-backup.service
- Runs `borg_nightly.sh`.
- Nightly backup workflow.

borg-check.service
- Runs `borg_check.sh`.
- Weekly integrity check.

borg-check-verify.service
- Runs `borg_check_verify.sh`.
- Monthly verify-data integrity check.

borg-log-cleanup.service
- Runs `borg_log_cleanup.sh`.
- Deletes old per-run logs.

## Timers

borg-backup.timer
- Triggers nightly backup.

borg-check.timer
- Triggers weekly `borg check`.

borg-check-verify.timer
- Triggers monthly `borg check --verify-data`.

borg-log-cleanup.timer
- Triggers log retention cleanup.

## Operational commands

Start a run:
- `sudo systemctl start borg-backup.service`
- `sudo systemctl start borg-check.service`
- `sudo systemctl start borg-check-verify.service`

View logs:
- `sudo journalctl -u borg-backup.service -n 100`
- `sudo journalctl -u borg-check.service -n 100`
- `sudo journalctl -u borg-check-verify.service -n 100`
