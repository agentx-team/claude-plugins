# Agent 低代码托管平台 — 设计文档

> 目标：让用户通过 **fork `agent-team-scaffold` 模板、只改 markdown / json / yaml** 就能自定义
> **Memory、Dreams、Per-Agent Context、Knowledge**，完全不接触任何底层 API。

本文是平台的**架构与概念设计**；面向使用者的操作步骤见 [`platform-guide.zh.md`](platform-guide.zh.md)。

---

## 0. 这个仓库在你的平台里的位置（先读这一节）

**一个 GitHub 仓库 = 一个 Claude Plugin = 一个 Agent Team。** 本脚手架就是这样一个「Agent Team
仓库」。它有**两个部署目标**，同一份源码（`agents/` + `skills/` + `commands/` + `scripts/cma/`
+ `cma.yaml`）两处兑现：

| 部署目标 | 兑现方式 | 记忆 | 知识 / RAG | 适用 |
|---|---|---|---|---|
| **CMA**（Claude Managed Agents，Anthropic 托管） | `scripts/cma/deploy.py`（本仓库内置） | memory store（`/mnt/memory/`） | **文件系统检索**（grep/read）；向量检索靠 MCP | 快速起步、无自有平台时 |
| **AgentX**（你的自托管平台，`agentx.nx.run`） | **git-sync 服务**把本仓库同步进平台 | **AgentCore Memory**（Semantic/UserPreference/Summary，每 Specialist 独立） | **Bedrock Knowledge Base + Neptune GraphRAG**（真·向量+图检索） | 生产、多租户、已有文档/知识库/技能管理 |

**关键:本脚手架不重新发明你 AgentX 平台已有的管理能力**，而是作为它的**输入物（Agent Team
仓库）**对接。AgentX 侧已具备的多维管理(见 §2.5)直接复用:

- **Library**(`/library/documents|knowledge|skills`)—— 文档管理、知识库管理、Skills 管理
- **Connectors**(`/settings/connectors`)—— MCP / APP 连接器与 GitHub 凭证管理
- **My Team / Specialists** —— 角色(人格层)管理 + 挂载 skill/memory
- **git-sync** —— 按 org 约定仓库(`{org}/documents|knowledge|skills|agents`)自动同步与写回

因此本脚手架的 `cma.yaml` 主要服务 **CMA 目标**；当部署到 **AgentX** 时,`memory_stores:` /
`knowledge:` 目录是**对接 AgentX 既有 Library/Knowledge/Memory 的声明清单**(见 §2.5 的映射),
而非平台要新建的子系统。

---

## 1. 四层模型（核心心智模型）

平台把「智能体」抽象成四层。理解这四层及其**生命周期**，是用对记忆/知识/上下文的前提。

```
Agent（智能体）──────────────────────── 你 fork 出来的这一个模板仓库
  │   身份 + 智能体级记忆/知识（所有 project 共享）
  │
  ├── Project A（项目）──────────────── 一个 agent 下可开多个 project，彼此隔离
  │     │   项目级记忆/知识（仅本项目可见，每个项目各一份）
  │     │
  │     ├── Session 1（会话）────────── 一个 project 下可开多个会话 = 多次独立任务
  │     │     └── Context（上下文）──── 仅本会话有效，会话结束即消失
  │     ├── Session 2
  │     └── Session 3
  │
  └── Project B
        └── Session 1 …
```

| 层 | 是什么 | 生命周期 | 承载的记忆/知识作用域 |
|---|---|---|---|
| **Agent** | 你 fork 的模板（一个智能体团队） | 永久（直到删除/改版） | `agent` 级 —— 所有 project 共享一份 |
| **Project** | agent 下的逻辑分组（一条业务线/一个客户/一个产品） | 长期（跨多个会话存在） | `project` 级 —— 每个 project 各一份，互不可见 |
| **Session** | 一次具体任务（独立沙箱 + 对话线程） | 单次任务 | `session` 级 —— 每个会话新建，结束即弃 |
| **Context** | 会话的对话历史 + 沙箱状态 | **仅本会话**；结束即消失 | 不持久——要保留必须写入 store |

