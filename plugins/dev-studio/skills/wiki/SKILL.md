---
name: wiki
description: >
  个人知识库（Obsidian wiki vault）的唯一入口与控制面：记录、调研、蒸馏、摄入、查询、维护、可视化、自动化，一站式覆盖。
  Use this skill whenever the user wants to interact with their wiki / knowledge base / second brain / notes
  in any way — 写入或读取都走这里。触发词包括但不限于："wiki", "记到 wiki", "帮我记录今日笔记/工作日志",
  "帮我记录会议纪要", "记一下今天做了什么", "帮我调研某个 URL / 调研一下 X", "记录一下这个客户沟通",
  "帮我写周报/月报", "整理成文档存到 wiki", "把最近的笔记蒸馏一下 / 提炼知识 / 整理成概念页",
  "ingest 这些文档/PDF/网页", "导入我的 Claude/Codex 对话历史", "我知道关于 X 的什么 / 查一下 Y",
  "audit/lint 我的 wiki / 找坏链孤儿页 / 健康检查", "补交叉引用 / 归一标签 / 查重合并", "wiki 状态/进度",
  "导出图谱 / 着色 / 建仪表盘", "初始化/重建 vault", "设置定时任务/自动维护/自动周报",
  "log this", "record today's work", "research this url and save it", "distill my notes", "query my wiki",
  "lint/audit my wiki", "ingest these docs", "set up a cron for my wiki",
  "请使用 skill wiki 管理/处理这个文档" (bind an attached document as the vault). 它把零散口语扩写成专业中文文档并
  归档（日报/周报/月报、会议纪要、技术调研、日记），自动滚动汇总，蒸馏 journal/_raw 为知识页，并通过内置
  框架手册覆盖 obsidian-wiki 的全部 AI 能力（ingest/query/lint/cross-link/dedup/export/research/history-ingest/
  dashboard/rebuild 等）。vault 通过 .config/skills/wiki/wiki.json 绑定（先查 cwd，再查 ~），可关联任何本地
  git 目录或 AgentX 附加的 Library 文档；每次写完自动同步（git commit & push，或 AgentX 内走 save_document）。
---

# wiki — 个人知识库的唯一入口

这是用户知识库的**单一控制面**。用户只通过 `wiki` 这一个技能，就能完成对知识库的**所有读写**。你的职责是：理解用户意图 → 路由到正确的执行手册 → 执行 → 写完同步。

## 能力分层（路由优先级）

1. **日常主路径（本 SKILL.md 直接执行）**：记录（工作日报/会议纪要/日记/技术调研）、滚动汇总（周报/月报）、蒸馏（journal/_raw → 知识页）。这是 80% 的请求，下面 §1–§7 就是它的完整流程。
2. **全量能力（路由到 `references/capabilities.md`）**：ingest 外部文档、查询、lint、cross-link、dedup、export、research、AI 历史摄入、dashboard、rebuild、setup 等——覆盖 obsidian-wiki 的全部 AI 能力。**当请求不属于日常主路径时，读 `references/capabilities.md` 找到对应手册（`framework/<name>/SKILL.md`）再执行。**
3. **自动化（路由到 `references/automation.md`）**：定时任务（每日维护、自动周/月报、兜底同步）。

> **判断顺序**：先看请求是否属于「记录/汇总/蒸馏」→ 是则按本文执行；否则打开 `references/capabilities.md` 路由。拿不准就先读 capabilities.md。

## 自包含原则（关键）

整个知识库**只保留 `wiki` 这一个仓库**。obsidian-wiki 框架的全部能力已 vendored 进 `framework/`：
- 框架手册：`framework/<skill-name>/SKILL.md`（如 `framework/wiki-ingest/SKILL.md`）。
- 框架脚本：`framework/_scripts/`（manifest.py、extract-jsonl.py 等）。
- 理论参考：`framework/llm-wiki/SKILL.md`。

