# MySQL Daily Backup Script with XtraBackup

[![ShellCheck](https://img.shields.io/badge/shellcheck-passed-brightgreen)](https://www.shellcheck.net/)
[![Bash Compatible](https://img.shields.io/badge/bash-compatible-blue.svg)](https://www.gnu.org/software/bash/)

This Bash script automates daily backups of MySQL 8.0.x databases, compresses backup data, securely transfers files to a remote server and AWS S3, and sends a daily report to administrators via email.

## Features

- Full or incremental backups depending on the day
- Backup compression using `tar` and `zstd`
- Secure transfer to remote server via `rsync`
- Upload backup archives to AWS S3 (supports configurable storage class, e.g., `GLACIER_IR`)
- Optional transfer toggles for `rsync` and `S3` via `enable_rsync`, `enable_s3`
- Automatic cleanup of old backups based on retention settings
- Daily report delivery via email using `msmtp`
- Highly configurable via simple variable edits

## Requirements

The following tools must be installed and available in your system's `PATH`:

- ⚠️ **Percona XtraBackup ≥ 8.0.12**  
  Used to perform physical backups of MySQL databases.  
  Version 8.0.12 or higher is required to support `--login-path`, which allows secure passwordless authentication via `mysql_config_editor`.

- ⚠️ **AWS CLI v2 (`aws`)**  
  Used to upload compressed backup archives to AWS S3.  
  Version 2 is required to support options like `--storage-class` and improved authentication.  
  Make sure to configure credentials via `aws configure` or environment variables.

- **rsync**  
  Used to securely transfer backup archives to a remote server over SSH.  
  Requires proper SSH access to the remote host.

- **msmtp**  
  Lightweight SMTP client used to send daily backup reports via email.  
  Requires SMTP server configuration and credentials.

- **zstd**  
  Compression tool used with `tar` to reduce backup archive size efficiently using multithreaded compression.

## Configuration

Edit the following variables inside the script:

| Variable                                                                   | Description                                          |
| -------------------------------------------------------------------------- | ---------------------------------------------------- |
| `backup_dir`                                                               | Local directory for backups                          |
| `defaults_file`                                                            | Path to MySQL configuration file (`my.cnf`)          |
| `socket`                                                                   | MySQL socket path                                    |
| `login_path`                                                               | MySQL authentication profile (via mysql_config_editor) |
| `remote_backup_dir`, `remote_backup_host`, `remote_user`                   | Remote server settings                               |
| `remote_backup_dir2`                                                       | AWS S3 bucket and path                               |
| `enable_rsync`                                                             | Set to `true` or `false` to enable/disable remote server transfer |
| `enable_s3`                                                                | Set to `true` or `false` to enable/disable AWS S3 upload |
| `aws_cli`                                                                  | Path to AWS CLI binary                               |
| `s3_storage_class`                                                         | S3 storage class for uploaded archives               |
| `smtp_server`, `smtp_user`, `smtp_pass`, `mail_sender`, `report_recipient` | SMTP settings for sending emails                     |
| `company_name`, `company_team`, `mail_subject_prefix`                      | Company branding for email reports                   |
| `backup_retention_days`                                                    | Number of days to retain local backups               |
| `full_backup_day`                                                          | Day to perform a full backup (e.g., `Sun`, `Monday`) |

> **Tip:**
>
> Backup files are automatically named and organized by date.
>
> Example:
> - `full-2025-04-29/` (raw full backup directory)
> - `full-2025-04-29.tar.zst` (compressed archive)
> - `incremental-2025-04-30/` (raw incremental backup)
> - `incremental-2025-04-30.tar.zst` (compressed archive)
>
> **MySQL Authentication:**  
> This script uses `mysql_config_editor` login profiles (via `--login-path`) to authenticate securely without exposing passwords inside the script.
>
> To create a login profile, run:
>
> ```bash
> mysql_config_editor set --login-path=your_login_profile --host=localhost --user=root --password --port=3306
> ```
>
> You can verify the connection with:
>
> ```bash
> mysql --login-path=your_login_profile --socket=/path/to/mysql.sock
> ```
>
> This allows passwordless and secure authentication for all `xtrabackup` operations.

## How It Works

This script follows a weekly backup strategy consisting of:

- **One full backup per week** on a designated day (e.g., Sunday), configured via `full_backup_day`
- **Daily incremental backups** for the remaining days, each based on the most recent backup

The backup process works as follows:

1. Determine if today matches the configured full backup day
2. Perform a **full** backup or an **incremental** backup based on the latest backup found
3. Compress the backup directory into a `.tar.zst` archive
4. Conditionally transfer the archive to a remote server and/or AWS S3 depending on toggle flags
5. Remove old local backups based on the retention setting
6. Send a daily email report to the administrator

## Example Usage

Manual run:

```bash
bash dailybackup.sh
```

Scheduled daily run (via crontab):

```bash
0 2 * * * /bin/bash /path/to/dailybackup.sh
```

> **Recommendation:**
>
> Schedule backups during low-traffic hours (e.g., early morning).

## Notes

- You can enable or disable remote server (`rsync`) and AWS S3 transfers independently using `enable_rsync` and `enable_s3` flags.
- If both transfer options are disabled, backups are still created and compressed, but **not transferred or deleted**.
- The backup file is deleted **only if all enabled transfers succeed**.
- If either transfer fails, the file is retained and a warning is logged.
- Full backups are performed only on the configured day, otherwise incremental backups are created.
- Logging is detailed and saved at `${backup_dir}/backup.log` daily.

## Email Example

### Daily Backup Report Email

```
Subject: [YourCompanyName] Backup Report of MySQL Database

Daily Backup Report

2025-04-29 02:00:00 - Full backup completed: /path/to/backup/full-2025-04-29
2025-04-29 02:15:00 - Compressed backup directory: /path/to/backup/full-2025-04-29
2025-04-29 02:20:00 - rsync transfer skipped (disabled)
2025-04-29 02:21:00 - S3 upload successful: /path/to/backup/full-2025-04-29.tar.zst
2025-04-29 02:23:00 - Deleted backup file after successful transfers: /path/to/backup/full-2025-04-29.tar.zst
2025-04-29 02:24:00 - Completed cleanup of backups older than 3 days.

- YourCompanyName IT Team
```

---

## Contributions

Pull requests are welcome!
If you find a bug or have ideas for improvements, feel free to open an issue.

