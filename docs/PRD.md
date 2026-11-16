# agent-user PRD

Status: initial implementation; privileged macOS integration validation pending.

## Problem and scope

Users need a terminal shell under a separate local macOS identity so commands
and agents use that account's home, credentials, and filesystem permissions.
The invoking user interacts through the same terminal and returns by exiting.

V1 provides `agent-user NAME [--tmux[=SESSION]]`,
`agent-user --delete [--force] NAME`, and `--help`.
No agent-specific setup, command execution mode, package installation, GUI login,
SSH configuration, automatic project sharing, or sandbox policy.
Optional `--tmux` uses user-installed tmux under the target identity, creating or
attaching to `main` by default. `--tmux=SESSION` selects another session. Detaching
returns to the invoking user while preserving the session. Missing tmux reports
an error; no automatic installation occurs.

## Required behavior

- Missing account: authenticate via sudo, create a hidden standard account with
  private `/Users/NAME`, disabled password login, and zsh; enter its shell.
- Managed account: verify creator, UUID, UID, home, and non-admin status; enter.
- Unmanaged existing account or conflicting home: refuse without modification.
- Shell: target identity and home, clean environment, terminal input/output,
  resizing, signals, job control, and exit status preserved by process handoff.
- Keychain: create a separate managed keychain, set it as default, and unlock
  on every entry without additional prompts. Store a random 256-bit password in
  root-owned mode-600 state, never in process arguments or exported environment.
  Preserve existing login keychains and credentials. Disable idle/sleep locking
  for persistent sessions; leave item-specific access controls intact.
  Set the user search list to only the managed keychain. Verify default credential
  write/read routing with a temporary item and remove it before shell entry.
  This checks the native security CLI path, not every application's item ACLs.
- Delete: display exact account/home; require matching typed name from the
  controlling terminal; revalidate; refuse active processes unless `--force`;
  remove account,
  then home, then management record. Retain evidence after partial failure.
  `--force` only bypasses the process check; it neither skips confirmation nor
  explicitly kills processes. Native deletion failures still stop cleanup.
- Reject invalid names, root, caller's own account, noninteractive use, identity
  mismatches, symlinked home/state, and unmanaged deletion.

## Implementation

Single Bash 3.2-compatible executable; native Directory Services tools create a
passwordless-disabled account without granting admin privileges or a Secure Token.
`dscl . -delete /Users/NAME` removes the local account record before guarded
home cleanup. A successful local-user listing must confirm removal before any
files are deleted; this avoids the unsupported `sysadminctl -keepHome` option.
Root-owned metadata under `/var/db/agent-user` records creator UID, target UID,
GeneratedUID, and phase. Metadata is parsed as data, never sourced as shell code.
An atomic directory lock serializes this tool's lifecycle operations. Failed
creation remains marked `creating`. A retry resumes after matching creator,
UID, UUID, and standard group and checking for conflicting home paths. Failures
before identity initialization require deliberate administrator recovery.

Elevation uses the caller's sudo authorization. Target execution drops identity
through sudo and starts `/bin/zsh -l` using `env -i`. Only explicit identity,
system PATH, TERM, and LANG values pass through. The shell owns no lifecycle lock.
No persistent privileged helper, daemon, or passwordless sudo grant is installed.
Native `security -i` receives one command through a pipe per operation so each
exit status is checked. Keychain operations execute as the target user, never
root. Persist the password before keychain creation so interrupted setup can retry.
Deletion removes the password after successful account/home removal.

## Security boundaries and limitations

The invoking administrator trusts the script they execute with sudo. Managed
accounts cannot edit root-owned metadata. Separate users still share the kernel,
network, and publicly accessible files. No automatic access to the caller's home
or current directory is granted. macOS GUI services are outside v1. Managed
keychains remain unlocked across shell exit, idle, and sleep. Their passwords
live on the same disk; filesystem permissions and FileVault provide the primary
protection. Existing credentials are not migrated, and app-specific access
prompts are not bypassed. External account-management tools do not honor our lock; concurrent
administrator changes are unsupported. A process check is not a kernel-level
guarantee against independently scheduled processes starting during deletion.

## Acceptance and validation

Automated unprivileged checks cover syntax, help, malformed arguments, forbidden
names, and noninteractive rejection. They must never request sudo or mutate users.
Mocked keychain tests cover first creation, repeated unlock with the same password,
file permissions, missing/corrupt password state, symlink rejection, and failure
before default-keychain changes when unlocking fails.

On a disposable macOS VM, verify creation attributes and inaccessible home,
repeat entry with unchanged UID/UUID, correct whoami/HOME/cwd, no leaked credentials,
Ctrl-C, Ctrl-Z/fg, terminal resize, shell exit status, and return to caller.
Verify tmux survives detach and reconnect and prevents deletion while running.
Verify keychain create/unlock in the actual sudo shell context, credential
write/read, reconnect after reboot/manual locking, retained login keychains,
and password cleanup on deletion. These native keychain checks remain pending.
Verify wrong confirmation preserves everything; confirmed idle deletion removes
account/home/metadata. Exercise unmanaged collisions, changed UUID/home, symlinks,
interrupted creation/deletion, stale locks, and concurrent invocations.

Release gate: complete those integration checks on supported macOS versions.
No live account creation or deletion was authorized as part of implementation
validation on the developer's primary Mac.
