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
- `MAIL_ON_SUCCESS` / `MAIL_ON_FAILURE` — set to `true/false` (or `1/0`) to send or suppress.

## Initial setup
> Prerequisites: Debian-like host with systemd, `borgbackup`, `zfsutils-linux`, and a working `msmtp` config; sudo/root access.

### Verify Borg is installed (install if missing):
```bash
borg --version || { sudo apt update && sudo apt install borgbackup -y; }
```

### Recommended clone location:
```bash
sudo mkdir -p /opt/git && sudo chown "$(whoami)" /opt/git
cd /opt/git
git clone https://github.com/Vantasin/Borg.git
cd Borg
```

### Install and configure:
1) Install artifacts and reload systemd:
```bash
sudo make install
```
> Installs scripts, units, logrotate; seeds borg.env if missing
> To force overwrite of borg.env: `sudo make install-force` (or `FORCE=1 sudo make install`)

2) Edit runtime config (0600 root:root):
```bash
sudo nano /usr/local/sbin/borg/borg.env
```
> Set BORG_PASSPHRASE, BORG_REPO, SOURCE_PATH, ZFS_DATASET, REPO_DATASET (if used), LOG_DIR, MAIL_TO/FROM

3) Optional manual test run:
```bash
sudo systemctl start borg-backup.service
```
> See journal/logs for results

4) Enable timers:
```bash
sudo make enable
```
5) Optional sanity check:
```bash
sudo make check
```

## Borg Repository Initialization (Encrypted)
> Recommended mode: `repokey-blake2` (encrypts data+metadata with a repo-embedded key + passphrase; balanced security and portability).
> One-time per repo path; run only when the dataset is unlocked/mounted.

Steps:
1) Ensure the repo dataset is unlocked and mounted (example):
```bash
sudo zfs load-key tank/Secure/Borg
sudo zfs mount tank/Secure/Borg
```
2) Set a strong passphrase for init (do not reuse weak or test values):
```bash
export BORG_PASSPHRASE='same-passphrase-set-in-borg.env'
```
3) Initialize the repo (adjust path as needed):
```bash
borg init --encryption=repokey-blake2 /tank/Secure/Borg/backup-repo
```
4) Verify:
```bash
borg info /tank/Secure/Borg/backup-repo
```
> Keep the repo inside the intended ZFS dataset/mountpoint (e.g., `/tank/Secure/Borg/backup-repo`). If the dataset is not mounted/unlocked, resolve that first; do not force init on the wrong path.

## Borg Passphrase Handling
- Default (recommended): store `BORG_PASSPHRASE` in `/usr/local/sbin/borg/borg.env` (0600 root:root). Services load it via `EnvironmentFile=`; scripts require it to be set.
- Optional: `pass`/GPG integration (operator-managed). Example non-interactive export before a manual run:
```bash
export BORG_PASSPHRASE="$(pass show backups/borg)"   # requires unlocked GPG key/pass store
systemctl start borg-backup.service
```
> Pros: keeps passphrase outside flat files. Cons: unattended timers require the GPG key and password store to be available/unlocked at boot—more operational complexity.
Choose based on whether you need fully unattended timers; the repo defaults to the env-file approach.

## Borg Key Export (CRITICAL)
- Encrypted repos need their key material plus the passphrase. Export and back it up safely—do this after `borg init` and after key changes.
```bash
borg key export /tank/Secure/Borg/backup-repo /root/borg-key.txt
chmod 600 /root/borg-key.txt && chown root:root /root/borg-key.txt
```
- Optional paper backup if desired:
```bash
borg key export --paper /tank/Secure/Borg/backup-repo > /root/borg-key-paper.txt
chmod 600 /root/borg-key-paper.txt && chown root:root /root/borg-key-paper.txt
```
- Store keys off the backup host (e.g., encrypted USB, password manager secure file, printed and stored securely). Do NOT store with the repo, on the same dataset, in Git, or in unencrypted cloud storage.
- Checklist: key exported ✅ / passphrase recorded ✅ / restore tested ✅

## Restore Instructions with Examples
> Always restore into a new/empty directory and verify before touching live data.

- Set context:
```bash
export BORG_PASSPHRASE='your-passphrase'
mkdir -p /restore/tmp/borg-test
```

- List archives:
```bash
borg list /tank/Secure/Borg/backup-repo
```

- Inspect contents of one archive:
```bash
borg list /tank/Secure/Borg/backup-repo::backup-myhost-2025-01-01T02:30
```

- Full extract to a temp directory:
```bash
cd /restore/tmp/borg-test
borg extract /tank/Secure/Borg/backup-repo::backup-myhost-2025-01-01T02:30
```

- Restore a single path:
```bash
cd /restore/tmp/borg-test
borg extract /tank/Secure/Borg/backup-repo::backup-myhost-2025-01-01T02:30 path/inside/archive
```

> After restore: verify permissions/ownership and run integrity checks as needed. Avoid overwriting live data; copy validated files into place during a planned window.

## Disaster Recovery Requirements
- Required to decrypt/restore:
  - Borg repo copy (`/tank/Secure/Borg/backup-repo` or replica)
  - Borg passphrase
  - Exported Borg key material (e.g., `/root/borg-key.txt`, or paper export)
- Required to rebuild automation:
  - This Git repo (scripts + units + Makefile)
  - Systemd units: `borg-backup.service|timer`, `borg-check.service|timer`, `borg-check-verify.service|timer`
  - Env template: `borg.env.example`; runtime config at `/usr/local/sbin/borg/borg.env` with required variables (`BORG_PASSPHRASE`, `BORG_REPO`, `SOURCE_PATH`, `ZFS_DATASET`, optional `REPO_DATASET`, `LOG_DIR`, `MAIL_TO`/`MAIL_FROM`)
- Recommended operational tests:
  - Periodic restore test to a disposable directory (e.g., quarterly)
  - Monitor existing timers: nightly backup, weekly `borg check`, monthly `borg check --verify-data`
  - Review logs under `/var/log/borg/` and `systemctl list-timers borg-*`

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
See [LICENSE](LICENSE).
