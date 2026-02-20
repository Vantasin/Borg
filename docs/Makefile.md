# Makefile Reference

This document summarizes Make targets and their effects.

See also:
- [Scripts](Scripts.md)
- [Systemd](Systemd.md)
- [Configuration](Configuration.md)

## install
- Copies scripts to `/usr/local/sbin/borg`.
- Installs systemd units to `/etc/systemd/system`.
- Seeds `/usr/local/sbin/borg/borg.env` if missing.
- Removes stale installed files using the manifest.
- Reloads systemd.

## install-force
- Same as `install` but overwrites `borg.env`.
- Creates a timestamped backup with `0600` permissions.

## enable
- Enables systemd timers for backup/check/verify/log-cleanup.
- Implies `install`.

## disable
- Disables all Borg timers.

## deploy
- Convenience target: `install` + `enable` + `status`.

## status
- Shows systemd service status for Borg units.
- Lists Borg timers.

## check
- Validates installed scripts and permissions.
- Validates unit files exist.

## uninstall
- Disables timers, removes installed scripts and units.
- Preserves `/usr/local/sbin/borg/borg.env`.

## help
- Lists available targets.
