---
title: Borg Backup Archive -- Backup Server
updated: 2025-12-12 00:59:42Z
created: 2025-11-30 20:37:35Z
latitude: 0.00000000
longitude: 0.00000000
altitude: 0.0000
tags:
  - borg backup
---

This document describes the complete, production-grade **BorgBackup  
archive system** running on the **Backup Raspberry Pi 5**. It covers  
**design, security model, setup, automation, alerting, and disaster  
recovery**, using real paths and services from this system.

* * *

## 1\. High-Level System Design

```
Live Server (ZFS)
   ↓ (Syncoid Pull via Restricted SSH)
Backup Server (Encrypted ZFS)
   → tank/Secure/backup
   → Borg Archive:
      /tank/Secure/Borg/backup-repo (Encrypted Borg)
   → ZFS Snapshots + Optional Offline Export
```

* * *

## 2\. ZFS Dataset Layout

### Encrypted ZFS Datasets

```
/tank/Secure/backup
/tank/Secure/Borg
/tank/Secure/Borg/backup-repo
```

### Create Borg Dataset

```bash
sudo zfs create tank/Secure/Borg   -o compression=zstd   -o atime=off   -o recordsize=1M
```

### Secure Permissions

```bash
sudo chown -R root:root /tank/Secure/Borg
sudo chmod -R 700 /tank/Secure/Borg
```

* * *

## 3\. Borg Installation

```bash
sudo apt update
sudo apt install borgbackup -y
```

* * *

## 4\. Borg Repository Initialization (Encrypted)

```bash
sudo borg init --encryption=repokey-blake2   /tank/Secure/Borg/backup-repo
```

* * *

## 5\. Borg Passphrase Handling

Create environment file:

```bash
sudo nano /root/.borg_env
```

```bash
export BORG_PASSPHRASE='long-random-passphrase'
```

Secure it:

```bash
sudo chmod 600 /root/.borg_env
sudo chown root:root /root/.borg_env
```

* * *

## 6\. Borg Key Export (CRITICAL)

```bash
sudo borg key export   /tank/Secure/Borg/backup-repo   /root/borg-key.txt
```

Secure the key:

```bash
sudo chmod 600 /root/borg-key.txt
sudo chown root:root /root/borg-key.txt
```

### Required Storage Locations

- Vaultwarden\\
- Local VeraCrypt (`codes.hc`)\\
- Offline USB VeraCrypt (`locked.hc`)

* * *

## 7\. Nightly Borg Backup Script

**Path**

```
/usr/local/sbin/borg/borg_nightly.sh
```

### Variables

```bash
ZFS_DATASET="tank/Secure/backup"
SOURCE_PATH="/tank/Secure/backup"
BORG_REPO="/tank/Secure/Borg/backup-repo"
```

### Workflow

1.  Create ZFS snapshot
2.  `borg create`
3.  `borg prune`
4.  Destroy snapshot
5.  Send email alert
6.  Write logs to `/var/log/borg`

* * *

## 8\. Systemd Automation

```
borg-backup.service
borg-backup.timer
```

Runs nightly at:

```
02:30
```

* * *

## 9\. Weekly Borg Metadata Check

```
Script: /usr/local/sbin/borg/borg_check.sh
Timer: Sunday @ 04:30
```

```bash
borg check /tank/Secure/Borg/backup-repo
```

* * *

## 10\. Monthly Borg Deep Verification

```
Script: /usr/local/sbin/borg/borg_check_verify.sh
Timer: 15th @ 04:45
```

```bash
borg check --verify-data /tank/Secure/Borg/backup-repo
```

* * *

## 11\. Email Alerting

All alerts are delivered via **msmtp** to:

```
alerts@example.com
```

* * *

## 12\. Monitoring

System Frequency

* * *

ZFS Scrub Weekly  
SMART Short Test Weekly  
SMART Long Test Monthly  
Syncoid Replication Daily

* * *

## 13\. Restore Examples

### List Archives

```bash
borg list /tank/Secure/Borg/backup-repo
```

### Restore Archive

```bash
borg extract /tank/Secure/Borg/backup-repo::archive-name
```

* * *

## 14\. Disaster Recovery Requirements

To restore the full system you **must have**:

- Borg repository copy\\
- `borg-key.txt`\\
- Borg passphrase\\
- ZFS dataset encryption key

* * *

## 15\. System Status

- Encrypted ZFS datasets active\\
- Encrypted Borg repository active\\
- Automated nightly backups\\
- Weekly + Monthly integrity verification\\
- Email alerting validated\\
- **System is production-grade and compliant with modern standards**
