#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash -n agent-user
output=$(bash agent-user --help)
[[ "$output" == *'Usage: agent-user NAME'* ]]
expect_failure() {
    local expected=$1 output status
    shift
    status=0
    output=$(bash agent-user "$@" </dev/null 2>&1) || status=$?
    [[ $status != 0 && "$output" == *"$expected"* ]] || {
        printf 'Unexpected result (%s): %s\n' "$status" "$output" >&2
        exit 1
    }
}
expect_failure Usage
expect_failure Usage --delete
expect_failure Usage --delete --force
expect_failure '--force requires --delete' --force alice
expect_failure '--tmux cannot be combined' --delete --tmux alice
expect_failure 'cannot be empty' alice --tmux=
expect_failure 'tmux session name' alice --tmux=bad.session
expect_failure Usage alice extra
for name in ../alice /Users/alice Alice --bad 'a b' 'a;id' _service "$(printf '%032d' 0)"; do
    expect_failure 'Use 1–31' "$name"
done
expect_failure 'root account is protected' root
if [[ $(uname -s) == Darwin ]]; then
    expect_failure 'interactive terminal is required' alice
    expect_failure 'interactive terminal is required' alice --tmux
    expect_failure 'interactive terminal is required' --tmux alice
    expect_failure 'interactive terminal is required' alice --tmux=work
    expect_failure 'interactive terminal is required' --delete alice
    expect_failure 'interactive terminal is required' --delete --force alice
    expect_failure 'interactive terminal is required' --delete alice --force
    expect_failure 'interactive terminal is required' --force --delete alice
fi
printf 'CLI checks passed; no privileged operations performed.\n'
