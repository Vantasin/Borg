# Configuration Reference

This document covers `borg.env.example` and the runtime env file.

See also:
- [Scripts](Scripts.md)
- [Systemd](Systemd.md)
- [Makefile](Makefile.md)

## borg.env.example
The example file documents supported environment variables and defaults.

Common variables:
- `BORG_REPO`: repository path.
- `SOURCE_PATH`: source dataset mountpoint.
- `ZFS_DATASET`: dataset name for snapshotting.
- `REPO_DATASET`: optional ZFS dataset that holds the repo.
- `ARCHIVE_PREFIX`: archive name prefix.
- `BORG_LOCK_WAIT`: seconds to wait on Borg repo locks.
- `LOG_DIR`, `LOG_RUN_DIR`: log locations.
- `LOG_RETENTION_DAYS`: log cleanup retention.
- `MAIL_TO`, `MAIL_FROM`: email routing for `msmtp`.
- `MAIL_ON_SUCCESS`, `MAIL_ON_FAILURE`, `MAIL_ON_SKIP`: notification controls.

## Runtime env file
The runtime file is `/usr/local/sbin/borg/borg.env`.

Rules:
- Must be `0600 root:root`.
- Must contain a `BORG_PASSPHRASE` or otherwise provide it via environment.
- This file is not versioned.

Backup behavior:
- `make install` will create it if missing.
- `make install-force` overwrites it and creates a timestamped backup in the same directory.