### 一句话区分「上下文」和「记忆」

> **上下文（Context）= 会话本身，临时的；记忆（Memory）= 你写进 store 的东西，跨会话存活。**
> 作用域（scope）决定「哪些会话共享同一个 store」。

这正是用户最容易混淆的点：「我让 agent 记住的东西为什么下次没了？」——因为它只活在**上下文**里。
要长期记住，必须落到某个 scope 的 **memory store**。

---

## 2. 映射到 Managed Agents 原语

平台不发明新概念，而是把四层模型**直接映射**到官方 Managed Agents 原语（见
[`memory-and-dreams.md`](memory-and-dreams.md) 的逐字引用与 JSON 形状）：

| 平台概念 | Managed Agents 原语 | 说明 |
|---|---|---|
| Agent | **agent 定义**（`POST /v1/agents`）+ `multiagent` coordinator 名册 | 创建一次，跨 project / session 复用 |
| Project | **一组 project 级 memory store + knowledge 的集合** | 「项目」是逻辑分组，不是 API 实体；靠「挂哪几个 store」体现 |
| Session | **session**（`POST /v1/sessions`，独立沙箱+线程） | 真正的运行实例；任务在此发生 |
| Context | **会话的对话历史 + 沙箱文件系统** | 官方明确：「每个会话默认从全新上下文开始」 |
| Memory（持久记忆） | **memory store**（`resources[]` 挂载到 `/mnt/memory/`） | **在会话创建时挂载**，不是 agent 的字段 |
| Knowledge（RAG） | **file / github_repository 资源**（挂进沙箱，grep/read 检索） | **没有原生向量检索**；语义检索用 MCP server |
| Dreams（记忆自整理） | **dream 异步任务**（读 1 个 store + ≤100 会话 → 产出新 store） | 输入不变，产出可审阅后再采用 |
| Per-Agent Context（子 agent 独立上下文） | **multiagent 线程**（每个子 agent 独立 thread/上下文/工具/MCP） | 一级委派；最多 20 名册 / 25 并发线程 |

**关键事实（决定整个设计）：**
1. 记忆/知识都在**会话创建时**通过 `resources[]` 挂载——**不是 agent 上的字段**。
2. 「作用域」不是某个 API 字段，而是**「把哪个 store、以什么 access、挂到哪些会话」的模式**。
3. 子 agent 的「独立上下文」来自 multiagent：「每个 agent 在自己的线程里运行……工具、MCP、
   上下文都不共享」。

> **AgentX 目标的等价物**：上表是 CMA 的原语；部署到 AgentX 时分别对应 AgentCore Harness/Session、
> AgentCore Memory、Bedrock Knowledge Base、@specialist 子 Agent（见 §2.5）。脚手架的概念一套，
> 两个运行时各自兑现。

---

## 2.5 映射到 AgentX 既有管理平台（文档 / 知识库 / Skills / 连接器 / 角色 / 记忆）

你的 AgentX 平台已经提供了多维管理面板。本脚手架仓库**作为输入物**对接它们，不重复造轮子。
对应关系如下（左：脚手架里的声明；右：AgentX 既有的管理面板与服务）：

