# Borg Automation

Opinionated BorgBackup automation for a single live host and a single backup host on Debian/systemd. This setup assumes encrypted ZFS datasets and relies on ZFS snapshots for consistent backups. Nightly backups plus weekly and monthly integrity checks run via systemd timers. If required ZFS datasets are unavailable, scripts log and exit 0 so timers retry after storage is online.

## Quickstart (start to finish)
1) Install Borg (Debian):
```bash
borg --version || { sudo apt update && sudo apt install borgbackup -y; }
```
2) Clone the repo:
```bash
sudo mkdir -p /opt/git && sudo chown "$(whoami)" /opt/git
cd /opt/git
git clone https://github.com/Vantasin/Borg.git
cd Borg
```
3) Install scripts/units (seeds borg.env if missing):
```bash
sudo make install
```
> If upgrading from older versions, `make install` removes the legacy `/etc/logrotate.d/borg` file.
> `make install` also removes stale installed scripts/units based on a manifest in `/usr/local/sbin/borg/.install-manifest` (never touches `borg.env`).
> Legacy logrotate cleanup is handled separately and is not part of the manifest.
> To force overwrite of borg.env (with a timestamped backup in the same directory): `sudo make install-force`.

4) Configure runtime env (0600 root:root):
```bash
sudo nano /usr/local/sbin/borg/borg.env
```
5) Create storage:
- Source data must live on encrypted ZFS so snapshots are available (required).
- Borg repo can live on ZFS or ext4; ZFS is recommended for consistency.

ZFS example:
```bash
sudo zfs create tank/Secure/Borg
```
ext4 example (repo only, not source data):
```bash
sudo mkdir -p /tank/Secure/Borg
```
6) Initialize the encrypted Borg repo (one-time per path):
```bash
sudo borg init --encryption=repokey-blake2 /tank/Secure/Borg/backup-repo
```
> Use the same passphrase that you set in the borg.env.

7) Export the repo key (store off-host securely):
```bash
sudo borg key export /tank/Secure/Borg/backup-repo ~/borg-key.txt
```
Optional paper copy:
```bash
sudo borg key export --paper /tank/Secure/Borg/backup-repo > ~/borg-key-paper.txt
```
> Encrypted repos need key material plus the passphrase. Export after init/changes and store off-host.

> Keep keys off the backup host (encrypted USB, password manager secure file, printed and stored securely). Do NOT store with the repo, on the same dataset, in Git, or in unencrypted cloud storage.

> Checklist: key exported ✅ / passphrase recorded ✅ / restore tested ✅

8) Optional manual test run:

> **Note:** This can take a long time depending on the size of the initial backup.

- Use tmux to avoid interruption if session drops:
```bash
tmux new -s borg-test
```
- Run manual backup in pane 1:
```bash
sudo systemctl start borg-backup.service
```
- **Split pane:** `Ctrl-b` then `"`
- Follow backup progress in pane 2
```bash
tail -f /var/log/borg/backup_latest.log
```

> **Detach:** `Ctrl-b` then `d`

> **Reattach:** `tmux attach -t borg-test`

9) Enable timers:
```bash
sudo make enable
```
> This also enables `borg-log-cleanup.timer` for log retention.
> One-shot deploy (install + enable + status): `sudo make deploy`.
10) Optional sanity check:
```bash
sudo make check
```
> `make check` validates installed files/perms and exits non-zero on issues.
11) Optional status review (human confirmation):
```bash
sudo make status
```
> `make status` shows systemd service/timer state for human review.

## Validate and test
### Status:
- `systemctl status borg-backup.service borg-check.service borg-check-verify.service borg-log-cleanup.service`
- `systemctl list-timers`

### Logs:
- Per-run logs: `/var/log/borg/runs/backup_YYYYMMDDTHHMMSS.log`
- Per-run logs: `/var/log/borg/runs/check_YYYYMMDDTHHMMSS.log`
- Per-run logs: `/var/log/borg/runs/check_verify_YYYYMMDDTHHMMSS.log`
- Latest symlinks: `/var/log/borg/backup_latest.log`, `/var/log/borg/check_latest.log`, `/var/log/borg/check_verify_latest.log`
- journal via `journalctl -u borg-backup.service -n 100`
> Logs older than `LOG_RETENTION_DAYS` are deleted by `borg-log-cleanup.timer`.

### Restore test (recommended periodically):

1) Make the restore directory.
```bash
mkdir -p /restore/tmp/borg-test
```
2) List the Borg repos.
```bash
sudo borg list /tank/Secure/Borg/backup-repo
```
3) Restore a Borg repo from the list.
```bash
cd /restore/tmp/borg-test
sudo borg extract /tank/Secure/Borg/backup-repo::backup-myhost-2025-01-01T02:30
```
> Use the same passphrase that you set in the borg.env.

> **After restore:** verify permissions/ownership and integrity.

> Avoid overwriting live data.

