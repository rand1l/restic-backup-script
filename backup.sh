#!/bin/bash

LOCAL_ENDPOINT='/mnt/backup'
MEGA_ENDPOINT='rclone:mega-backup:backup'
HOME_BACKUP='/home/sfy'
NOTES_BACKUP='/home/sfy/notes'
REPOS_BACKUP='/home/sfy/repos'
GUM_INPUT_PLACEHOLDER=' '
GUM_SPIN_SPINNER='jump'
RESTIC_COMPRESSION='max'
RESTIC_REPOSITORY="${LOCAL_ENDPOINT}"
RESTIC_FROM_REPOSITORY="${RESTIC_REPOSITORY}"

export GUM_INPUT_PLACEHOLDER
export GUM_SPIN_SPINNER
export RESTIC_COMPRESSION
export RESTIC_REPOSITORY
export RESTIC_FROM_REPOSITORY
export RESTIC_PASSWORD
export RESTIC_FROM_PASSWORD


function _restic_repo_check() {
    if gum spin \
        --title='Checking repo...' \
        restic cat config; then
        echo_log ok "Found restic repo at ${RESTIC_REPOSITORY}"
    else
        >&2 echo_log err "No restic repo at ${RESTIC_REPOSITORY} OR the password is wrong OR the repo is locked"
        exit 1
    fi
}

function _restic_backup_local_helper() {
    local source="$1"
    local args=("$@")

    echo_log warn "Backing up ${source} to ${RESTIC_REPOSITORY}"
    if restic backup "${args[@]}"; then
        echo_log ok "Done backing up ${source} to ${RESTIC_REPOSITORY}"
    else
        >&2 echo_log err "Failed to backup from ${source} to ${RESTIC_REPOSITORY}"
        exit 1
    fi
}

function _restic_backup_local() {
    _restic_backup_local_helper "${HOME_BACKUP}" \
        --exclude="${NOTES_BACKUP}" \
        --exclude="${REPOS_BACKUP}" \
        --tag='local'

    _restic_backup_local_helper "${NOTES_BACKUP}" --tag='both'

    _restic_backup_local_helper "${REPOS_BACKUP}" --tag='both'
}

function _restic_backup_copy() {
    echo_log warn "Copying data from ${LOCAL_ENDPOINT} to ${RESTIC_REPOSITORY}"

    if restic copy --tag='both'; then
        echo_log ok "Done copying data from ${LOCAL_ENDPOINT} to ${RESTIC_REPOSITORY}"
    else
        >&2 echo_log err "Failed to copy data from ${LOCAL_ENDPOINT} to ${RESTIC_REPOSITORY}"
        exit 1
    fi
}

function _restic_remove_old_snapshots() {
    if gum spin \
        --title='Removing old snapshots...' \
        -- \
        restic forget --keep-last=1 --prune; then
        echo_log ok "Removed old snapshots from ${RESTIC_REPOSITORY}"
    else
        >&2 echo_log err "Failed to remove old snapshots from ${RESTIC_REPOSITORY}"
        exit 1
    fi
}

function _restic_integrity_check() {
    gum spin \
        --title='Checking integrity...' \
        restic check
    if [ "$?" -eq 0 ]; then
        echo_log ok "Integrity check for ${RESTIC_REPOSITORY} successful"
    else
        >&2 echo_log err "Integrity check for ${RESTIC_REPOSITORY} failed"
        exit 1
    fi
}

function handle_interrupt() {
    >&2 echo_log err 'Backup was interrupted'
    exit 2
}

function echo_header() {
    toilet 'backup.sh' --font='emboss2' --filter='border' \
        | lolcat --freq=0.08 --seed=32
}

function prompt_password() {
    local password
    local password_check

    password=$(gum input --password --prompt='Enter password: ')
    password_check=$(gum input --password --prompt='Confirm password: ')

    if [ "${password}" == "${password_check}" ]; then
        echo_log ok 'Passwords match'
    else
        >&2 echo_log err 'Passwords do not match'
        exit 1
    fi

    RESTIC_PASSWORD="${password}"
    RESTIC_FROM_PASSWORD="${RESTIC_PASSWORD}"
}

function echo_log() {
    local color="$1"
    local output="$2"
    local symbol

    case "${color}" in
        err)  colorcode=31 && symbol='❌' ;;
        ok)   colorcode=32 && symbol='✅' ;;
        warn) colorcode=33 && symbol='💡' ;;
        info) colorcode=34 && symbol='🤖' ;;
    esac

    echo -e "\033[0;${colorcode}m${symbol} ${output}\033[0;0m"
}

function backup_loop() {
    _restic_repo_check

    if [[ ! "${RESTIC_REPOSITORY}" =~ 'rclone' ]]; then
        _restic_backup_local
    else
        _restic_backup_copy
    fi

    _restic_remove_old_snapshots

    _restic_integrity_check
}

function main() {
    trap handle_interrupt SIGINT

    echo_header

    prompt_password

    echo_log info 'Starting local backup'
    backup_loop

    RESTIC_REPOSITORY="${MEGA_ENDPOINT}"

    echo_log info 'Starting remote backup'
    backup_loop

    echo_log info 'All done'
}

main
