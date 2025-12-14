# Borg Automation

BorgBackup automation for a single live host and a single backup host on Debian/systemd with encrypted ZFS datasets. Nightly backups plus weekly and monthly integrity checks are run via systemd timers. If required ZFS datasets or mountpoints are unavailable (e.g., locked at boot), scripts log the condition and exit 0 so timers retry after storage is online.

## Repository layout
- `scripts/`: Bash entrypoints (`borg_nightly.sh`, `borg_check.sh`, `borg_check_verify.sh`).
- `systemd/`: `borg-*.service` and `borg-*.timer` units installed flat into `/etc/systemd/system/`.
- `packaging/logrotate/borg`: logrotate policy for `/var/log/borg/*.log`.
- `docs/`: original operational notes (`Borg Backup Archive -- Backup Server.md`).
- `borg.env.example`: sample environment; real config lives beside installed scripts.
- `Makefile`: install, enable/disable, status, check, uninstall targets.

## Security model
- Secrets and host-specific settings are not committed. Use `/usr/local/sbin/borg/borg.env` (0600, root:root); start from `borg.env.example`.
- Services load `EnvironmentFile=/usr/local/sbin/borg/borg.env`; scripts honor the same path and fall back to `/tank/Secure/Secrets/.borg_env` only if `BORG_PASSPHRASE` is otherwise unset.
- Logrotate installs to `/etc/logrotate.d/borg`; runtime logs stay in `/var/log/borg/`.

`/usr/local/sbin/borg/borg.env` variables (copy from `borg.env.example`):
- `BORG_PASSPHRASE` (required) — encryption key for the Borg repo.
- `BORG_REPO` — repo path, default `/tank/Secure/Borg/backup-repo`.
- `SOURCE_PATH` — source directory to back up, default `/tank/Secure/backup`.
- `ZFS_DATASET` — dataset for `SOURCE_PATH`, default `tank/Secure/backup`.
- `REPO_DATASET` — dataset hosting `BORG_REPO` (optional), e.g., `tank/Secure/Borg`.
- `LOG_DIR` — default `/var/log/borg`.
- `MAIL_TO` / `MAIL_FROM` — msmtp notification addresses.

## Initial setup
Prerequisites: Debian-like host with systemd, `borgbackup`, `zfsutils-linux`, and a working `msmtp` config; sudo/root access.

Verify Borg is installed:
```bash
borg --version  # if missing: sudo apt install borgbackup
```

Recommended clone location:
```bash
sudo mkdir -p /opt/git && sudo chown "$(whoami)" /opt/git
cd /opt/git
git clone <repo-url>
cd borg
```

Install and configure:
```bash
sudo make install          # installs scripts, units, logrotate; seeds borg.env if missing
sudo cp /usr/local/sbin/borg/borg.env.example /usr/local/sbin/borg/borg.env  # create/refresh config (use FORCE=1 on make install to overwrite automatically)
sudo chmod 600 /usr/local/sbin/borg/borg.env && sudo chown root:root /usr/local/sbin/borg/borg.env
sudo nano /usr/local/sbin/borg/borg.env     # set BORG_PASSPHRASE, BORG_REPO, SOURCE_PATH, ZFS_DATASET, REPO_DATASET (if used), LOG_DIR, MAIL_TO/FROM
sudo systemctl daemon-reload                  # make install already reloads; safe to repeat
sudo systemctl start borg-backup.service      # manual test run; see journal/logs
sudo make enable                              # enable timers
sudo make check                               # optional sanity check (paths/perms/logrotate)
```

## Day-2 operations
- Update flow:
```bash
git pull
sudo make install
sudo make check
```
- Status: `systemctl status borg-backup.service borg-check.service borg-check-verify.service` and `systemctl list-timers borg-*`.
- Logs: `/var/log/borg/backup_YYYY-MM-DD.log`, `check_YYYY-MM-DD.log`, `check_verify_YYYY-MM-DD.log`; journal via `journalctl -u borg-backup.service -n 100` (or other units).

Makefile targets (non-exhaustive):
- `make install`: install scripts/units/logrotate; seed `borg.env` if missing; reload systemd.
- `make enable` / `make disable`: enable/disable timers.
- `make status`: show service/timer status and timers list.
- `make check`: sanity-check installed paths/perms/logrotate.
- `make uninstall`: remove installed units/scripts/logrotate (keeps `borg.env`).

## Troubleshooting
- Dataset locked/unmounted: scripts log “not mounted/unavailable” and exit 0. Unlock/mount `ZFS_DATASET` (and optional `REPO_DATASET`), then `systemctl start borg-backup.service` or wait for the timer.
- Missing env or wrong perms: ensure `/usr/local/sbin/borg/borg.env` exists, has `BORG_PASSPHRASE`, and is `0600 root:root`; rerun `sudo make install` if needed and use `sudo make check`.

## Credits
Built on BorgBackup, ZFS, systemd, msmtp, and logrotate.

## License
See `LICENSE`.
