# Repository Guidelines

## Project Structure & Module Organization
- `scripts/`: source Bash for backups, prune, checks, and verify-data runs.
- `systemd/`: oneshot services and timers (including `borg-log-cleanup.timer`) wired to the installed scripts in `/usr/local/sbin/borg/`.
- `docs/`: production architecture and recovery notes (keep `Borg Backup Archive -- Backup Server.md` intact).
- `scripts/borg_log_cleanup.sh`: removes per-run logs older than the retention window.
- `README.md`: install/update steps and operational pointers; start here.

## Build, Test, and Development Commands
- `shellcheck scripts/*.sh`: lint scripts before committing.
- `sudo systemd-analyze verify systemd/borg-*.service systemd/borg-*.timer`: validate unit syntax and timer bindings.
- Manual dry-run with temp paths: `sudo env BORG_PASSPHRASE=testpass BORG_REPO=/tmp/borg-test SOURCE_PATH=/tmp/data ./scripts/borg_nightly.sh`.
- Preferred deployment: `sudo make install && sudo make enable` (copies to `/usr/local/sbin/borg/`, prunes stale installed files via `/usr/local/sbin/borg/.install-manifest`, reloads systemd).

## Coding Style & Naming Conventions
- Bash: start with `#!/usr/bin/env bash` and `set -euo pipefail`; prefer long-form flags, `$(...)`, two-space indents, and quoted variables. Keep config variables grouped near the top for easy overrides.
- Systemd: stick to `Type=oneshot`, root execution, and the existing `Nice`/`IOScheduling` values; name services/timers `borg-<action>.service|timer`. Units load `/usr/local/sbin/borg/borg.env`.
- Logs live under `/var/log/borg`; keep per-run log filenames date-stamped (`backup_YYYYMMDDTHHMMSS.log`, etc.).
- Log retention is handled by `borg-log-cleanup.timer` using `LOG_RETENTION_DAYS`.

## Testing Guidelines
- Run `shellcheck` plus a manual service invocation: `sudo systemctl start borg-backup.service` (or the check/verify units) and review `sudo journalctl -u borg-backup.service -n 100`.
- For safe functional tests, point `BORG_REPO` and `SOURCE_PATH` to disposable paths and use a temporary passphrase file; confirm snapshots/cleanup behave as expected.
- No automated coverage targets exist; favor small, auditable changes and include log snippets when sharing results.

## Commit & Pull Request Guidelines
- Commit subjects: present-tense, imperative, and scoped (e.g., `Adjust prune retention window`).
- PRs should state purpose, key changes, manual test commands, risks/rollback notes, and any deployment steps (`systemctl daemon-reload`, timer enablement).
- Link relevant incidents/issues and attach representative log tails when altering alerting or backup behavior.

## Security & Configuration Tips
- Do not commit secrets; runtime config lives at `/usr/local/sbin/borg/borg.env` (`0600 root:root`). An example file ships as `borg.env.example`.
- This automation assumes encrypted ZFS datasets and uses ZFS snapshots for consistent backups.
- Repository paths assume encrypted ZFS (`/tank/Secure/Borg/backup-repo`); never test against production storage.
- Scripts exit cleanly (0) if required ZFS datasets or mountpoints are absent; timers will retry once storage is online.
- Legacy compatibility: scripts will also source `/tank/Secure/Secrets/.borg_env` if `BORG_PASSPHRASE` is unset.
- Email notifications rely on `msmtp`; keep `MAIL_FROM`/`MAIL_TO` current and validate SMTP config when changing hosts.
