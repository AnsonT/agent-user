# agent-user

Open a shell as a dedicated local macOS user, in your current terminal.

```sh
./agent-user user1
# Work inside /Users/user1. Run exit to return.
./agent-user --delete user1
./agent-user --delete --force user1 # Bypass running-process check; still confirms
```

Requires macOS, an interactive terminal, and permission to run commands through
`sudo`. Uses bundled Bash and macOS utilities; no dependencies. Add this directory
to your PATH or install the executable in a directory on your PATH.

First entry creates a hidden, non-admin account with a private home and no usable
password. Later entries reuse it. Your normal sudo authentication authorizes
entry. Existing accounts not created by this tool are refused. The creator alone
can manage an account through this script (administrators retain system access).

The shell is `/bin/zsh -l`, starting in the target home with a clean environment.
Configure tools and PATH inside that account. Credentials, SSH agent sockets, and
personal shell configuration are not copied. This is a CLI shell, not a GUI login.

Each entry creates or unlocks `~/Library/Keychains/agent-user.keychain-db` and
sets it as the user's default and sole user-search-list keychain. A temporary
credential write/read/delete check verifies default routing before shell entry.
A random password lives in root-only
`/var/db/agent-user/NAME.keychain-password` (mode 600); no extra password prompt.
Passwords pass to `security` through standard input, not process arguments.
Existing login keychain files remain unchanged but are removed from the user
search list so locked legacy keychains cannot intercept lookups. Their credentials
are not migrated.
Sign in again to save new credentials in the managed default keychain.

The managed keychain does not lock on idle or sleep, allowing tmux sessions to
continue. Re-entering unlocks it after reboot or manual locking. Individual apps
may still request keychain item access; this does not bypass their access rules.
Protection relies on filesystem permissions and disk encryption because the
unlock password lives on the same Mac. Account deletion also removes that password.
If the managed keychain exists but its password is missing or no longer works,
entry fails without replacing either file or discarding credentials.

For persistence, run `agent-user user1 --tmux` to create or attach to session
`main`, or `agent-user user1 --tmux=work` for a named session. Detach with
Ctrl-b then d; rerun the same command to reconnect. Sessions run as the target
user. Install tmux yourself; the launcher checks that user's login-shell PATH
and standard Homebrew locations. `--tmux` cannot be combined with `--delete`.

Deletion displays the home path and requires typing the account name. Stop all
processes belonging to the account, including tmux, first. Deletion removes the
account and its home; it does not find or remove files elsewhere. `--force` skips
the running-process check, retaining typed confirmation and identity checks.
It does not explicitly terminate processes; macOS may still reject deletion.

Account separation follows macOS filesystem permissions. It does not block
network access or access to world-readable files, and is not a VM or sandbox.
No shared-directory permissions, sudoers rules, agent setup, or SSH setup are added.

## Recovery and development

Root-owned records live in `/var/db/agent-user`: creator UID, target UID, account
UUID, and creation phase. Failed operations stop without guessing which resources
are safe to delete. Re-running creation resumes only when creator, UID, UUID,
and group match the partial account; conflicting homes are refused. Earlier
failures without a recorded account identity require administrator recovery.
An administrator must inspect the recorded identity, local
Directory Services record, and home before repairing a partial operation. Do not
remove metadata to bypass a mismatch. A killed process can leave `lock/`; remove
that empty directory only after confirming no agent-user operation remains active.

If creation reports `eDSPermissionError`, macOS denied a Directory Services write
even though the script elevated with sudo. Try the command in Terminal.app and
accept its administration prompt if shown. Retry the same command after resolving
the permission. Do not delete the account or its metadata to bypass this error.

```sh
bash -n agent-user
bash tests/cli.sh
bash tests/keychain.sh
```

These checks never create accounts or change real keychains. Keychain tests mock
the macOS security tool. Account lifecycle, real keychain access, and terminal integration
must also be tested on a disposable macOS VM before relying on this tool. See
[PRD](docs/PRD.md) for acceptance criteria and current validation limits.

Design reference: [Sandvault](https://github.com/webcoyote/sandvault). This project
implements only account lifecycle and shell entry, independently.