## Repository layout
- `scripts/`: Bash entrypoints (`borg_nightly.sh`, `borg_check.sh`, `borg_check_verify.sh`).
- `systemd/`: `borg-*.service` and `borg-*.timer` units installed flat into `/etc/systemd/system/` (includes log cleanup timer).
- `scripts/borg_lib.sh`: shared helpers (logging, mail, env load).
- `scripts/borg_log_cleanup.sh`: prunes old per-run logs (used by `borg-log-cleanup.timer`).
- `docs/`: original operational notes (`Borg Backup Archive -- Backup Server.md`).
- `borg.env.example`: sample environment; real config lives beside installed scripts.
- `Makefile`: install, enable/disable, status, check, uninstall targets.

## Security model and configuration
- This automation assumes encrypted ZFS datasets and uses ZFS snapshots for consistent backups.
- Secrets/config are not committed. Use `/usr/local/sbin/borg/borg.env` (0600 root:root); start from `borg.env.example`.
- Services load `EnvironmentFile=/usr/local/sbin/borg/borg.env`; scripts require `BORG_PASSPHRASE` and honor the same path (legacy fallback to `/tank/Secure/Secrets/.borg_env` if unset).
- Runtime logs stay in `/var/log/borg/` and are pruned by `borg-log-cleanup.timer`.

Key variables in `/usr/local/sbin/borg/borg.env`:
- `BORG_PASSPHRASE` (required) — repo encryption passphrase
- `BORG_REPO` — default `/tank/Secure/Borg/backup-repo`
- `SOURCE_PATH` — default `/tank/Secure/backup`
- `ZFS_DATASET` — default `tank/Secure/backup`
- `REPO_DATASET` — optional dataset hosting the repo, e.g., `tank/Secure/Borg`
- `LOG_DIR` — default `/var/log/borg`
- `LOG_RUN_DIR` — default `/var/log/borg/runs`
- `LOG_RETENTION_DAYS` — delete per-run logs older than this (default `90`)
- `ARCHIVE_PREFIX` — archive name prefix (default `backup`)
- `BORG_LOCK_WAIT` — seconds to wait for repo lock (default `3600`)
- `MAIL_TO` / `MAIL_FROM` — msmtp notification addresses
- `MAIL_ON_SUCCESS` / `MAIL_ON_FAILURE` / `MAIL_ON_SKIP` — `true/false` (or `1/0`) to send or suppress

## Borg Passphrase Handling
- Default (recommended): env file at `/usr/local/sbin/borg/borg.env` (0600 root:root), loaded by systemd and scripts.
- Optional `pass`/GPG (operator-managed):
```bash
export BORG_PASSPHRASE="$(pass show backups/borg)"   # requires unlocked GPG key/pass store
sudo systemctl start borg-backup.service
```
> Pros: keeps passphrase outside flat files.

> Cons: unattended timers require GPG key+store unlocked at boot.

## Disaster Recovery Requirements
- To decrypt/restore:
  - Borg repo copy (`/tank/Secure/Borg/backup-repo` or replica)
  - Borg passphrase
  - Exported Borg key material (text or paper)
- To rebuild automation:
  - This Git repo (scripts, units, Makefile)
  - Systemd units: `borg-backup.service|timer`, `borg-check.service|timer`, `borg-check-verify.service|timer`
  - Env template: `borg.env.example`; runtime config at `/usr/local/sbin/borg/borg.env` (`BORG_PASSPHRASE`, `BORG_REPO`, `SOURCE_PATH`, `ZFS_DATASET`, optional `REPO_DATASET`, `LOG_DIR`, `MAIL_TO`/`MAIL_FROM`, `MAIL_ON_SUCCESS`/`MAIL_ON_FAILURE`)
- Recommended tests:
  - Periodic restore to a disposable directory (e.g., quarterly)
  - Monitor timers: nightly backup, `borg check` on 1st-3rd Saturdays, `borg check --verify-data` on the 4th Saturday
  - Review `/var/log/borg/` and `systemctl list-timers borg-*`

## Troubleshooting
- Dataset absent: create the dataset (ZFS `zfs create ...` or mkdir for ext4) at the intended path, then rerun.
- Missing env or wrong perms: ensure `/usr/local/sbin/borg/borg.env` exists, has `BORG_PASSPHRASE`, and is `0600 root:root`; rerun `sudo make install` if needed and use `sudo make check`.

## Makefile targets (common)
- `make install` / `make install-force` (overwrite borg.env with a timestamped backup): install scripts/units; remove stale installed files via manifest; reload systemd.
- `make enable` / `make disable`: enable/disable timers.
- `make deploy`: install + enable + status.
- `make status`: show service/timer status and timers list.
- `make check`: sanity-check installed paths/perms.
- `make uninstall`: remove installed units/scripts (keeps `borg.env`).

## Credits
Built on BorgBackup, ZFS, systemd, and msmtp.

## License
See [LICENSE](LICENSE).
