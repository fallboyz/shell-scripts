#!/bin/bash
# script name : mysql_xtrabackup_daily_backup.sh
# description : Daily backup script for MySQL 8.0.x (requires Percona XtraBackup 8.0.12+)
# author      : island_of_hermit <fallboyz@umount.net>
# date        : 2024-04-12
# modify      : 2025-04-30
#
# set -x
#
# 백업 관련 설정
backup_dir="/path/to/backup"
backup_exec="/usr/bin/xtrabackup"
defaults_file="/path/to/my.cnf"
socket="/path/to/mysql.sock"

# mysql_config_editor를 이용해 등록한 프로파일
login_path="your_login_profile"

# 로깅 및 유지 기간 설정
backup_retention_days=3
log_file="${backup_dir}/backup.log"

# Rsync 전송 설정
enable_rsync=true
remote_backup_dir="/path/to/remote-backup-dir/"
remote_backup_host="your.remote.server.ip.or.hostname"
remote_user="your_remote_user"
rsync_opt=(-e "ssh -o StrictHostKeyChecking=no")

# AWS S3 업로드 설정
enable_s3=true
remote_backup_dir2="your-bucket-name/backup-path/"
aws_cli="/usr/bin/aws"
s3_storage_class="GLACIER_IR"

# SMTP 기본 설정 (msmtp 패키지 설치 필요)
smtp_server="your.smtp.server"
smtp_port=587
smtp_use_tls=true
smtp_auth=true
smtp_user="your_smtp_user@example.com"
smtp_pass="your_smtp_password"

# 수/발신인 설정
mail_sender="backup_sender@example.com"
report_recipient="admin_recipient@example.com"

# 회사 및 공통 설정
company_name="YourCompanyName"
company_team="${company_name} IT Team"
mail_subject_prefix="[${company_name}]"

# 풀 백업을 수행할 요일 설정
# - 예: Sun, Mon, Tue, ... 또는 Sunday, Monday, ... (대소문자 구분 없음)
full_backup_day="Sun"

# 로그 기록 함수
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ${1}" >> "${log_file}"
}

# 요일 반환 함수
get_day_of_week() {
    local short_day full_day
    short_day=$(date +%a | tr '[:upper:]' '[:lower:]')
    full_day=$(date +%A | tr '[:upper:]' '[:lower:]')
    echo "${short_day} ${full_day}"
}

# CPU 코어 개수를 계산하여 반환하는 함수
get_cpu_cores() {
    local cores

    cores=$(grep -c ^processor /proc/cpuinfo)
    echo $((cores / 2))
}

# 지정한 일 수만큼 과거 날짜를 반환하는 함수
get_past_date() {
    local days_ago=$1

    date -d "${days_ago} days ago" +%Y-%m-%d
}

# 메일 커맨드 빌드 함수
build_mail_command() {
    local cmd="msmtp -f ${mail_sender} --host=${smtp_server} --port=${smtp_port}"

    if [[ "${smtp_use_tls}" == true ]]; then
        cmd+=" --tls=on"
    else
        cmd+=" --tls=off"
    fi

    if [[ "${smtp_auth}" == true ]]; then
        cmd+=" --auth=on --user=${smtp_user} --passwordeval='echo ${smtp_pass}'"
    else
        cmd+=" --auth=off"
    fi

    echo "${cmd}"
}

# 백업 리포트 메일 발송 함수
send_backup_report() {
    local mail_subject
    mail_subject="${mail_subject_prefix} Backup Report of MySQL Database"

    mail_command=$(build_mail_command)

    {
        echo "Subject: ${mail_subject}"
        echo "From: ${mail_sender}"
        echo "To: ${report_recipient}"
        echo ""
        echo "Daily Backup Report"
        echo ""
        cat "${log_file}"
        echo ""
        echo "- ${company_team}"
    } | ${mail_command} "${report_recipient}"
}

# 원격 서버로 백업 파일을 전송하는 함수
transfer_backup_to_remote() {
    local backup_file=$1

    if rsync -az \
        "${rsync_opt[@]}" \
        "${backup_file}" \
        "${remote_user}@${remote_backup_host}:${remote_backup_dir}" >> "${log_file}" 2>&1; then
        log "[info] rsync transfer successful: ${backup_file}"
        return 0
    else
        log "[warn] rsync transfer failed: ${backup_file}"
        return 1
    fi
}

# AWS S3에 백업 파일을 업로드하는 함수
upload_backup_to_s3() {
    local backup_file=$1

    if "${aws_cli}" s3 cp \
        "${backup_file}" \
        "s3://${remote_backup_dir2}" \
        --storage-class "${s3_storage_class}" >> "${log_file}" 2>&1; then
        log "[info] S3 upload successful: ${backup_file}"
        return 0
    else
        log "[warn] S3 upload failed: ${backup_file}"
        return 1
    fi
}

# 백업 파일을 삭제하는 함수
cleanup_backup() {
    local backup_file=$1

    rm -f "${backup_file}"
    log "[info] Deleted backup file after successful transfers: ${backup_file}"
}

