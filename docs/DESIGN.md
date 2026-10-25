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

5. **受保护分支列表可配置。**
   `protected=$(git config --get branch-guard.protected || echo "main master")`。
   `git config --get` 在键不存在时退出码为 1——在 shell 里 1 是"失败"，
   所以 `||` 右侧的回退会执行；键存在时退出码为 0，回退不执行。
   走 `git config` 读取还免费得到配置分层：仓库级值覆盖全局值。
   列表是一条空格分隔的字符串，整串替换默认值；空值表示不保护任何分支。
   不支持通配符——`case` 中的分支名按字面量匹配。
   选"一条字符串"而不是多值键（`--add` / `--get-all`），是因为 `--get`
   对多值只返回最后一条，而 `--add` 容易让用户误以为在追加到默认列表。

## Agent 检测

标记是 agent 运行时设置、并被所有子进程继承的环境变量：
`CLAUDECODE`（Claude Code）、`CODEX_THREAD_ID` /
`CODEX_SESSION_ID`（Codex）、`AGENT_GUARD=1`（手动覆盖）。
所有标记都不存在即视为人类：立即 exit 0。

## 验收清单（可执行：../test.sh，场景 1-8）

1. agent 在 main 上提交 → 被移到 `agent/*`，提交落在那里，main 不变。
2. 人类在 main 上提交 → 不做处理。
3. agent 在功能分支上提交 → 不做处理。
4. 在 main 上带 `AGENT_GUARD_APPROVE=1` → 允许。
5. 配置 `branch-guard.protected develop` 后，agent 在 develop 上提交 →
   被移到 `agent/*`，develop 不变。
6. 配置替换默认值：配了 develop 后，agent 在 main 上提交 → 允许。
7. 仓库级配置覆盖全局配置：全局保护 develop、仓库保护 main 时，
   agent 在 main 上提交 → 被移走；在 develop 上提交 → 允许。
8. 列表为空 → 谁都不保护，agent 在 main 上提交 → 允许。

## 明确的非目标（v1）

- pre-push / 推送保护（请配合 agent-git-guard 一起使用）
- PowerShell 原生钩子（Git Bash 已覆盖 Windows）
- 依据意图命名分支（钩子无法知道意图；就用时间戳）

## 已知限制

- husky 仓库会覆盖全局 hooksPath；见 README。
- detached HEAD 不做处理。
- 受保护分支按字面量匹配，不支持 `release/*` 之类的通配符。
- 把列表配置成空字符串等同于关闭保护；见 README 的"自定义受保护分支"。
- DeepSeek Harness 的标记未知；发现后请加入（`env | sort`）。

## 事后复盘：uninstall 中的路径形式不匹配（已修复）

真实使用中报出的问题：卸载删除了钩子文件，却把全局
`core.hooksPath` 留了下来。根因：在 Windows 上安装和卸载可能在不同
shell 下运行，因此存下的值是 `C:/...`，而 `$HOME` 却展开为 `/c/...`
（MSYS 形式）。MSYS 在系统调用层做路径转换（这正是 `rm` 还能正常
工作的原因），但 `[ = ]` 是不感知文件系统的纯字符串比较。修复办法：
比较前用 `cygpath -m`（Windows 形式，正斜杠）把两边归一化。

代码库中沉淀了两条经验：

1. 回归测试先行：`test.sh` 中的场景 9 复现了该不匹配，并在修复前
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

原来的第 4 条（可配置受保护分支列表）已实现，见上文"决策 5"，
不再留在本清单里。