**执行框架手册时的路径改写**（手册是从上游原样搬来的，路径需就地映射）：
- 手册写 `.skills/<x>/SKILL.md` 或 `<x>/SKILL.md` → 实读 `framework/<x>/SKILL.md`
- 手册写 `scripts/<f>` → 实读 `framework/_scripts/<f>`
- 手册要 `OBSIDIAN_VAULT_PATH` / `.env` / Config Resolution Protocol → **一律改用** `scripts/locate-vault.sh` 的输出（见 §0），并用 §0 的默认约定补齐其它变量；缺 `.env` 不阻塞。
- 手册要更新 `index.md`/`log.md`/`hot.md`/`.manifest.json` → 这些都在 vault 根，照常维护。

每次写操作完成后，**自动同步**（§7：git 模式 commit & push；AgentX 内走 `save_document`）。

---

## 0. Before You Start — 定位 vault（wiki.json 绑定模型）

**技能与 vault 是解耦的**：本技能可以装在任何地方（AgentX 团队插件、~/.claude/skills、项目内），vault 通过一个小配置文件 **`wiki.json`** 绑定。**永远用脚本定位 vault，不要硬编码绝对路径**（脚本与本 SKILL.md 同在技能目录 `scripts/` 内）：

```bash
SKILL_DIR="<本技能目录>"                            # 含本 SKILL.md 的目录
VAULT="$(bash "$SKILL_DIR/scripts/locate-vault.sh" 2>/dev/null)"
```

`locate-vault.sh` 的解析顺序（先到先得）：
1. 环境变量 `WIKI_VAULT_PATH`（显式覆盖）。
2. **`$PWD/.config/skills/wiki/wiki.json`**（当前工作区绑定，优先）。
3. **`~/.config/skills/wiki/wiki.json`**（用户级默认绑定）。
4. 兼容旧布局：cwd 或技能真实路径向上找 `.wiki-vault` 标记（技能 vendored 在 vault 仓库内的旧模式）。

`wiki.json` 结构（通用设计——AgentX 聊天工作区和普通本地 Claude Code 均适用）：

```json
{
  "version": 1,
  "vault": "documents/wiki",     // 绝对路径、~ 前缀、或相对于含 .config/ 的目录
  "sync": "save_document",       // "git"（默认，本地 clone 直接 commit+push）
                                  // | "save_document"（AgentX 聊天内，经平台 git-first 提交）
  "document": {                   // 可选：AgentX Library 文档绑定元数据
    "id": "<library doc id>", "dir": "wiki", "title": "我的个人知识系统"
  }
}
```

**绑定（首次使用 / 用户说「请使用 skill wiki 管理这个文档」）**：用 `scripts/bind-vault.sh` 写入绑定：

```bash
# AgentX 聊天：用户附加了 Library 文档（已 materialize 到 documents/<dir>/，
# 系统提示的 "Attached Documents" 一节给出其路径与 id）——绑定它并走 save_document 同步：
bash "$SKILL_DIR/scripts/bind-vault.sh" documents/<dir> --sync save_document \
  --doc-id <library-doc-id> --doc-title "<标题>"

# 普通 Claude Code：绑定任何本地 git 目录（--global 写 ~/.config 作为用户默认）：
bash "$SKILL_DIR/scripts/bind-vault.sh" ~/Workspace/knowledge/wiki --sync git --global
```

**未绑定时**（locate-vault.sh 退出码 1）：**不要猜路径**。回复用户「wiki skill 尚未关联任何文档/目录」，并给出绑定方式：在 AgentX 里请用户附加要管理的文档后说「请使用 skill wiki 管理这个文档」；本地则告知 bind-vault.sh 用法。若当前对话恰好带着一个已 materialize 的文档且用户意图明确（如「用 wiki 管理这个文档」），直接执行绑定再继续。