| 脚手架里的概念 | AgentX 管理面板 / 服务 | 运行时载体 | 说明 |
|---|---|---|---|
| `skills/**/SKILL.md` | **Library → Skills**（`/library/skills`，SkillService） | 写入 `/workspace/.opencode/skills/` 或注入 system prompt | Skills 是平台一等公民；git-sync 把本仓库 `skills/` 同步进 Library |
| `knowledge:`（`type: file`） | **Library → Documents**（`/library/documents`） | S3 + DB 索引 | 单文档；放进约定仓库 `{org}/documents/<name>/` |
| `knowledge:`（语料/向量检索） | **Library → Knowledge**（`/library/knowledge`，KnowledgeService） | **Bedrock Knowledge Base + Neptune GraphRAG** | **真·向量+图检索**（不是 CMA 的 grep）；`knowledge/v1beta` |
| `.mcp.json` / MCP server | **Connectors**（`/settings/connectors`，ConnectorService：`mcp_remote`/`mcp_local`/`app`） | 写入 OpenCode config `mcpServers`，或 connector-as-MCP-bridge | 凭证 AES-256-GCM 存 MongoDB，按调用注入 |
| `agents/specialists/**`（人格层） | **My Team → Specialists**（SpecialistService） | claude-agent-sdk `AgentDefinition` / @specialist 子 Agent | 每个 Specialist 独立 system prompt + skills + memory |
| `agents/workflows/**`（编排） | **Workflow Map**（聊天右侧编排可视化，WorkflowService） | orchestrator agent 串联 leaves | 一级委派的可视化 |
| `commands/**` | 输入框 `/` **Actions** 菜单 | SDK slash command | — |
| 整个仓库 | **`/agents` 市场 + git-sync** | 一个 git 仓库 → 一个 PVC 目录 | 一仓库 = 一 Plugin = 一 Team |
| `memory_stores:`（各 scope） | **AgentCore Memory**（Semantic / UserPreference / Summary） | 按命名空间隔离，每 Specialist 独立 | 见下方「记忆映射」 |

### 记忆映射：scope ↔ AgentCore Memory 命名空间

CMA 用 memory store，AgentX 用 **AgentCore Memory**（托管，跨会话）。脚手架的 `scope` 直接翻译为
AgentCore Memory 的**命名空间隔离维度**：

| 脚手架 scope | CMA 兑现 | AgentX 兑现（AgentCore Memory 命名空间） |
|---|---|---|
| `agent` | 一个共享 memory store | 按 **agent/team** 命名空间——所有 project 共享 |
| `project` | 每 project 一个 store | 按 **project（租户）** 命名空间——项目间隔离 |
| `session` | 每 session 新建 store | 会话短期状态（microVM 内，结束即弃） |
| 角色私有（leaf `memory:`） | 该角色挂自己的 store | **每个 Specialist 独立记忆**（「This specialist builds knowledge as it works」） |

> 因此用户在 `cma.yaml` 里写的 `scope`，在 AgentX 侧由 git-sync / 运行时翻译为对应的 AgentCore
> Memory 命名空间与 Specialist 记忆挂载——**用户依旧只改 yaml**。

### git-sync 同步约定（AgentX 侧，已设计）

git-sync 以 **org 约定仓库**（`{org}/documents|knowledge|skills|agents`，main 第一层子目录 = 一个
条目）+ **topic 独立仓库**（整仓库 = 一个条目）同步内容；区分 **official org**（服务配置、只读
skills+agents）与 **custom org**（`/settings/connectors` 配置、读写全部四类，可写回）。本脚手架
作为一个 `agents` 类的 **topic 独立仓库**或约定仓库子目录被同步进 `/agents` 市场。
（详见 AgentX 的 `docs/agent-teams-design.md` 第 4 节。）

---

## 3. 记忆作用域（scope）的精确语义

平台在 `memory_stores:` / `knowledge:` 目录里给每个库标一个 `scope`，`build.py` 据此为
**每个 (project, session)** 生成正确的占位符，平台据此**创建/复用**真实的 store id：

| scope | 占位符形态 | 创建/复用规则 | 典型用途 |
|---|---|---|---|
| `agent` | `${MEMSTORE_<KEY>}` | 整个 agent **一份**，所有 project / session 共享 | 团队规范、智能体自身的跨项目校准记忆 |
| `project` | `${MEMSTORE_<KEY>__<PROJECT>}` | **每个 project 一份**，项目间隔离 | 本项目的决策、术语、历次结论 |
| `session` | `${MEMSTORE_<KEY>__SESSION}` | **每个 session 新建**，结束即弃 | 临时草稿、上下文外溢的落盘点 |

