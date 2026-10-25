# branch-guard — 设计说明

## 一句话需求

面向与编码 agent 协作的开发者：保证 agent 的工作永远不会直接落到
`main` 上，同时不改变人类工作方式的任何一点。

## 决策

1. **拦截点：git 钩子，而非 agent 侧配置。**
   agent 指令（AGENTS.md、系统提示词）只是建议性的，而且会被遗忘。
   agent 运行时的钩子（例如 Claude Code 的 PreToolUse）只能看到 agent
   直接执行的命令文本——看不到从 agent 所写脚本内部触发的提交。git
   能看到每一次提交。git 钩子是底线；agent 侧配置以后可以作为润色
   补充，而无需改变架构。

2. **阶段：提交时，而非推送时。**
   agent-git-guard 已经很好地守住了推送阶段。本工具把防线提前一个
   阶段：agent 一开始在 main 上提交，工作就被迁移到分支上，因此提交
   *以及*之后的任何推送都天然位于该分支。

3. **纯 POSIX sh，零依赖。**
   Git for Windows 通过其自带的 sh 运行钩子，因此一套实现即可覆盖
   Linux、macOS 和 Windows。无需安装运行时，也没有版本管理负担。

4. **移动，而非阻断。**
   只懂拒绝的钩子会让 agent 卡住、让用户被打断。`git switch -c` 会把
   已暂存和未暂存的改动一起带过去，因此触发钩子的那次提交可以在新
   分支上继续。agent 读到钩子的 stderr 消息后继续即可。

## Agent 检测

标记是 agent 运行时设置、并被所有子进程继承的环境变量：
`CLAUDECODE`（Claude Code）、`CODEX_THREAD_ID` /
`CODEX_SESSION_ID`（Codex）、`AGENT_GUARD=1`（手动覆盖）。
所有标记都不存在即视为人类：立即 exit 0。

## 验收清单（可执行：../test.sh）

1. agent 在 main 上提交 → 被移到 `agent/*`，提交落在那里，main 不变。
2. 人类在 main 上提交 → 不做处理。
3. agent 在功能分支上提交 → 不做处理。
4. 在 main 上带 `AGENT_GUARD_APPROVE=1` → 允许。

## 明确的非目标（v1）

- pre-push / 推送保护（请配合 agent-git-guard 一起使用）
- 可配置的受保护分支列表——已提升为下方"延后想法 #4"
- PowerShell 原生钩子（Git Bash 已覆盖 Windows）
- 依据意图命名分支（钩子无法知道意图；就用时间戳）

## 已知限制

- husky 仓库会覆盖全局 hooksPath；见 README。
- detached HEAD 不做处理。
- DeepSeek Harness 的标记未知；发现后请加入（`env | sort`）。

## 事后复盘：uninstall 中的路径形式不匹配（已修复）

真实使用中报出的问题：卸载删除了钩子文件，却把全局
`core.hooksPath` 留了下来。根因：在 Windows 上安装和卸载可能在不同
shell 下运行，因此存下的值是 `C:/...`，而 `$HOME` 却展开为 `/c/...`
（MSYS 形式）。MSYS 在系统调用层做路径转换（这正是 `rm` 还能正常
工作的原因），但 `[ = ]` 是不感知文件系统的纯字符串比较。修复办法：
比较前用 `cygpath -m`（Windows 形式，正斜杠）把两边归一化。

代码库中沉淀了两条经验：

1. 回归测试先行：`test.sh` 中的场景 5 复现了该不匹配，并在修复前
   失败。它把 `HOME` 沙箱化，因此不会碰到真实的机器配置。
2. 测试要封闭：`setup_repo` 固定了仓库级 `core.hooksPath`，因为机器
   级 hooksPath（即使指向一个空目录）会遮蔽测试仓库的 `.git/hooks`，
   并曾悄悄让场景 1 失败。

## 延后想法（测试期间记录的假设性需求）

这些是测试过程中冒出来的，并非来自真实使用。此处连同提议的机制一起
记录，以便将来真有用户提出时不必重新做设计思考。均未实现。

1. **`uninstall.sh --local`** —— `install.sh --local` 的对称逆操作：
   `rm -f $(git rev-parse --git-dir)/hooks/pre-commit`，绝不触碰全局
   配置。理由：安装/卸载对称能降低尝试 `--local` 的顾虑。实现触发
   条件：真的有人装了 `--local` 之后想要退出。

2. **从全局安装中豁免某一个仓库** —— 这不是卸载（钩子文件是共享的），
   而是*禁用*。今天无需任何代码即可做到：在仓库内执行
   `git config core.hooksPath "$(git rev-parse --git-dir)/hooks"`
   （仓库配置优先于全局配置）。更友好的 v2：把它包装起来，或者让
   钩子自身遵循 `git config --bool branch-guard.disabled`。

3. **临时的全局总开关** —— `git config --global
   branch-guard.disabled true`，由钩子在开头检查。机制同 (2)，
   是它的推广。模式参考：`HUSKY=0`。

注意它们依赖的这个区分：install/uninstall 管理的是*文件是否存在*；
enable/disable 管理的是*行为*。"全局安装了但这里豁免"无法通过删除
文件来表达。

4. **可配置的受保护分支列表**（从 v1 非目标提升而来）——
   目前 `main master` 硬编码在钩子里。提议的机制：
   `protected=$(git config --get branch-guard.protected || echo "main master")`。
   通过 `git config` 读取意味着仓库级的值会免费覆盖机器级的值
   （git 自身的配置分层替我们完成了工作）。钩子中 case 语句的列表
   匹配本来就支持多词列表，因此这只是一行改动加上测试。实现触发
   条件：使用 git-flow 风格工作流（develop/release 分支）的用户，或
   任何重命名默认分支的人——把 `master` 改名为 `main`，正是硬编码
   列表里有两个条目的原因。注意：在所有延后想法中，这一个最可能
   毕业，因为分支命名约定确实因团队而异，而不像卸载易用性那样属于
   边缘场景的易用性问题。