确认 `VAULT` 后：
- **先 PULL 再动**（关键，读和写都要）：任何读取或写入 vault 之前，先运行
  ```bash
  bash "$SKILL_DIR/scripts/pull.sh"
  ```
  它按 `wiki.json` 的 `sync` 模式行动：`git` 模式执行真正的 `git pull --ff-only`
  （本地分叉且工作树干净时自动 rebase），把**其它设备**上记录的内容拉下来;
  `save_document` 模式下平台已在本回合开始时对文档做过增量 pull（PullItem）,
  脚本只汇报当前 checkout 的 HEAD。**这一步保证多端一致：别处写的日志，这里
  能立刻查到。** pull 失败不阻塞（继续用本地状态，push 时 sync.sh 会 reconcile）。
- **取当天日期**：`date "+%Y-%m-%d %A %H:%M"`（用真实日期，绝不臆测）。
- **语言**：一律中文写作；技术术语保留英文。
- **风格基准**：套用 `$VAULT/_templates/`（会议纪要/周报/日记/月记/技术调研等模板）与既有工作周报样例 `$VAULT/journal/2026/W*.md`（每周文件 = 每日记录 + 本周总结）。**模仿其结构、emoji、callout、表格**，不另起一套。

---

## 1. 判断意图（路由）

| 用户说类似… | 动作 | 去 |
|---|---|---|
| 「记录今日工作 / 工作日志 / 今天做了 X」（工作/客户/交付相关） | **写入当周周报的「当天」记录** | `$VAULT/journal/<YYYY>/W<ww>.md` 的「📅 每日记录」追加当天 `### MM/DD` 条目 |
| 「记录今日笔记 / 日记 / 复盘」（个人、非纯工作） | **个人日记** | `$VAULT/journal/<YYYY>/<YYYYMMDD>.md` |
| 「记录会议纪要 / 刚开了个会 / 和 X 沟通了」 | **会议纪要** | 见 §4：归入当周周报当天记录的会议纪要子节，或独立 `projects/<项目>/` 文件 |
| 「帮我调研 <URL> / 调研一下 X」 | **技术调研** | `$VAULT/projects/<项目>/` 或 `$VAULT/references/` |
| 「写周报 / 本周总结 / 帮我生成周报」 | **生成/刷新当周总结** | `$VAULT/journal/<YYYY>/W<ww>.md` 的「本周总结」（从同文件每日记录归纳） |
| 「写月报 / 月度总结」 | **月报**（从当月各周报汇总） | `$VAULT/journal/<YYYY>/M<MM>.md` |
| 「蒸馏 / 提炼 / 把笔记整理成概念页 / 沉淀知识」 | **蒸馏**（见 §6） | `concepts/ entities/ skills/ synthesis/` |
| 「记录一下 X」（其它） | **通用笔记** | 按主题判断 `projects/` 或 `_raw/`，不确定落 `_raw/` |
| **以上都不是**（ingest 文档/查询/lint/导出/历史摄入/初始化/定时…） | **路由到全量能力** | 读 `references/capabilities.md` 找手册 → 执行 |

不确定归哪个项目时，扫 `$VAULT/projects/` 现有目录（道通、宁德、KPI、R&D、Other、Learn）做最佳匹配；都不匹配则问一句或落 `_raw/`。

> 各类型详细写法见 `references/formats.md`；滚动汇总规则见 `references/rollup.md`；**全量能力路由见 `references/capabilities.md`**；定时任务见 `references/automation.md`；**Markdown 富文本/图表技法见 `references/markdown.md`（写任何页面前都应参考，尽量可视化）**。需要时读取它们获取精确步骤。

---

## 2. 扩写原则（口语 → 专业文档）

1. **扩写但不杜撰**：把要点扩展为完整专业表述，补结构（背景/讨论/结论/行动项）；**绝不编造**用户没给的事实（人名、数字、OPP ID、日期）。缺失处留 `{待补充}` 或省略该 section。
2. **尽量可视化（重点）**：写每一页前先想「这里有没有**关系**能画成 Mermaid 图、有没有**数据**能画成 Vega-Lite 图表」。流程/关系/层级/状态 → Mermaid；趋势/对比/占比/分布 → Vega-Lite；多维结构化信息 → 表格；结论/警告/提示 → callout。**优先图表，别只堆纯文字。** 具体语法与示例见 `references/markdown.md`。
3. **结构化**：用 vault 风格的表格、callout（`> [!success]`/`> [!warning]` 等）、`- [ ]` 任务。
4. **标题与摘要**：起专业标题；独立文件写 frontmatter `summary:`。
5. **保留信号**：把口语里隐含的决策、风险、next action 显式列出。
6. **可追溯**：调研类文末「来源」列 URL；从对话整理的注明日期。
7. **图表自检**：Vega-Lite 的 JSON 必须能被解析（逗号/引号/括号闭合）；Mermaid 节点文本可内嵌 `[[wikilink]]` 串联页面。

