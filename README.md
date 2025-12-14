# Borg Automation

BorgBackup automation for a single live host and a single backup host on Debian/systemd with encrypted ZFS datasets. Nightly backups plus weekly and monthly integrity checks run via systemd timers. If required ZFS datasets or mountpoints are unavailable (locked at boot), scripts log the condition and exit 0 so timers retry after storage is online.

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
cd borg
```
3) Install scripts/units/logrotate (seeds borg.env if missing):
```bash
sudo make install
# To force overwrite of borg.env: sudo make install-force
```
4) Configure runtime env (0600 root:root):
```bash
sudo nano /usr/local/sbin/borg/borg.env
# Set BORG_PASSPHRASE, BORG_REPO, SOURCE_PATH, ZFS_DATASET, REPO_DATASET (optional), LOG_DIR, MAIL_TO/FROM, MAIL_ON_SUCCESS/MAIL_ON_FAILURE
```
5) Prepare storage and init encrypted repo (one-time per path):
```bash
# If using ZFS and dataset not present:
sudo zfs create tank/Secure/Borg
sudo zfs load-key tank/Secure/Borg
sudo zfs mount tank/Secure/Borg

# If using ext4 on /dev/sdX1:
sudo mkfs.ext4 /dev/sdX1
sudo mkdir -p /tank/Secure/Borg
echo "/dev/sdX1 /tank/Secure/Borg ext4 defaults 0 2" | sudo tee -a /etc/fstab
sudo mount /tank/Secure/Borg