> 平台运行时维护一张映射表：`(scope, key, project?, session?) → memstore_…`。
> 首次遇到就调 `POST /v1/memory_stores` 创建并缓存；之后按 scope 复用。用户**永远看不到**
> 这张表，只看到 yaml 里的 `scope`。

### access 与防注入

- `read_only`：参考资料、共享规范。**强烈建议**所有「知识」和「团队规范」用只读。
- `read_write`：agent 需要写入的记忆（项目记忆、角色校准）。
- 安全红线（官方警告）：`read_write` + 不可信输入 = 提示注入可污染记忆，后续会话当作可信读取。
  平台默认把知识/规范设为 `read_only`，并保留脚手架「规划员是 schema 约束的只读 reader」的护栏。

---

## 4. Knowledge / RAG 的设计取舍

Managed Agents **没有原生向量库 / 嵌入索引 / `rag_search` 工具**。因此平台的知识模型是：

- **知识 = 挂进沙箱的文档**（上传的 `file`，或一个 `github_repository`）。
- **检索 = agent 用 `grep` / `glob` / `read`** 在挂载点上找（外加 `web_search` / `web_fetch`）。
- **语义检索 = 自带向量库做成 MCP server**（在 `.mcp.json` 声明，按角色 `mcpServers` 授权）。

平台在 `knowledge:` 目录里声明知识来源与 scope，`build.py` 把它们和记忆一起注入会话
`resources[]`。这样「项目级知识」就和「项目级记忆」一样，每个 project 各挂各的。

### 两个目标的 RAG 能力差异（重要）

| | **CMA 目标** | **AgentX 目标** |
|---|---|---|
| 知识载体 | 挂进沙箱的文件 / 仓库 | **Bedrock Knowledge Base**（S3 向量化）+ **Neptune GraphRAG** |
| 检索方式 | `grep` / `glob` / `read`（文件系统） | **向量相似度 + 图游走 + 融合重排序**（真·语义检索） |
| 语义检索 | 需自带向量库做成 MCP | **平台原生**（KnowledgeService，`knowledge/v1beta`） |
| 管理面板 | 无（声明在 yaml） | **Library → Knowledge / Documents** |

也就是说：**部署到 AgentX 时你自动获得真正的向量 RAG**，无需 MCP 变通——`knowledge:` 里 scope=
`project` 的语料会落进该项目（租户）的 Bedrock Knowledge Base，检索结果注入 system prompt。CMA
目标则退化为文件系统检索（脚手架默认形态，零依赖可跑）。这是「一份声明、两处兑现，能力按目标增强」。

---

## 5. Dreams（记忆自整理）的设计

记忆是增量写入的，久了会有重复/矛盾/过时。**Dream** 是异步任务：读 1 个输入 store + 1~100
个历史会话 → 产出一个**全新、整理过**的 store（输入不动，可审阅后采用）。平台把它定位为
**协调员（coordinator）的运维动作**：

- 触发：一个项目跑了一批会话后（如冲刺结束），对该项目的 `project-context` 或 agent 级
  `evaluator-calibration` 发起 dream。
- 采用：dream 产出新 store id；平台把映射表里对应 scope 的指向**切到新 store**，旧的归档。
- 红线：**人工审阅后才采用**。dream 产出不自动替换正在用的记忆。

> Dreams 与 MCP 隧道目前是**研究预览**，需额外 `dreaming-2026-04-21` beta 头并申请开通。
> 平台把它做成「可选增强」：未开通时，记忆仍可手动用 Memory Stores API 修剪。

---

## 6. Per-Agent Context（子 agent 独立上下文）的设计

脚手架的本地一级委派（`coordinator → planner → design-evaluator → generator → evaluator
→ packager`）在 headless 侧映射为 **multiagent coordinator**：

- coordinator 是主线程；名册里每个子 agent 在**自己的线程**里跑，**上下文/工具/MCP 不共享**。
- 每个子 agent 用自己的 agent 定义（model / system / tools / mcp_servers）。
- 一级委派（depth>1 忽略）；名册 ≤ 20；并发线程 ≤ 25。

