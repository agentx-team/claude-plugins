# wiki 自动化（定时任务）

目标：让 wiki 在无人值守时也保持鲜活——定时维护、定时汇总、定时备份。所有定时任务都通过 `claude -p`（headless）调用 `wiki` 技能，因此**一个技能即覆盖手动与自动两种触发**。

> 触发：用户说「设置定时任务 / 每天自动维护 / 自动生成周报 / 装个 cron / 定时同步」。

## 前置

- 技能已挂载：`ln -sf <clone>/.skills/wiki ~/.claude/skills/wiki`。
- `claude` CLI 可用，且能在非交互模式跑：`claude -p "<prompt>"`。
- vault 由 `scripts/locate-vault.sh` 可定位（git 仓库 + `.wiki-vault`）。

## 推荐的定时编排

用 crontab（Linux）。安装：把下面写进 `crontab -e`（按需调整时间/路径）。每条都先 `cd` 到 vault 再调用，确保 `claude` 在仓库上下文里运行。

```cron
# 环境：让 cron 能找到 claude（按你的安装路径改）
PATH=/usr/local/bin:/usr/bin:/bin:/home/core/.local/bin

# 工作日 09:00 — 在当周周报里起草当天「每日记录」条目（带昨天遗留 Action Items）
0 9 * * 1-5 cd $(bash ~/.claude/skills/wiki/scripts/locate-vault.sh) && claude -p "wiki：在当周周报 journal/<YYYY>/W##.md 的每日记录里起草今天的条目，把昨天未完成的 Action Items 带过来；无新内容则只建当天空条目。完成后同步。" >> ~/.wiki-cron.log 2>&1

# 每周五 18:00 — 从当周周报的每日记录刷新「本周总结」
0 18 * * 5 cd $(bash ~/.claude/skills/wiki/scripts/locate-vault.sh) && claude -p "wiki：从当周周报 journal/<YYYY>/W##.md 的每日记录归纳并刷新「本周总结」，完成后同步。" >> ~/.wiki-cron.log 2>&1

# 每月最后一天 18:30 — 月报
30 18 28-31 * * [ "$(date -d tomorrow +\%d)" = "01" ] && cd $(bash ~/.claude/skills/wiki/scripts/locate-vault.sh) && claude -p "wiki：生成本月月报（从本月日报+周报汇总），写入 journal/<YYYY>/M##.md 并同步。" >> ~/.wiki-cron.log 2>&1

# 每天 09:30 — 每日维护循环（freshness + index + hot.md）
30 9 * * * cd $(bash ~/.claude/skills/wiki/scripts/locate-vault.sh) && claude -p "wiki：运行每日维护（daily-update：检查来源新鲜度、更新 index、重建 hot.md），完成后同步。" >> ~/.wiki-cron.log 2>&1

# 每周日 03:00 — 健康巡检 + 自动补链（保守 consolidate）
0 3 * * 0 cd $(bash ~/.claude/skills/wiki/scripts/locate-vault.sh) && claude -p "wiki：跑 lint 健康检查并对明确问题做 cross-linker 补链；有改动则同步。" >> ~/.wiki-cron.log 2>&1

# 每小时 — 兜底同步（防止有改动未推送）
0 * * * * bash ~/.claude/skills/wiki/scripts/sync.sh "hourly auto-sync" >> ~/.wiki-cron.log 2>&1
```

## 安装/卸载提示

- 安装：把上述行追加进 `crontab -e`；先用 `crontab -l` 看现有内容避免覆盖。
- 校验 `claude` 路径：`which claude`，把目录加进 cron 的 `PATH`。
- 日志在 `~/.wiki-cron.log`，排障时 `tail -f`。
- 卸载：`crontab -e` 删掉对应行。

## headless 调用约定（给执行这些任务的自己）

- cron 调用是非交互的：**不要反问用户**，按提示自主完成；信息不足时记录为占位 `{待补充}` 而非阻塞。
- 每个任务结尾都要 `scripts/sync.sh` 同步；push 失败不致命（下一次兜底同步会补）。
- 维护类任务（lint/daily-update）默认**保守**：只做明确无歧义的修复，存疑项写进报告不擅自改。

## 可选：macOS launchd

vendored 框架带了一个 launchd 样例：`framework/_scripts/com.obsidian-wiki.daily-update.plist` 与 `framework/_scripts/daily-update.sh`。在 macOS 上可参照它把每日维护装成 LaunchAgent；把其中的 vault 路径与技能调用换成本技能的 `claude -p "wiki：..."` 形式即可。