# Initialize Borg repo (adjust path as needed)
export BORG_PASSPHRASE='same-passphrase-set-in-borg.env'
sudo borg init --encryption=repokey-blake2 /tank/Secure/Borg/backup-repo
sudo borg info /tank/Secure/Borg/backup-repo
```
6) Export the repo key (store off-host securely):
```bash
sudo borg key export /tank/Secure/Borg/backup-repo /root/borg-key.txt
sudo chmod 600 /root/borg-key.txt && sudo chown root:root /root/borg-key.txt
# Optional paper copy:
sudo borg key export --paper /tank/Secure/Borg/backup-repo > /root/borg-key-paper.txt
sudo chmod 600 /root/borg-key-paper.txt && sudo chown root:root /root/borg-key-paper.txt
```
7) Optional manual test run:
```bash
sudo systemctl start borg-backup.service
```
8) Enable timers:
```bash
sudo make enable
```
9) Optional sanity check:
```bash
sudo make check
```

## Validate and test
- Status: `systemctl status borg-backup.service borg-check.service borg-check-verify.service` and `systemctl list-timers borg-*`
- Logs: `/var/log/borg/backup_YYYY-MM-DD.log`, `check_YYYY-MM-DD.log`, `check_verify_YYYY-MM-DD.log`; journal via `journalctl -u borg-backup.service -n 100`
- Restore test (recommended periodically):
```bash
export BORG_PASSPHRASE='your-passphrase'
mkdir -p /restore/tmp/borg-test
borg list /tank/Secure/Borg/backup-repo
borg list /tank/Secure/Borg/backup-repo::backup-myhost-2025-01-01T02:30
cd /restore/tmp/borg-test
borg extract /tank/Secure/Borg/backup-repo::backup-myhost-2025-01-01T02:30
```

## Repository layout
- `scripts/`: Bash entrypoints (`borg_nightly.sh`, `borg_check.sh`, `borg_check_verify.sh`).
- `systemd/`: `borg-*.service` and `borg-*.timer` units installed flat into `/etc/systemd/system/`.
- `packaging/logrotate/borg`: logrotate policy for `/var/log/borg/*.log`.
- `docs/`: original operational notes (`Borg Backup Archive -- Backup Server.md`).
- `borg.env.example`: sample environment; real config lives beside installed scripts.
- `Makefile`: install, enable/disable, status, check, uninstall targets.

## Security model and configuration
- Secrets/config are not committed. Use `/usr/local/sbin/borg/borg.env` (0600 root:root); start from `borg.env.example`.
- Services load `EnvironmentFile=/usr/local/sbin/borg/borg.env`; scripts require `BORG_PASSPHRASE` and honor the same path (legacy fallback to `/tank/Secure/Secrets/.borg_env` if unset).
- Logrotate installs to `/etc/logrotate.d/borg`; runtime logs stay in `/var/log/borg/`.

Key variables in `/usr/local/sbin/borg/borg.env`:
- `BORG_PASSPHRASE` (required) — repo encryption passphrase
- `BORG_REPO` — default `/tank/Secure/Borg/backup-repo`
- `SOURCE_PATH` — default `/tank/Secure/backup`
- `ZFS_DATASET` — default `tank/Secure/backup`
- `REPO_DATASET` — optional dataset hosting the repo, e.g., `tank/Secure/Borg`
- `LOG_DIR` — default `/var/log/borg`
- `MAIL_TO` / `MAIL_FROM` — msmtp notification addresses
- `MAIL_ON_SUCCESS` / `MAIL_ON_FAILURE` — `true/false` (or `1/0`) to send or suppress

## Borg Passphrase Handling
- Default (recommended): env file at `/usr/local/sbin/borg/borg.env` (0600 root:root), loaded by systemd and scripts.
- Optional `pass`/GPG (operator-managed):
```bash
export BORG_PASSPHRASE="$(pass show backups/borg)"   # requires unlocked GPG key/pass store
sudo systemctl start borg-backup.service
```
> Pros: keeps passphrase outside flat files. Cons: unattended timers require GPG key+store unlocked at boot.

## Borg Repository Initialization (Encrypted)
- Recommended mode: `repokey-blake2` (encrypts data+metadata with repo-embedded key + passphrase).
- One-time per repo path; run only when the dataset is unlocked/mounted.
```bash
sudo zfs load-key tank/Secure/Borg
sudo zfs mount tank/Secure/Borg
export BORG_PASSPHRASE='same-passphrase-set-in-borg.env'
sudo borg init --encryption=repokey-blake2 /tank/Secure/Borg/backup-repo
sudo borg info /tank/Secure/Borg/backup-repo
```
> Keep the repo inside the intended dataset/mount. If missing: create/mount the ZFS dataset (see Quickstart step 5) or provision ext4 on a dedicated device.

## Borg Key Export (CRITICAL)
- Encrypted repos need key material plus the passphrase. Export after init/changes and store off-host.
```bash
sudo borg key export /tank/Secure/Borg/backup-repo /root/borg-key.txt
sudo chmod 600 /root/borg-key.txt && sudo chown root:root /root/borg-key.txt
sudo borg key export --paper /tank/Secure/Borg/backup-repo > /root/borg-key-paper.txt
sudo chmod 600 /root/borg-key-paper.txt && sudo chown root:root /root/borg-key-paper.txt
```
> Keep keys off the backup host (encrypted USB, password manager secure file, printed and stored securely). Do NOT store with the repo, on the same dataset, in Git, or in unencrypted cloud storage.
> Checklist: key exported ✅ / passphrase recorded ✅ / restore tested ✅

## Restore Instructions
- Always restore into a new/empty directory and verify before touching live data.
```bash
export BORG_PASSPHRASE='your-passphrase'
mkdir -p /restore/tmp/borg-test
borg list /tank/Secure/Borg/backup-repo
borg list /tank/Secure/Borg/backup-repo::backup-myhost-2025-01-01T02:30
cd /restore/tmp/borg-test
borg extract /tank/Secure/Borg/backup-repo::backup-myhost-2025-01-01T02:30
borg extract /tank/Secure/Borg/backup-repo::backup-myhost-2025-01-01T02:30 path/inside/archive
```
> After restore: verify permissions/ownership and integrity; avoid overwriting live data—copy validated files during a planned window.

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
  - Monitor timers: nightly backup, weekly `borg check`, monthly `borg check --verify-data`
  - Review `/var/log/borg/` and `systemctl list-timers borg-*`

## Troubleshooting
- Dataset locked/unmounted: scripts log “not mounted/unavailable” and exit 0. Unlock/mount `ZFS_DATASET` (and optional `REPO_DATASET`), then `systemctl start borg-backup.service` or wait for the timer.
- Missing env or wrong perms: ensure `/usr/local/sbin/borg/borg.env` exists, has `BORG_PASSPHRASE`, and is `0600 root:root`; rerun `sudo make install` if needed and use `sudo make check`.

## Makefile targets (common)
- `make install` / `make install-force` (overwrite borg.env): install scripts/units/logrotate; reload systemd.
- `make enable` / `make disable`: enable/disable timers.
- `make status`: show service/timer status and timers list.
- `make check`: sanity-check installed paths/perms/logrotate.
- `make uninstall`: remove installed units/scripts/logrotate (keeps `borg.env`).

## Credits
Built on BorgBackup, ZFS, systemd, msmtp, and logrotate.

## License
See [LICENSE](LICENSE).
