#!/bin/bash
# script name : mysql_xtrabackup_daily_backup.sh
# description : Daily backup script for MySQL 8.0.x (requires Percona XtraBackup 8.0.12+)
# author      : island_of_hermit <fallboyz@umount.net>
# date        : 2024-04-12
# modify      : 2025-05-07
#
# set -x
#
# 백업 관련 설정
backup_dir="/path/to/backup"
backup_exec="/usr/bin/xtrabackup"

# defaults_file 경로는 선택사항이며, 올바른 경로일 경우에만 오버라이드 되므로,
# 주석처리, 빈값, 또는 잘못된 값일 경우 /etc/my.cnf를 기본값으로 사용
defaults_file="/path/to/my.cnf"

# 소켓 경로는 선택사항이며, 올바른 경로일 경우에만 오버라이드 되므로,
# 주석처리, 빈값, 또는 잘못된 값일 경우 login_path에 저장된 값을 기본값으로 사용
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

# S3 스토리지 클래스 종류는 아래 사이트를 참고
# https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage-class-intro.html
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

# defaults-file 옵션 생성 함수
build_defaults_file_option() {
    local defaults_option=""
    if [ -n "${defaults_file}" ] && [ -f "${defaults_file}" ]; then
        defaults_option="--defaults-file=${defaults_file}"
    elif [ -f "/etc/my.cnf" ]; then
        defaults_option="--defaults-file=/etc/my.cnf"
    fi
    echo "${defaults_option}"
}

# socket 옵션 생성 함수
build_socket_option() {
    local socket_option=""
    if [ -n "${socket}" ] && [ -S "${socket}" ]; then
        socket_option="--socket=${socket}"
    fi
    echo "${socket_option}"
}

# rsync 전송 함수
transfer_backup_to_remote() {
    local backup_file=$1
    rsync -az "${rsync_opt[@]}" "${backup_file}" \
        "${remote_user}@${remote_backup_host}:${remote_backup_dir}" >> "${log_file}" 2>&1
}

# S3 업로드 함수
upload_backup_to_s3() {
    local backup_file=$1
    "${aws_cli}" s3 cp "${backup_file}" "s3://${remote_backup_dir2}" \
        --storage-class "${s3_storage_class}" >> "${log_file}" 2>&1
}

# 백업 파일 삭제 함수
cleanup_backup() {
    local backup_file=$1
    rm -f "${backup_file}"
    log "[info] Deleted backup file after successful transfers: ${backup_file}"
}

# 전송 통합 처리
transfer_backup() {
    local backup_file="$1"
    local rsync_result=2
    local s3_result=2

    if [ "${enable_rsync}" = true ]; then
        transfer_backup_to_remote "${backup_file}" && rsync_result=0 || rsync_result=1
    fi

    if [ "${enable_s3}" = true ]; then
        upload_backup_to_s3 "${backup_file}" && s3_result=0 || s3_result=1
    fi

    if { [ "${enable_rsync}" = true ] && [ "${rsync_result}" -eq 0 ]; } || \
       { [ "${enable_s3}" = true ] && [ "${s3_result}" -eq 0 ]; }; then
        cleanup_backup "${backup_file}"
    else
        log "[warn] Transfer failed or skipped. Backup file not deleted: ${backup_file}"
    fi
}

# 이전 백업 삭제 함수
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
}

# 압축 함수
compress_backup() {
    local target_dir=$1
    local archive_name
    archive_name="$(basename "${target_dir}").tar.zst"

    tar -cf - -C "${target_dir}" . | zstd -T0 -15 -o "${backup_dir}/${archive_name}" || {
        log "[error] Failed to compress backup directory: ${target_dir}"
        exit 1
    }

    log "[info] Compressed backup directory: ${target_dir}"
    echo "${backup_dir}/${archive_name}"
}

# 풀 백업 수행 함수
perform_full_backup() {
    local target_dir compressed_file socket_option defaults_option
    target_dir="${backup_dir}/full-$(date +%Y-%m-%d)"
    mkdir -p "${target_dir}"

    socket_option=$(build_socket_option)
    defaults_option=$(build_defaults_file_option)

    "${backup_exec}" \
        "${defaults_option}" \
        --backup \
        --parallel="$(get_cpu_cores)" \
        --login-path="${login_path}" \
        "${socket_option}" \
        --target-dir="${target_dir}" >> "${log_file}" 2>&1 || {
            log "[error] Full backup failed: ${target_dir}"
            exit 1
        }

    log "[info] Full backup completed: ${target_dir}"
    compressed_file=$(compress_backup "${target_dir}")
    transfer_backup "${compressed_file}"
}

# 증분 백업 수행 함수
perform_incremental_backup() {
    local base_dir=$1
    local target_dir compressed_file socket_option defaults_option
    target_dir="${backup_dir}/incremental-$(date +%Y-%m-%d)"
    mkdir -p "${target_dir}"

    socket_option=$(build_socket_option)
    defaults_option=$(build_defaults_file_option)

    "${backup_exec}" \
        "${defaults_option}" \
        --backup \
        --parallel="$(get_cpu_cores)" \
        --incremental-basedir="${base_dir}" \
        --login-path="${login_path}" \
        "${socket_option}" \
        --target-dir="${target_dir}" >> "${log_file}" 2>&1 || {
            log "[error] Incremental backup failed: ${target_dir} (base: ${base_dir})"
            exit 1
        }

    log "[info] Incremental backup completed: ${target_dir} (base: ${base_dir})"
    compressed_file=$(compress_backup "${target_dir}")
    transfer_backup "${compressed_file}"
}

# 메인 함수
main() {
    true > "${log_file}"

    local last_backup_dir short_day full_day target_day
    read -r short_day full_day <<< "$(get_day_of_week)"

    last_backup_dir=$(find "${backup_dir}" -maxdepth 1 -type d -name "*-*" -print | sort -r | head -1)
    target_day=$(echo "${full_backup_day}" | tr '[:upper:]' '[:lower:]')

    if [ "${short_day}" = "${target_day}" ] || [ "${full_day}" = "${target_day}" ]; then
        perform_full_backup
    else
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