**真正的「子 agent 私有记忆 + 私有上下文」** = 给该子 agent 自己的 agent 定义 + 让它在**自己的
会话**里跑，且只挂它自己的 store。平台据此把 `scope: agent` 的角色私有库（如
`evaluator-calibration`）只在该角色的线程/会话注入。

---

## 7. 配置即产品：用户只改三类文件

平台的「低代码」体现在——用户**只碰这三类文件**，其余全由 `scripts/cma/` 生成：

| 文件 | 作用 | 用户改什么 |
|---|---|---|
| `scripts/cma/cma.yaml` | **唯一编排清单** | agent 身份、`memory_stores`/`knowledge` 目录、`projects`、`workflows` |
| `agents/**/*.md` | 角色 system prompt（frontmatter + 正文） | 角色职责、护栏、用哪些 skill/memory |
| `scripts/cma/schemas/*.json` | reader 角色的 `output_schema`（防注入） | 结构化产物的字段约束 |

校验与构建：

```bash
python3 scripts/cma/check.py     # 校验所有引用（记忆/知识/项目/工作流）解析无误
python3 scripts/cma/build.py     # 干跑：按 项目×工作流 打印 agent + session 载荷
```

`build.py` 的产物对每个 **(project, workflow)** 打印：
- `# agent`：`POST /v1/agents` 载荷（每个 agent 建一次，跨项目复用）；
- `# session`：`POST /v1/sessions` 载荷，含**本项目**该挂的全部 memory+knowledge `resources[]`，
  其中 id 是 scope 占位符（`${MEMSTORE_…}` / `${FILE_…}`），平台部署时替换为真实 id。

---

## 8. 平台运行时：`scripts/cma/deploy.py`（已实现）

脚手架负责**声明**（`cma.yaml` + md），运行时负责**兑现**（调真实 API）。本仓库现已内置这层
运行时——`scripts/cma/deploy.py`，纯标准库（`urllib`，无 SDK 依赖），**默认干跑**（无需任何
凭证即可看到它要发的每个 API 调用），加 `--apply` 才真正调用。

### 8.1 它做的五件事

| 步骤 | API | 复用/新建规则 |
|---|---|---|
| ① 确保 agent 存在 | `POST /v1/agents` | 建一次，写入状态表，之后复用（含 version） |
| ② 确保 memory store 存在 | `POST /v1/memory_stores` | 按 `(scope,key,project?,session?)` 懒创建：`agent` 全局复用、`project` 按项目复用、`session` 每会话新建 |
| ③ 上传知识 | `POST /v1/files`（multipart）/ repo 直传 | `file` 上传得 `file_id` 并按 scope 缓存；`github_repository` 直接作为资源 |
| ④ 开会话 | `POST /v1/sessions` | 把该 (project, workflow) 的 session 载荷里的占位符替换成真实 id |
| ⑤ 启动会话 | `POST /v1/sessions/:id/events` | 发 `user.message` 开始任务 |

### 8.2 状态表（占位符 → 真实 id 的映射）

运行时把 `(scope, key, project?, session?) → 真实 id` 持久化到
`scripts/cma/.deploy-state.json`（已 gitignore）：

- `agent` 级 store：键 `memstore:<key>` —— 全局一份；
- `project` 级 store：键 `memstore:<key>:<project>` —— 每项目一份；
- `session` 级 store：**不写入状态表** —— 每次会话都新建（这正是「上下文/草稿仅本会话有效」的兑现）。

`deploy.py status` 打印这张表；`deploy.py reset` 清空（忘记所有 id，下次重新创建）。

### 8.3 用法

```bash
# 干跑（无需凭证）——打印它会发的每个调用
python3 scripts/cma/deploy.py agent                                   # 仅确保 agent
python3 scripts/cma/deploy.py session default deliver-feature "做一个 CSV 导入器"
python3 scripts/cma/deploy.py status                                  # 看 id 映射表
python3 scripts/cma/deploy.py reset                                   # 清空映射表

# 真跑（需要凭证）
export ANTHROPIC_API_KEY=sk-...           # API key
export ANTHROPIC_ENVIRONMENT_ID=env_...   # 一个 Managed Agents 环境（云沙箱）id
python3 scripts/cma/deploy.py session acme deliver-feature "..." --apply
# 也可用 PATH 上的封装：cma-deploy session acme deliver-feature --apply
```

