# wiki 能力地图（路由表）

`wiki` 是唯一入口。所有知识库能力都从这里路由。本表把**用户意图**映射到**执行手册**。手册分两类：

- **原生手册**（本技能 `references/` 内）：日常记录/调研/蒸馏的精炼流程，是最常用路径。
- **框架手册**（本技能 `framework/<name>/SKILL.md`）：从 obsidian-wiki 完整能力集 vendored 进来的详细流程。需要时**读取对应文件**再执行；它们引用的 `llm-wiki/SKILL.md`、`scripts/` 等也都在 `framework/` 内。

> 执行框架手册时的路径改写：手册里写 `.skills/llm-wiki/SKILL.md` → 实读 `framework/llm-wiki/SKILL.md`；写 `scripts/manifest.py` → 实读 `framework/_scripts/manifest.py`。`OBSIDIAN_VAULT_PATH` 一律由 `scripts/locate-vault.sh` 解析得到，不要硬编码或要求 `.env`。

---

## A. 写入 · 记录（最常用，走原生手册）

| 用户意图 | 手册 | 输出位置 |
|---|---|---|
| 记录今日工作 / 工作日志 | 本技能 §4 + `references/formats.md` | `journal/<YYYY>/W<ww>.md` 的「每日记录」 |
| 记录会议纪要 / 客户沟通 | 本技能 §4 + `references/formats.md` | 日报子节 或 `projects/<项目>/` |
| 记今日笔记 / 写日记 | 本技能 §4 + `references/formats.md` | `journal/<YYYY>/<YYYYMMDD>.md` |
| 写周报 / 月报（自动汇总） | 本技能 §5 + `references/rollup.md` | `journal/<YYYY>/W##.md` · `M##.md` |
| 帮我调研 <URL> / 调研 X | 本技能 §4（用 defuddle 抓取） | `projects/<项目>/` 或 `references/` |
| 把对话/这段内容存进 wiki | `framework/wiki-capture/SKILL.md` | 自动分类落页；`--quick` 落 `_raw/` |
| 通用速记 / 记一下 X | 本技能 §4 | `_raw/` 或就近项目 |

## B. 写入 · 蒸馏与摄入（外部素材 → 知识页）

| 用户意图 | 手册 |
|---|---|
| 蒸馏/提炼 journal、_raw → 概念页 | 本技能 §6 |
| ingest 文档/PDF/文件夹/网页/导出/日志/图片 | `framework/wiki-ingest/SKILL.md` |
| 多轮联网研究并自动归档 | `framework/wiki-research/SKILL.md` |
| 把当前所在项目的知识同步进 wiki | `framework/wiki-update/SKILL.md` |
| 找概念共现、补综合页 | `framework/wiki-synthesize/SKILL.md` |

## C. 写入 · AI 对话历史摄入（跨工具记忆）

| 用户意图 | 手册 |
|---|---|
| 统一入口：导入某工具历史 | `framework/wiki-history-ingest/SKILL.md`（路由到下列） |
| 导入 Claude / Codex / Copilot / Hermes / OpenClaw / Pi 历史 | `framework/<tool>-history-ingest/SKILL.md` |
| 按主题从某工具历史定向摄入并答复 | `framework/wiki-agent/SKILL.md`（/wiki-claude /wiki-codex…） |
| 按"哪个工具产出"浏览/对比知识、找盲区 | `framework/memory-bridge/SKILL.md` |

## D. 读取 · 查询与上下文

| 用户意图 | 手册 |
|---|---|
| 我知道关于 X 的什么 / 查 Y / 多跳关联 | `framework/wiki-query/SKILL.md` |
| 生成 token 受限的上下文包（喂给别的任务） | `framework/wiki-context-pack/SKILL.md` |
| 周/月「我学到了什么」可读摘要 | `framework/wiki-digest/SKILL.md` |

## E. 维护 · 健康与治理

| 用户意图 | 手册 |
|---|---|
| audit / lint / 坏链 / 孤儿页 / 矛盾 / 健康检查 | `framework/wiki-lint/SKILL.md`（`--consolidate` 修复模式） |
| 自动补缺失交叉引用 / 连接孤儿页 | `framework/cross-linker/SKILL.md` |
| 标签归一 / 维护受控词表 | `framework/tag-taxonomy/SKILL.md` |
| 查重 / 合并同义页 / 身份消解 | `framework/wiki-dedup/SKILL.md` |
| 状态/进度：已 ingest vs 待处理、delta、hubs、token footprint | `framework/wiki-status/SKILL.md` |
| 每日维护循环（freshness + index + hot.md），可挂 cron | `framework/daily-update/SKILL.md` |
| 校验某次实现/输出是否达标（自检） | `framework/impl-validator/SKILL.md` |

## F. 结构 · 初始化与重建

| 用户意图 | 手册 |
|---|---|
| 初始化 vault 结构/特殊文件 | `framework/wiki-setup/SKILL.md` |
| 归档并重建 / 从归档恢复 | `framework/wiki-rebuild/SKILL.md` |
| 多 vault 配置切换 | `framework/wiki-switch/SKILL.md` |
| 暂存写入 → 人工审阅后提升 | `framework/wiki-stage-commit/SKILL.md` |

## G. 可视化 · 导出 · 打包

| 用户意图 | 手册 |
|---|---|
| 导出图谱 JSON/GraphML/Neo4j/HTML/OKF | `framework/wiki-export/SKILL.md` |
| 从导出/OKF 导入知识图谱 | `framework/wiki-import/SKILL.md` |
| 给 Obsidian 图谱按 tag/分类/可见性着色 | `framework/graph-colorize/SKILL.md` |
| 建 Obsidian Bases/Dataview 动态仪表盘 | `framework/wiki-dashboard/SKILL.md` |
| 把成熟知识页打包成可移植 Agent Skill | `framework/vault-skill-factory/SKILL.md` |

## H. 理论参考

| 用户意图 | 手册 |
|---|---|
| 理解 LLM Wiki 模式/三层架构/页面模板/置信度/生命周期/分层检索 | `framework/llm-wiki/SKILL.md` + 本仓库 `docs/` |

---

## 路由原则

1. **先匹配最常用的 A/B**（记录、蒸馏）——这是日常主路径，多数请求落在这里，直接按本 SKILL.md 主体执行。
2. **其它意图**：在上表找到手册，**读取该文件**，按其步骤执行，套用「路径改写」规则。
3. **配置统一**：所有手册需要 `OBSIDIAN_VAULT_PATH` 时，用 `scripts/locate-vault.sh` 的输出；需要 `.env` 变量时，缺省即用约定默认（见本 SKILL.md §0）。
4. **写完必同步**：任何写操作后运行 `scripts/sync.sh`（见本 SKILL.md §7），保证单仓库始终是最新真相。
5. **尽量可视化**：写任何页面都参考 `references/markdown.md`，优先用 Mermaid（关系/流程）和 Vega-Lite（数据）而非纯文字。
6. **拿不准就先读手册再动手**，不要凭记忆执行框架流程。
