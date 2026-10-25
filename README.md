# branch-guard

一个 git pre-commit 钩子，阻止编码 agent 在 `main` 上提交。
当 agent 试图提交时，它的工作会被静默迁移到一个全新的
`agent/<timestamp>-<pid>` 分支，提交随后在那里落地。而人类提交完全
相同的内容时，永远不会被干预。

它之所以存在，是因为 agent 不被告知就不会创建分支——而即使被告知
（通过 AGENTS.md 或系统提示词），它们也会忘。指令只是君子协定；git
钩子能看到每一次提交，无论发起者是谁、是什么，包括从 agent 自己写的
脚本内部触发的那一次。

## 它做什么

| 提交时的情况 | 结果 |
|---|---|
| agent 在受保护分支上提交（默认 `main` / `master`） | 工作被移到 `agent/<timestamp>-<pid>`，提交落在那里 |
| agent 在任何其他分支上提交 | 允许，不做处理 |
| agent 带 `AGENT_GUARD_APPROVE=1` 提交 | 允许（按命令显式批准） |
| **你**（而不是 agent）提交 | 始终允许 |

绕过始终是人类的选择：`git commit --no-verify` 会跳过钩子。

## 它如何判断自己是 agent

agent 运行时会设置标记环境变量，每个子进程都会继承——所以即使提交
来自 agent 写的脚本，标记也依然存在：

| 标记 | 运行时 |
|---|---|
| `CLAUDECODE` | Claude Code |
| `CODEX_THREAD_ID`、`CODEX_SESSION_ID` | Codex |
| `AGENT_GUARD=1` | 对其他任何东西强制启用守卫 |

用的是别的 agent？在它的会话里运行 `env | sort`，找到它的标记，
然后加到 `hooks/pre-commit` 的列表中。（已知缺口：DeepSeek
Harness 的标记尚未加入列表——欢迎贡献。）

## 安装

```sh
git clone <this repo>
cd branch-guard
./install.sh
```

这会把钩子复制到 `~/.git-hooks` 并设置全局 `core.hooksPath`。
之所以是全局的：agent 在工作过程中会自己克隆仓库，而装在某个仓库里的
钩子不会出现在五分钟后才做的克隆里。
`./install.sh --local` 只安装到当前仓库。
`./uninstall.sh` 将其移除。

纯 POSIX sh，无依赖。可在 Linux、macOS 以及 Windows（通过 Git Bash）
上运行（Git for Windows 通过其自带的 sh 运行钩子，因此不需要单独的
Windows 版本）。

## 自定义受保护分支

默认保护 `main` 和 `master`。要换成别的分支，配置 `branch-guard.protected`：

```sh
# 全局：本机所有仓库（仓库级配置会覆盖它）
git config --global branch-guard.protected "main develop release"

# 只对当前仓库生效
git config branch-guard.protected "main develop"
```

- 空格分隔的列表，整串**替换**默认值，而不是追加。
- 设成空字符串（`git config branch-guard.protected ""`）等于谁都不保护。
- 不支持通配符：`release/*` 不会匹配 `release/1.2`，分支名要逐字写出。
- 查看当前值及它来自哪一层配置：`git config --show-origin --get branch-guard.protected`。

## 如果你使用 husky

Husky 会按仓库设置 `core.hooksPath`，而仓库配置优先于全局配置，因此
在 husky 仓库里全局钩子永远不会运行。在该仓库的 `.husky/pre-commit`
中加一行：

```sh
"$HOME"/.git-hooks/pre-commit "$@" || exit 1
```

## 开发

```sh
./test.sh   # 验收测试：在你的临时目录里创建一次性仓库
```

设计说明与验收清单见 [docs/DESIGN.md](docs/DESIGN.md)。

## 许可证

MIT
