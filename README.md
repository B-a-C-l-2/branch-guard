# branch-guard

A git pre-commit hook that stops a coding agent from committing on `main`.
When an agent tries, its work is silently moved to a fresh `agent/<timestamp>-<pid>`
branch and the commit proceeds there. A human committing the very same
things is never touched.

It exists because agents do not create branches unless told to — and even
when told to (via AGENTS.md or system prompts), they forget. Instructions
are a gentleman's agreement; a git hook sees every commit, whoever or
whatever started it, including one fired from inside a script the agent wrote.

## What it does

| the agent commits | result |
|---|---|
| on `main` / `master` | work moved to `agent/<timestamp>-<pid>`, commit lands there |
| on any other branch | allowed, untouched |
| with `AGENT_GUARD_APPROVE=1` | allowed (explicit per-command approval) |
| and when it is **you** committing, not an agent | always allowed |

Bypass remains the human's choice: `git commit --no-verify` skips the hook.

## How it knows it is an agent

Agent runtimes set marker environment variables that every child process
inherits — so the marker is present even when the commit comes from a script
the agent wrote:

| marker | runtime |
|---|---|
| `CLAUDECODE` | Claude Code |
| `CODEX_THREAD_ID`, `CODEX_SESSION_ID` | Codex |
| `AGENT_GUARD=1` | forces the guard on for anything else |

Using a different agent? Run `env | sort` inside its session, find its
marker, and add it to the list in `hooks/pre-commit`. (Known gap: DeepSeek
Harness's marker is not in the list yet — contributions welcome.)

## Install

```sh
git clone <this repo>
cd branch-guard
./install.sh
```

That copies the hook to `~/.git-hooks` and sets the global `core.hooksPath`.
Global on purpose: an agent clones repositories of its own while it works,
and a hook inside one repo is not in a clone made five minutes later.
`./install.sh --local` installs into the current repository only.
`./uninstall.sh` removes it.

POSIX sh, no dependencies. Works on Linux, macOS, and Windows via Git Bash
(Git for Windows runs hooks through its bundled sh, so no separate Windows
version is needed).

## If you use husky

Husky sets `core.hooksPath` per repository, and repository config beats
global config, so in a husky repo the global hook never runs. Add one line
to that repo's `.husky/pre-commit`:

```sh
"$HOME"/.git-hooks/pre-commit "$@" || exit 1
```

## Develop

```sh
./test.sh   # acceptance tests: creates throwaway repos in your temp dir
```

Design notes and the acceptance list live in [docs/DESIGN.md](docs/DESIGN.md).

## License

MIT