# 원격 서버 및 S3로 백업 파일을 전송하는 함수
transfer_backup() {
    local backup_file="$1"
    local rsync_result=0
    local s3_result=0

    if [ "${enable_rsync}" = true ]; then
        if transfer_backup_to_remote "${backup_file}"; then
            log "[info] rsync transfer success"
        else
            log "[warn] rsync transfer failed"
            rsync_result=1
        fi
    else
        log "[info] rsync transfer skipped (disabled)"
    fi

    if [ "${enable_s3}" = true ]; then
        if upload_backup_to_s3 "${backup_file}"; then
            log "[info] S3 upload success"
        else
            log "[warn] S3 upload failed"
            s3_result=1
        fi
    else
        log "[info] S3 upload skipped (disabled)"
    fi

    if [ "${rsync_result}" -eq 0 ] && [ "${s3_result}" -eq 0 ]; then
        cleanup_backup "${backup_file}"
    else
        log "[warn] Transfer failed or skipped. Backup file not deleted: ${backup_file}"
    fi
}

# 설정된 기간보다 오래된 백업 디렉토리를 삭제하는 함수
cleanup_old_backups() {
    local expiration_date

    expiration_date=$(get_past_date "${backup_retention_days}")

    find "${backup_dir}" -maxdepth 1 -type d \( -name "full-????-??-??" -o -name "incremental-????-??-??" \) |
        while read -r dir; do
            local dir_date

            dir_date=$(basename "${dir}" | grep -o "[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}")
            if [[ "${dir_date}" < "${expiration_date}" ]]; then
                rm -rf "${dir}"
                log "[info] Deleted old backup directory: ${dir} (${dir_date})"
            fi
        done

    log "[info] Completed cleanup of backups older than ${backup_retention_days} days."
}

# 백업 디렉토리를 tar.zst로 압축하는 함수
compress_backup() {
    local target_dir=$1
    local archive_name

    archive_name="$(basename "${target_dir}").tar.zst"

    if ! tar -cf - \
        -C "${target_dir}" . | zstd -T0 -15 -o "${backup_dir}/${archive_name}"; then
        log "[error] Failed to compress backup directory: ${target_dir}"
        exit 1
    fi

    log "[info] Compressed backup directory: ${target_dir}"
    echo "${backup_dir}/${archive_name}"
}

# 풀 백업을 수행하는 함수
perform_full_backup() {
    local target_dir
    local compressed_file

    target_dir="${backup_dir}/full-$(date +%Y-%m-%d)"
    mkdir -p "${target_dir}"

    if ! "${backup_exec}" --backup \
        --parallel="$(get_cpu_cores)" \
        --login-path="${login_path}" \
        --defaults-file="${defaults_file}" \
        --socket="${socket}" \
        --target-dir="${target_dir}" >> "${log_file}" 2>&1; then
        log "[error] Full backup failed: ${target_dir}"
        exit 1
    fi

    log "[info] Full backup completed: ${target_dir}"

    compressed_file=$(compress_backup "${target_dir}")
    transfer_backup "${compressed_file}"
}

# 증분 백업을 수행하는 함수
perform_incremental_backup() {
    local base_dir=$1
    local target_dir
    local compressed_file

    target_dir="${backup_dir}/incremental-$(date +%Y-%m-%d)"
    mkdir -p "${target_dir}"

    if ! "${backup_exec}" --backup \
        --parallel="$(get_cpu_cores)" \
        --incremental-basedir="${base_dir}" \
        --login-path="${login_path}" \
        --defaults-file="${defaults_file}" \
        --socket="${socket}" \
        --target-dir="${target_dir}" >> "${log_file}" 2>&1; then
        log "[error] Incremental backup failed: ${target_dir} (base: ${base_dir})"
        exit 1
    fi

    log "[info] Incremental backup completed: ${target_dir} (base: ${base_dir})"

    compressed_file=$(compress_backup "${target_dir}")
    transfer_backup "${compressed_file}"
}

# 메인 실행 흐름
main() {
    true > "${log_file}"

    local last_backup_dir
    local short_day
    local full_day

    read -r short_day full_day <<< "$(get_day_of_week)"
    last_backup_dir=$(find "${backup_dir}" -maxdepth 1 -type d -name "*-*" -print | sort -r | head -1)

    local target_day
    target_day=$(echo "${full_backup_day}" | tr '[:upper:]' '[:lower:]')

    if [ "${short_day}" = "${target_day}" ] || [ "${full_day}" = "${target_day}" ]; then
        perform_full_backup
    else
        if [ "${short_day}" != "${target_day}" ] && [ "${full_day}" != "${target_day}" ]; then
            log "[error] Invalid full_backup_day setting: '${full_backup_day}' does not match current day '${short_day}' or '${full_day}'"
            exit 1
        fi

        if [ -n "${last_backup_dir}" ]; then
            perform_incremental_backup "${last_backup_dir}"
        else
            log "[warn] No previous backup found. Performing full backup."
            perform_full_backup
        fi
    fi

    cleanup_old_backups

    send_backup_report
}

main "$@"