## 3. frontmatter 约定（独立文件时）

沿用 vault 既有标签体系（`type/` + `project/`）：

```yaml
---
tags:
  - type/meeting        # daily/weekly/monthly/journal/meeting/research/concept/skill/entity…
  - project/道通         # 关联项目（如适用）
created: "2026-06-29"
modified: "2026-06-29"
---
```

工作记录是**追加到当周周报文件**（`journal/<YYYY>/W<ww>.md`），沿用该文件既有 frontmatter（`type/weekly` + `project/KPI`），不为单天新建文件。

---

## 4. 各类型执行要点

### 工作记录（写入当周周报，最常用）
> 模型：**周报文件是工作记录的唯一载体**。一周一个 `journal/<YYYY>/W<ww>.md`，里面「📅 每日记录」按天累加，「本周总结」由这些天归纳。没有独立的"日报文件"。详细格式见 `references/formats.md`。
1. 用真实日期算当天所属 ISO 周：`TZ=Asia/Shanghai date +%V`（周一起始），得 `W<ww>` 与年份。
2. 打开 `$VAULT/journal/<YYYY>/W<ww>.md`；**不存在则新建**（按 `references/formats.md` 的周报骨架：frontmatter + 标题 + 周期 + 本周总结占位 + 「📅 每日记录」空节）。
3. 在「📅 每日记录」下插入当天 `### MM/DD (Day) ☀️` 条目，含用户提到的 `#### 🤝 客户互动`（表格 + `##### 会议纪要`）、`#### 📚 学习`、`#### 🔨 Build / Deliver`、`#### 💡 备注`；无内容 section 省略。每日记录**按日期逆序（最新的一天在最上面）**排列，各天之间用 `---` 分隔——所以新的一天插在「📅 每日记录」标题正下方、已有最新条目之前。
4. 当天条目已存在 → **合并**进去，不重复建。
5. 写完当天记录后，可顺手刷新「本周总结」（见 §5A），保持周报随时可读。

### 会议纪要
- **工作会议**：默认作为当周周报里当天记录下的 `##### 会议纪要 — {客户/对象} {主题}` 子节。
- **重要/独立会议**：用 `_templates/会议纪要模板.md` 结构建独立文件，放 `projects/<项目>/`，文件名 `YYYY-MM-DD <主题> 会议纪要.md`。

### 技术调研（「帮我调研 <URL>」）
1. 给了 URL：用 `defuddle` skill 抓正文（`defuddle parse <url> --md`）读懂；多个来源逐个抓。
2. 按 `_templates/技术调研模板.md` 扩写：技术概述、对比、（如适用）PoC、优劣分析、结论。
3. 放 `projects/<相关项目>/` 或 `references/`（通用主题）；文件名用调研主题；文末列所有 URL。

### 个人日记 / 周报 / 月报
- 日记套 `_templates/日记模板.md`，放 `journal/<YYYY>/<YYYYMMDD>.md`。
- 周报/月报见 §5。

---

## 5. 工作周报（每日记录 + 本周总结，单文件）

**核心模型**：工作记录与周总结**同住一个周报文件** `journal/<YYYY>/W<ww>.md`：
- 上半部「📅 每日记录」= 每天按 `### MM/DD (Day)` 累加的明细（§4 写入），**按日期逆序，最新一天在最上**；
- 顶部「本周总结」callout = 从这些每日记录归纳的本周综述。

二者都要有：明细保证可追溯，总结保证可速读。**没有独立的"日报文件"，也不再用 `projects/KPI/...`。**