> **占位符回解**：deploy.py 用与 build.py 完全相同的 `_slug` 规则，把 `${MEMSTORE_PROJECT_CONTEXT__ACME}`
> 反解回目录键 `project-context`，再按 scope 找/建真实 store——所以声明侧和兑现侧永远一致。

### 8.4 尚未自动化的部分（诚实边界）

- **Skills 上传**：agent 载荷里的 skill 以 `skill_ref` 引用；真跑前需先把 `skills/` 上传到你的
  workspace（与 financial-services 的部署流程一致）。deploy.py 会打印提醒，但不替你上传。
- **Dreams**：`deploy.py` 暂未内置 dream 触发（见 §5）；可用 Memory Stores / Dreams API 手动发起，
  或后续作为 `deploy.py dream <store> <session...>` 子命令补上。
- **环境（environment）创建**：`--apply` 需要你预先有一个 environment id（云或自托管沙箱）；
  本运行时只消费它，不创建它。

---

## 9. 架构设计、组件与 API 依赖

### 9.1 三层架构

```
┌──────────────────────────────────────────────────────────────────────────┐
│  ① 声明层（用户编辑）  Declarative — 用户只碰这里                            │
│     cma.yaml（agent / memory_stores / knowledge / projects / workflows）    │
│     agents/**/*.md（角色 system prompt）   schemas/*.json（output_schema）    │
│     knowledge/*.md（知识源文件）                                            │
└──────────────────────────────────────────────────────────────────────────┘
                │  build.py（派生）          │  check.py（校验）
                ▼                            ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  ② 编译层（脚手架自带，无副作用）  Derivation — 不调任何 API                  │
│     build.py  → 按 项目×工作流 产出 agent 载荷 + session 载荷（scope 占位符）  │
│     check.py  → 校验引用/作用域/工作流，CI 友好                              │
└──────────────────────────────────────────────────────────────────────────┘
                │  deploy.py（兑现，唯一调 API 的组件）
                ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  ③ 运行时层（脚手架自带，幂等）  Fulfilment — 调 Managed Agents API           │
│     deploy.py + .deploy-state.json（(scope,key,project,session)→真实 id）     │
└──────────────────────────────────────────────────────────────────────────┘
                │  HTTPS（urllib，beta: managed-agents-2026-04-01）
                ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  Claude Managed Agents 平台                                                 │
│     /v1/agents · /v1/memory_stores(/memories) · /v1/files · /v1/sessions    │
│     · /v1/sessions/:id/events · /v1/dreams（研究预览）                        │
│     environment（云沙箱 / 自托管沙箱）· vault（MCP 凭证）                      │
└──────────────────────────────────────────────────────────────────────────┘
```

设计原则：**②与③分离**。编译层永远无副作用（纯函数，CI 里随便跑）；只有 deploy.py 触网，且默认
干跑。声明侧与兑现侧共用 build.py 的派生逻辑与 `_slug` 规则，保证两者永不漂移。

### 9.1b 双部署目标（同一仓库，两处兑现）

①声明层与②编译层对**两个目标共用**；只有③兑现层分叉：

```
                        本 Agent Team 仓库（① 声明 + ② 编译）
                          cma.yaml · agents/ · skills/ · commands/
                                   │
                ┌──────────────────┴───────────────────┐
                ▼                                       ▼
   ③a CMA 目标（脚手架内置）                 ③b AgentX 目标（你的自托管平台）
   scripts/cma/deploy.py                     git-sync 服务（gh/git CLI 同步本仓库）
        │ HTTPS                                    │
        ▼                                          ▼
   Claude Managed Agents                     AgentX（agentx.nx.run, EKS + Bedrock AgentCore）
     /v1/agents · memory_stores               · Library: Documents/Knowledge/Skills
     · files · sessions · dreams              · Connectors（MCP/APP，AES-256-GCM 凭证）
     environment · vault                      · My Team: Specialists（独立记忆）
     记忆=memory store；RAG=文件系统           · Workflow Map 编排可视化
                                              · AgentCore Memory（Semantic/UserPreference/Summary）
                                              · Bedrock Knowledge Base + Neptune GraphRAG（真·向量RAG）
                                              · /agents 市场 + Scheduled 定时任务
```

