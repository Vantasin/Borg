# Borg Automation

BorgBackup automation for a single live host and a single backup host on Debian/systemd with encrypted ZFS datasets. Nightly backups plus weekly and monthly integrity checks run via systemd timers. If required ZFS datasets are unavailable, scripts log and exit 0 so timers retry after storage is online.

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
3) Install scripts/units/logrotate (seeds borg.env if missing):
```bash
sudo make install
```
> To force overwrite of borg.env: `sudo make install-force`.

4) Configure runtime env (0600 root:root):
```bash
sudo nano /usr/local/sbin/borg/borg.env
```
5) Create storage:
- ZFS example:
```bash
sudo zfs create tank/Secure/Borg
```
- ext4 example:
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
>Tip: use tmux to avoid interruption if SSH drops:

```bash
tmux new -s borg-test
```
split pane: `Ctrl-b` then `"`
```bash
sudo systemctl start borg-backup.service
```
> Run manual backup in pane 1

```bash
tail -f /var/log/borg/backup_$(date +%F).log
```
> Follow backup progress in pane 2

> detach: Ctrl-b then d; reattach: tmux attach -t borg-test

9) Enable timers:
```bash
sudo make enable
```
10) Optional sanity check:
```bash
sudo make check
```

## Validate and test
### Status:
- `systemctl status borg-backup.service borg-check.service borg-check-verify.service`
- `systemctl list-timers borg-*`

### Logs:
- `/var/log/borg/backup_YYYY-MM-DD.log`
- `check_YYYY-MM-DD.log`
- `check_verify_YYYY-MM-DD.log`
- journal via `journalctl -u borg-backup.service -n 100`

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
  - Monitor timers: nightly backup, weekly `borg check`, monthly `borg check --verify-data`
  - Review `/var/log/borg/` and `systemctl list-timers borg-*`

## Troubleshooting
- Dataset absent: create the dataset (ZFS `zfs create ...` or mkdir for ext4) at the intended path, then rerun.
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
