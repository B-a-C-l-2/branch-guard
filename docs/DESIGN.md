# branch-guard — design notes

## One-sentence requirement

For developers who work with coding agents: guarantee an agent's work never
lands directly on `main`, without changing anything about how a human works.

## Decisions

1. **Interception point: git hook, not agent-side config.**
   Agent instructions (AGENTS.md, system prompts) are advisory and are
   forgotten. Agent-runtime hooks (e.g. Claude Code's PreToolUse) only see
   commands the agent runs directly, as text — not commits fired from inside
   a script the agent wrote. Git sees every commit. Git hooks are the floor;
   agent-side config may be added later as polish without changing the
   architecture.

2. **Stage: commit time, not push time.**
   agent-git-guard already guards the push stage well. This tool moves the
   line one stage earlier: the moment an agent starts committing on main,
   the work is relocated to a branch, so commits *and* any later push are
   on the branch naturally.

3. **Pure POSIX sh, zero dependencies.**
   Git for Windows runs hooks through its bundled sh, so one implementation
   covers Linux, macOS and Windows. No runtime to install, nothing to version.

4. **Move, don't block.**
   A hook that only refuses would leave the agent stuck and the user
   interrupted. `git switch -c` carries staged and unstaged changes along,
   so the commit that triggered the hook can proceed on the new branch.
   The agent reads the hook's stderr message and simply continues.

## Agent detection

Markers are environment variables set by the agent runtime and inherited by
all children: `CLAUDECODE` (Claude Code), `CODEX_THREAD_ID` /
`CODEX_SESSION_ID` (Codex), `AGENT_GUARD=1` (manual override).
Absence of all markers means human: exit 0 immediately.

## Acceptance list (executable: ../test.sh)

1. Agent commits on main → moved to `agent/*`, commit lands there, main unchanged.
2. Human commits on main → untouched.
3. Agent commits on a feature branch → untouched.
4. `AGENT_GUARD_APPROVE=1` on main → allowed.

## Explicit non-goals (v1)

- pre-push / push protection (use agent-git-guard alongside)
- configurable protected-branch list (hardcoded: main, master)
- PowerShell-native hook (Git Bash covers Windows)
- branch naming from intent (a hook cannot know intent; timestamp it is)

## Known limitations

- Husky repos override the global hooksPath; see README.
- Detached HEAD is left alone.
- DeepSeek Harness marker unknown; add it when found (`env | sort`).

## Post-mortem: path-form mismatch in uninstall (fixed)

Reported through real use: uninstall removed the hook file but left the
global `core.hooksPath` set. Root cause: install and uninstall can run
under different shells on Windows, so the stored value was `C:/...` while
`$HOME` expanded to `/c/...` (MSYS form). MSYS translates paths at the
syscall layer (which is why `rm` worked), but `[ = ]` is a pure string
comparison with no filesystem awareness. Fix: normalize both sides with
`cygpath -m` (Windows form, forward slashes) before comparing.

Two lessons encoded in the codebase:

1. Regression first: scenario 5 in `test.sh` reproduces the mismatch and
   failed before the fix. It sandboxes `HOME` so the real machine config
   is untouched.
2. Hermetic tests: `setup_repo` pins a repo-level `core.hooksPath`, because
   a machine-global hooksPath (even pointing at an empty directory) shadows
   test repos' `.git/hooks` and silently broke scenario 1.
