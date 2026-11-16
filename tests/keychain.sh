#!/bin/bash
# Exercise orchestration with a fake security tool; never touch real keychains.
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
die() { printf '%s\n' "$*" >&2; exit 1; }
# Load only the keychain functions from the standalone executable.
eval "$(sed -n '/^as_user() {/,/^# Account lifecycle\./p' agent-user | sed '$d')"
stat() {
    # Fixtures are owned by the test runner; preserve the actual mode check.
    local result
    result=$(/usr/bin/stat "$@")
    printf '0:%s\n' "${result#*:}"
}
as_user() {
    if [[ $1 == /bin/mkdir ]]; then "$@"; return; fi
    [[ $1 == /usr/bin/security ]] || return 90
    shift
    if [[ $1 == -i ]]; then
        [[ $# == 1 ]] || return 91
        local line operation secret path
        IFS= read -r line
        operation=${line%% *}
        line=${line#* -p }
        secret=${line%% *}
        path=${line#* }; path=${path#\"}; path=${path%\"}
        [[ "$secret" =~ ^[[:xdigit:]]{64}$ ]] || return 92
        printf '%s\n' "$operation" >> "$fixture/calls"
        if [[ "$operation" == create-keychain ]]; then
            printf '%s\n' "$secret" > "$path"
        else
            [[ "$secret" == "$(cat "$path")" ]] || return 93
            [[ ${fail_unlock:-false} == false ]] || return 97
            touch "$fixture/unlocked"
        fi
    else
        printf '%s\n' "$1" >> "$fixture/calls"
        case "$1" in
            default-keychain)
                if [[ $# == 1 ]]; then
                    printf '    "%s"\n' "${default_override:-$home/Library/Keychains/agent-user.keychain-db}"
                else
                    [[ $2 == -s ]] || return 99
                    [[ -d "$home/Library/Preferences" ]] || return 100
                fi
                ;;
            list-keychains) [[ $2 == -s ]] || return 99 ;;
            add-generic-password)
                [[ -f "$fixture/unlocked" ]] || return 98
                grep -q '^list-keychains$' "$fixture/calls" || return 94
                [[ ${fail_write:-false} == false ]] || return 95
                ;;
            find-generic-password)
                [[ ${fail_read:-false} == false ]] || return 96
                printf 'probe\n'
                ;;
        esac
    fi
}
reset_fixture() {
    rm -rf "$fixture/home" "$fixture/state"
    home=$fixture/home; state=$fixture/state; name=testuser; uid=999
    mkdir -p "$home" "$state"
    : > "$fixture/calls"
    rm -f "$fixture/unlocked"
}
expect_failure() {
    local message=$1 output
    if output=$(prepare_keychain 2>&1); then die 'Expected keychain failure.'; fi
    [[ "$output" == *"$message"* ]] || die "Unexpected error: $output"
}
reset_fixture
prepare_keychain
password_file=$state/$name.keychain-password
original=$(cat "$password_file")
[[ $(/usr/bin/stat -f %Lp "$password_file") == 600 ]]
prepare_keychain
[[ $(cat "$password_file") == "$original" ]]
[[ $(grep -c '^create-keychain$' "$fixture/calls") == 1 ]]
[[ $(grep -c '^unlock-keychain$' "$fixture/calls") == 2 ]]
! grep -q "$original" "$fixture/calls"
default_override=/wrong/keychain
: > "$fixture/calls"
expect_failure 'Default keychain resolves to'
! grep -q '^add-generic-password$' "$fixture/calls"
unset default_override
fail_write=true
expect_failure 'not writable'
fail_write=false
fail_read=true
expect_failure 'could not be read'
[[ $(tail -1 "$fixture/calls") == delete-generic-password ]]
fail_read=false
# A wrong password must fail before changing keychain settings/defaults.
printf 'different\n' > "$home/Library/Keychains/agent-user.keychain-db"
: > "$fixture/calls"
expect_failure 'Could not unlock-keychain'
! grep -q 'default-keychain' "$fixture/calls"
rm "$password_file"
expect_failure 'exists without its password'
reset_fixture
fail_unlock=true
expect_failure 'Could not unlock newly created keychain'
! grep -q '^add-generic-password$' "$fixture/calls"
[[ -f "$state/$name.keychain-password" ]]
[[ -f "$home/Library/Keychains/agent-user.keychain-db" ]]
fail_unlock=false
prepare_keychain
reset_fixture
ln -s "$fixture" "$home/Library"
expect_failure 'directory is symlinked'
reset_fixture
mkdir "$home/Library"
ln -s "$fixture" "$home/Library/Preferences"
expect_failure 'directory is symlinked'
reset_fixture
printf 'corrupt\n' > "$state/$name.keychain-password"
chmod 600 "$state/$name.keychain-password"
expect_failure 'Invalid managed keychain password'
chmod 644 "$state/$name.keychain-password"
expect_failure 'root-owned with mode 600'
printf 'Keychain orchestration checks passed; no real keychains changed.\n'
