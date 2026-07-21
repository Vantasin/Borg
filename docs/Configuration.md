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
- `BORG_KEEP_DAILY`: daily archive retention count (default `7`).
- `BORG_KEEP_WEEKLY`: weekly archive retention count (default `4`).
- `BORG_KEEP_MONTHLY`: monthly archive retention count (default `12`).
- `BORG_KEEP_YEARLY`: yearly archive retention count (default `0`).
- `LOG_DIR`, `LOG_RUN_DIR`: log locations.
- `LOG_RETENTION_DAYS`: log cleanup retention.
- `MAIL_TO`, `MAIL_FROM`: email routing for `msmtp`.
- `MAIL_ON_SUCCESS`, `MAIL_ON_FAILURE`, `MAIL_ON_SKIP`: notification controls.
- `TEST_STATUS` / `BORG_TEST_STATUS`: one-off manual email test mode for `borg_check.sh` and `borg_check_verify.sh` (`ok`, `warn`, `fail`, `skip`). Do not store these in the runtime env file.

Archive retention:
- Values must be non-negative integers.
- `0` disables the corresponding retention tier.
- Missing values use the defaults `7/4/12/0`, so existing installations remain backward compatible.

## Runtime env file
The runtime file is `/usr/local/sbin/borg/borg.env`.

Rules:
- Must be `0600 root:root`.
- Must contain a `BORG_PASSPHRASE` or otherwise provide it via environment.
- This file is not versioned.

Backup behavior:
- `make install` will create it if missing.
- `make install-force` overwrites it and creates a timestamped backup in the same directory.
