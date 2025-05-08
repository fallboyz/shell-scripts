# MySQL Daily Backup Script with XtraBackup

[![ShellCheck](https://img.shields.io/badge/shellcheck-passed-brightgreen)](https://www.shellcheck.net/)
[![Bash Compatible](https://img.shields.io/badge/bash-compatible-blue.svg)](https://www.gnu.org/software/bash/)

This Bash script automates daily backups of MySQL 8.0.x databases, compresses backup data, securely transfers files to a remote server and AWS S3, and sends a daily report to administrators via email.

## Features

* Full or incremental backups depending on the day
* Backup compression using `tar` and `zstd`
* Secure transfer to remote server via `rsync`
* Upload backup archives to AWS S3 (supports configurable storage class, e.g., `GLACIER_IR`)
* Optional transfer toggles for `rsync` and `S3` via `enable_rsync`, `enable_s3`
* Automatic cleanup of old backups based on retention settings
* Daily report delivery via email using `msmtp`
* Highly configurable via simple variable edits
* Connection options for MySQL (`defaults_file` and `socket`) are automatically validated before use. If invalid or missing, safe defaults are applied.

## Requirements

The following tools must be installed and available in your system's `PATH`:

* ⚠️ **Percona XtraBackup ≥ 8.0.12**  
  Used to perform physical backups of MySQL databases.  
  Version 8.0.12 or higher is required to support `--login-path`, which allows secure passwordless authentication via `mysql_config_editor`.

* ⚠️ **AWS CLI v2 (`aws`)**  
  Used to upload compressed backup archives to AWS S3.  
  Version 2 is required to support options like `--storage-class` and improved authentication.  
  Make sure to configure credentials via `aws configure` or environment variables.

* **rsync**  
  Used to securely transfer backup archives to a remote server over SSH.  
  Requires proper SSH access to the remote host.

* **msmtp**  
  Lightweight SMTP client used to send daily backup reports via email.  
  Requires SMTP server configuration and credentials.

* **zstd**  
  Compression tool used with `tar` to reduce backup archive size efficiently using multithreaded compression.

## Configuration

Edit the following variables inside the script:

| Variable                | Description                                                                                       |
| ----------------------- | ------------------------------------------------------------------------------------------------- |
| `backup_dir`            | Local directory for backups                                                                       |
| `backup_exec`           | Path to the `xtrabackup` binary                                                                   |
| `defaults_file`         | Path to MySQL configuration file (`my.cnf`). If empty or invalid, defaults to `/etc/my.cnf`       |
| `socket`                | MySQL socket path. If empty or invalid, connection will fallback to `login_path` profile defaults |
| `login_path`            | MySQL authentication profile (via mysql\_config\_editor)                                          |
| `backup_retention_days` | Number of days to retain local backups                                                            |
| `log_file`              | Path for the general backup log file                                                              |
| `xtrabackup_log`        | Path for the detailed XtraBackup log                                                              |
| `enable_rsync`          | Enable (`true`) or disable (`false`) remote server transfer                                       |
| `remote_backup_dir`     | Remote directory for backups                                                                      |
| `remote_backup_host`    | Remote server IP or hostname                                                                      |
| `remote_user`           | Username for SSH connection to the remote server                                                  |
| `rsync_opt`             | Additional options for the rsync command                                                          |
| `enable_s3`             | Enable (`true`) or disable (`false`) AWS S3 upload                                                |
| `remote_backup_dir2`    | AWS S3 bucket and path                                                                            |
| `aws_cli`               | Path to the AWS CLI binary                                                                        |
| `s3_storage_class`      | AWS S3 storage class (e.g., `GLACIER_IR`)                                                         |
| `smtp_server`           | SMTP server for sending emails                                                                    |
| `smtp_port`             | SMTP port                                                                                         |
| `smtp_use_tls`          | Use TLS for email (`true` or `false`)                                                             |
| `smtp_auth`             | Use SMTP authentication (`true` or `false`)                                                       |
| `smtp_user`             | SMTP username                                                                                     |
| `smtp_pass`             | SMTP password                                                                                     |
| `mail_sender`           | Sender email address                                                                              |
| `report_recipient`      | Recipient email address                                                                           |
| `company_name`          | Your company name                                                                                 |
| `company_team`          | Your company team or department                                                                   |
| `mail_subject_prefix`   | Prefix for the email subject line                                                                 |
| `full_backup_day`       | Day to perform a full backup (e.g., `Sun`, `Monday`)                                              |

> **Tip:**
> Backup files are automatically named and organized by date.
>
> Example:
>
> * `full-2025-04-29/` (raw full backup directory)
> * `full-2025-04-29.tar.zst` (compressed archive)
> * `incremental-2025-04-30/` (raw incremental backup)
> * `incremental-2025-04-30.tar.zst` (compressed archive)

> **MySQL Authentication:**
> This script uses `mysql_config_editor` login profiles to authenticate securely without exposing passwords inside the script.
>
> To create a login profile:
>
> ```bash
> mysql_config_editor set --login-path=your_login_profile --host=localhost --user=root --password --port=3306
> ```
>
> Test the connection:
>
> ```bash
> mysql --login-path=your_login_profile --socket=/path/to/mysql.sock
> ```

## How It Works

This script follows a weekly backup strategy:

1. Determine if today matches the configured full backup day.
2. Perform a **full** or **incremental** backup based on the latest backup.
3. Compress the backup directory into a `.tar.zst` archive.
4. Transfer the archive to a remote server and/or AWS S3 based on settings.
5. Remove old local backups based on the retention setting.
6. Send a daily email report to the administrator.

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
> Schedule backups during low-traffic hours (e.g., early morning).

## Notes

* If both `rsync` and `S3` transfers are disabled, backups are still created and compressed, but not transferred or deleted.
* Backup files are deleted only if **all enabled transfers succeed**.
* If any transfer fails, the file is retained and a warning is logged.
* Full backups are performed only on the configured day; otherwise, incremental backups are created.
* Logging is saved daily at `${log_file}` and `${xtrabackup_log}`.

## Email Example

```
Subject: [YourCompanyName] Backup Report of MySQL Database

Backup Report of MySQL Database

============================== Backup Summary ==============================
2025-04-29 02:00:00 - Full backup completed: /path/to/backup/full-2025-04-29
2025-04-29 02:15:00 - Compressed backup directory: /path/to/backup/full-2025-04-29
2025-04-29 02:20:00 - rsync transfer skipped (disabled)
2025-04-29 02:21:00 - S3 upload successful: /path/to/backup/full-2025-04-29.tar.zst
2025-04-29 02:23:00 - Deleted backup file after successful transfers: /path/to/backup/full-2025-04-29.tar.zst
2025-04-29 02:24:00 - Completed cleanup of backups older than3 days.

============================ XtraBackup Details ============================
(Output from xtrabackup.log)
============================================================================

YourCompanyName IT Team
```

---

## Contributions

Pull requests are welcome!
If you find a bug or have ideas for improvements, feel free to open an issue.