**工作周定义：周一 00:00 ~ 周日 23:59（北京时间，Asia/Shanghai）。** ISO 周号：`TZ=Asia/Shanghai date +%V`（周一起始）。

### 5A. 生成 / 刷新「本周总结」

用户说「写周报 / 本周总结」时，**从同一周报文件的每日记录自动归纳，不让用户重述**：

1. **定位周报文件**：算目标周次（默认本周；用户可指定「上周」「W25」等），打开 `$VAULT/journal/<YYYY>/W<ww>.md`。文件不存在 → 提示「本周（W<ww>）还没有任何记录，先记录今天的工作？」。
2. **读「📅 每日记录」全部当天条目**，归纳为「本周总结」callout（`> [!abstract] 本周总结`），覆盖：
   - **关键交付**：汇总各天 `🔨 Build / Deliver`，去重合并同类项，标状态（✅完成/🔄进行中/❌延期）。
   - **客户互动 / 对外协作**：汇总各天 `🤝 客户互动`，按客户归组；重要会议附一句摘要。
   - **项目推进**：跨多天的同一项目进展合并为一条叙述（体现脉络而非流水）。
   - **一句话主线**：本周最重要的 1~2 件事。
   - **下周计划**：从未完成 Action Items（`- [ ]`）+ 用户补充提取；无则留 `{待补充}`。
   - **风险与阻塞**：提取明确标记的风险/延期/阻塞；无则省略。
3. **写回**：替换/更新该文件顶部的「本周总结」callout，**不动「📅 每日记录」明细**。可在文件 frontmatter 补 `summary:` 一行（便于索引预览）。
4. **汇报**：告知「已刷新 W<ww> 本周总结，覆盖 <周一>~<周日>，归纳 N 天记录」，附一句话主线。

> 扩写不杜撰：只从已有每日记录提炼，缺数据留 `{待补充}`，不捏造人名/数字/OPP ID。

### 5B. 月报汇总

- **月报**：读当月覆盖的各周报 `journal/<YYYY>/W<ww>.md`（含其每日记录与本周总结）→ 按 `_templates/月记模板.md` 归纳 → 写 `journal/<YYYY>/M<MM>.md`。优先用各周「本周总结」做二次归纳（已去噪），需要细节再回看每日记录。

详细抽取/去重/归类算法见 `references/rollup.md`。

---

## 6. 蒸馏能力（journal/_raw → 知识页）

实现 [[docs/02-目录结构设计]] 的三流：`_raw/`（闪念）→ `journal/`（日常流水）→ `concepts/entities/skills/synthesis`（永久知识）。

触发：「蒸馏」「提炼」「把最近笔记整理成知识/概念页」「沉淀一下」。

**流程：**
1. **选源**：默认扫最近的 `journal/<YYYY>/` 日记与 `_raw/` 草稿（或用户指定的文件/时间范围）。
2. **抽信号**：从流水里识别可复用的——概念/模式（→`concepts/`）、工具/人/产品（→`entities/`）、操作方法/流程（→`skills/`）、跨多概念的分析（→`synthesis/`）。**丢弃**纯流水账、一次性琐事、已是常识的内容。
3. **归并而非新建**：目标知识页若已存在 → 合并新信息、标矛盾、强化交叉引用；确实新 → 按 [[docs/02-目录结构设计]] 的页面模板建页（必备 frontmatter：title/category/tags/summary/sources/created/updated；可选 provenance/lifecycle）。
4. **provenance 标记**：来源确实说的=默认无标记；LLM 推断的连接/推论加 `^[inferred]`；来源冲突加 `^[ambiguous]`。新蒸馏页 `lifecycle: draft`。
5. **双向链接**：蒸馏页 `sources:` 指回原 journal/_raw 文件；并在原 journal 条目里加 `[[concepts/xxx]]` 反向链接（「这天想清楚了 X」）。
6. **维护导航**：更新 `index.md`（按分类列出新页 + 一行摘要）；相关主题已有 MOC 时在 `maps/<主题>地图.md` 挂上新页。
7. **`_raw/` 提升**：被完全蒸馏的 `_raw/` 草稿，蒸馏后可移除原件（确认无其它副本）；journal 是时间记录，**保留不删**。