- **CMA 目标**：零依赖、可独立跑（`deploy.py`，默认干跑）。记忆=memory store，RAG=文件系统检索。
- **AgentX 目标**：复用平台**既有的**文档/知识库/Skills/连接器/角色/记忆管理面板（§2.5）；记忆=
  AgentCore Memory，RAG=Bedrock Knowledge Base+GraphRAG。git-sync 把本仓库同步进 `/agents` 市场。
- **一份源码**：`skills/`/`agents/`/`commands/` 两个目标都吃；用户改 `cma.yaml`/md 一处生效两处。

### 9.2 组件清单

| 组件 | 文件 | 触网 | 职责 |
|---|---|---|---|
| 编排清单 | `scripts/cma/cma.yaml` | 否 | 唯一配置入口（用户编辑） |
| 编译器 | `scripts/cma/build.py` | 否 | md/yaml → agent + session 载荷（scope 占位符） |
| 校验器 | `scripts/cma/check.py` | 否 | 引用/作用域/工作流完整性校验 |
| 运行时 | `scripts/cma/deploy.py` | **是** | 兑现：建 agent/store/file/session、维护 id 映射表 |
| 状态表 | `scripts/cma/.deploy-state.json` | 否 | `(scope,key,project,session)→真实 id`（gitignore） |
| PATH 封装 | `bin/cma-check` · `bin/cma-deploy` | — | 让 agent 在 Bash 里直接调校验/部署 |

### 9.3 API 依赖一览（③a CMA 目标）

| 平台动作 | HTTP 端点 | 何时调用 | 必要 beta 头 |
|---|---|---|---|
| 创建/复用智能体 | `POST /v1/agents` | 首次部署该 agent | `managed-agents-2026-04-01` |
| 创建记忆库 | `POST /v1/memory_stores` | 某 scope 的库首次需要时 | 同上 |
| 预置/读写记忆 | `…/memory_stores/:id/memories`（create/update/list/retrieve/delete） | 预置语料、人工修正 | 同上 |
| 上传知识文件 | `POST /v1/files`（multipart） | `file` 型知识首次需要时 | 同上（Files API） |
| 开会话 | `POST /v1/sessions` | 用户在某项目新建会话 | 同上 |
| 启动/驱动会话 | `POST /v1/sessions/:id/events` | 发 `user.message` / 工具结果 | 同上 |
| 流式响应 | `GET /v1/sessions/:id/events/stream` | 观察 agent 输出（运行时可选） | 同上 |
| 记忆自整理 | `POST /v1/dreams`（+ 轮询/取消/归档） | 协调员发起 dream | `managed-agents-2026-04-01` + `dreaming-2026-04-21`（研究预览） |
| MCP 凭证 | `vault_ids`（会话创建参数）+ vault API | agent 用需鉴权的 MCP server 时 | `managed-agents-2026-04-01` |

CMA 外部依赖：①一个 **environment id**（云/自托管沙箱，预先创建）；②`ANTHROPIC_API_KEY`；③可选
**vault**（MCP OAuth 凭证）。`deploy.py` 只依赖 Python 3 标准库，不引入 anthropic SDK——便于嵌入任何后端。

### 9.3b 服务依赖一览（③b AgentX 目标）

部署到 AgentX 时，本仓库**消费平台既有的 ConnectRPC 服务**（不新增子系统）。相关服务（proto 包）：