蒸馏要**保守**：宁可少提炼高质量页，不要把噪音灌进知识层。

> 详细页面模板/置信度/生命周期/分层检索规则见 `framework/llm-wiki/SKILL.md`，或本仓库 [[docs/01-理念与架构]]。需要更强的摄入/综合/查重时，转 `framework/wiki-ingest`、`framework/wiki-synthesize`、`framework/wiki-dedup`（路由见 `references/capabilities.md`）。

---

## 7. 收尾：写文件 + 自动同步

1. **写文件**（新建或合并追加）；合并时保留既有内容，只增量插入。
2. **自动同步**——每次记录/蒸馏后运行技能内脚本（相对本技能目录）：
   ```bash
   bash "$SKILL_DIR/scripts/sync.sh" "record: <简述本次记了什么>"
   ```
   `sync.sh` 读取 `wiki.json` 的 `sync` 字段决定同步方式：
   - **`git`（默认，本地 clone）**：自行定位 vault，`git add -A` + commit + push origin；无改动时安静跳过。
     > **多端并发与冲突策略（重要）**：vault 可能被**多台设备同时 push 到 `main`**。push 被拒时 `sync.sh` 自动 `fetch` 并以**「远端为准」（remote-wins）** 合并——非冲突的本地改动保留，冲突内容一律采用远端版本，然后重试 push（最多 5 轮）。调用方**不需要**自己 `git pull`/处理冲突；它任何情况下都不会 hard-fail 中断记录。
   - **`save_document`（AgentX 聊天内）**：vault 是平台 materialize 的 Library 文档（无推送凭证），脚本**不做**本地 commit/push，而是输出一行 `NEXT STEP FOR THE AGENT: call the save_document tool …`。**看到这个输出后，你必须立即调用 `save_document` 工具**（参数：`doc_dir` = 输出给出的目录名、`message` = 输出给出的提交信息）——它经平台 git-first 提交并 push，提交归属当前用户。这就是 AgentX 模式的「自动 commit & push」。
3. **简短回执**：告诉用户「记到了哪个文件/section、文档标题、已同步（附 commit 链接如有）」，附 1-2 句摘要。**不要把整篇贴回对话。**

> **任何写操作都收尾同步**——无论走日常主路径还是 `framework/` 手册（ingest/research/history-ingest/lint --consolidate 等），完成后都运行 `scripts/sync.sh`（save_document 模式则接着调用工具）。只读操作（query/status/digest/export 到对话）不必同步。

## 原则
- **唯一入口**：用户只用 `wiki` 一个技能完成所有读写；不属于日常主路径的，查 `references/capabilities.md` 路由到 `framework/` 手册。
- **先定位再动笔**：用 `scripts/locate-vault.sh` 找 `VAULT`，判意图与目标文件，再写。
- **先 pull 再读写**：任何读/写前先 `scripts/pull.sh`——多端同步的正确性来自「读前拉、写后推」两端闭环。
- **自包含**：框架能力都在 `framework/` 内；执行时套用 §「自包含原则」的路径改写，不依赖外部 obsidian-wiki 安装或 `.env`。
- **扩写不杜撰**：补结构与专业表述，不补事实。
- **沿用既有风格**：模仿 `_templates/` 与既有周报 `journal/2026/W*.md`。
- **尽量可视化**：能画 Mermaid/Vega-Lite 就别只堆文字；语法见 `references/markdown.md`。
- **滚动汇总**：周/月报永远从日报自动归纳。
- **蒸馏保守**：只沉淀高价值、可复用的知识，双向链接、标注 provenance。
- **每次必同步**：写完即 `sync.sh`，保证单仓库始终是最新真相。
- **headless 友好**：被 cron/`claude -p` 调用时不反问，自主完成，占位代替阻塞（见 `references/automation.md`）。