| 平台能力 | AgentX 服务（proto 包） | 对应脚手架声明 |
|---|---|---|
| Skills 管理 + git 导入 | **SkillService**（`skill/v1`）、`skill_import_service.go`（git/sparse-checkout） | `skills/**/SKILL.md` |
| 知识库（向量/图 RAG） | **KnowledgeService**（`knowledge/v1beta`）→ Bedrock Knowledge Base + Neptune | `knowledge:`（语料型） |
| 文档 / 库统一管理 | **LibraryService**（`agentx/v1/library`） | `knowledge:`（`type: file`） |
| 连接器（MCP/APP）+ 凭证 | **ConnectorService**（`connector/v1`，AES-256-GCM） | `.mcp.json` / MCP server |
| 角色（人格层） | **SpecialistService**（`specialist/v1`） | `agents/specialists/**` |
| 编排 | **WorkflowService**（`workflow/v1`） | `agents/workflows/**` |
| 仓库同步 / 写回 | **GitSyncService**（`gitsync/v1`）：`ListOrgs/AddOrg/TriggerSync/PublishItem/AddRepository…` | 整个仓库 |
| 第三方 token 中枢 | **McpTokenService**（`mcptoken/v1`，`/mcp/token`） | 连接器凭证 |
| 长期记忆 | **AgentCore Memory**（Semantic/UserPreference/Summary） | `memory_stores:`（各 scope） |
| 定时执行 | **ScheduleService**（`schedule/v1`） | （会话级，平台特性） |

AgentX 外部依赖：AWS EKS + Bedrock AgentCore（Harness/Memory/Gateway）、Bedrock Knowledge Base、
Neptune、S3、DynamoDB、MongoDB、IRSA、OIDC（`account.nx.run`）。这些由平台提供，本仓库只需符合
git-sync 的约定（§2.5）即可被同步、展示、运行。

### 9.4 幂等与多租户

- **幂等**：状态表使 agent/project 级资源「建一次、复用」；重复 `deploy.py session` 不会重复建库。
- **多项目隔离**：`project` 级库的真实 id 按项目区分（状态键带项目名），项目间记忆互不可见。
- **多租户落地建议**：平台后端为每个租户/工作区维护各自的 `.deploy-state.json`（或换成数据库表），
  其余逻辑不变；deploy.py 的 `load_state/save_state` 是唯一需要替换的持久化点。

---

## 10. 设计不变量（务必保持）

1. **上下文是会话级的、临时的**；要持久必须写入某 scope 的 store。
2. **一份来源，多处兑现**：md/yaml 是唯一来源；agent 载荷与 session 载荷都由 `build.py` 派生，
   deploy.py 用同一套逻辑兑现——声明与兑现永不漂移。
3. **作用域是模式不是字段**：scope 决定「哪些会话共享同一个 store」。
4. **知识是文件系统检索**，不是向量库；语义检索走 MCP。
5. **编译无副作用，运行时才触网**：build.py/check.py 永不调 API；只有 deploy.py 触网且默认干跑。
6. **没有任何东西自动上线**：部署/推送/dream 采用都暂存待人工签核（deploy.py 默认 DRY-RUN）。
7. **一级委派**：子 agent 不再嵌套（CMA 硬限制）。

---

## 11. 相关文档

- [`platform-guide.zh.md`](platform-guide.zh.md) —— 面向使用者：如何 fork、配项目、配记忆/知识、开会话。
- [`memory-and-dreams.md`](memory-and-dreams.md) —— 官方原语逐字引用、JSON 形状、dreams/多智能体细节。
- [`agent-roster.md`](agent-roster.md) · [`coordination-rules.md`](coordination-rules.md) —— 角色与协作不变量。
- **AgentX 平台侧**（在 AgentX 仓库内）：`docs/AgentX-Platform-Overview.md`（平台总览、Specialists×
  Capabilities 两层模型、AgentCore Memory）、`docs/agent-teams-design.md`（一仓库=一 Plugin=一 Team、
  git-sync 约定、Library/Connectors/Specialists 服务）。本脚手架即该设计中的「Agent Team 仓库」。
