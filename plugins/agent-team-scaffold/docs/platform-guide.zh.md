# Agent 低代码托管平台 — 使用文档

> 面向使用者。你只需 **fork 模板 + 改 yaml/md/json**，就能定制一个智能体团队、开多个项目、
> 每个项目开多个会话——**不接触任何底层 API**。
> 概念与架构见 [`platform-design.zh.md`](platform-design.zh.md)。

---

## 0. 先记住一句话

> **上下文（Context）只活在单个会话里，会话一结束就没了。**
> 想让智能体「长期记住」某件事，就把它放进某个**作用域（scope）的记忆库**：
> `agent`（全智能体共享）、`project`（按项目隔离）、`session`（仅本次会话）。

四层关系：**Agent（你 fork 的） → 多个 Project → 每个 Project 多个 Session → 每个 Session 一份临时 Context。**

### 这个仓库可以部署到两个地方

**一个仓库 = 一个 Claude Plugin = 一个 Agent Team**，两个部署目标，改一处 `cma.yaml`/md 两处生效：

| 目标 | 怎么上线 | 记忆 | 知识/RAG |
|---|---|---|---|
| **CMA**（Anthropic 托管，零依赖可独立跑） | `python3 scripts/cma/deploy.py …`（见 §8） | memory store | 文件系统检索（grep/read） |
| **AgentX**（你的自托管平台 `agentx.nx.run`） | 由平台 **git-sync** 同步本仓库（你不用跑命令） | AgentCore Memory（每 Specialist 独立） | **真·向量+图 RAG**（Bedrock KB + Neptune） |

> 部署到 AgentX 时，你**复用平台已有的管理面板**——文档/知识库/Skills 在 **Library**、连接器在
> **Connectors**、角色在 **My Team**、记忆是 **AgentCore Memory**。本仓库只是它们的「输入物」。
> 详见设计文档 §0 与 §2.5。

---

## 1. 创建你的智能体（fork 模板）

1. **Fork** `agent-team-scaffold` 仓库（或在平台点「基于模板创建」）。
2. 打开 `scripts/cma/cma.yaml`，改 `agent:` 块给智能体起名：

   ```yaml
   agent:
     name: my-research-team           # 英文 slug，作命名空间
     display_name: "我的调研团队"
     description: "围绕 规划→生成→评审 闭环的调研智能体团队。"
     memory:
       - team-standards               # 智能体级记忆（所有项目共享，见第 4 节）
     knowledge:
       - house-style                  # 智能体级知识（所有项目共享，见第 5 节）
   ```

3. 校验：

   ```bash
   python3 scripts/cma/check.py
   ```

到此你就有了一个「智能体」。它本身不跑任务——任务发生在**项目下的会话**里。

---

## 2. 开多个项目（Project）

一个智能体下可开多个项目，**彼此隔离**：项目 A 的记忆/知识，项目 B 看不到。
在 `cma.yaml` 的 `projects:` 下，**复制一个块、改 key** 就新开一个项目：

```yaml
projects:
  acme:                              # ← 项目 key（英文 slug）
    display_name: "ACME 客户"
    description: "给 ACME 做的调研。"
    memory:
      - project-context              # 项目级记忆（本项目独有一份）
    knowledge:
      - product-docs                 # 项目级知识（本项目独有）
    workflows:
      - deliver-feature              # 本项目可运行的工作流

  globex:                            # ← 再开一个项目，配置互不影响
    display_name: "Globex 客户"
    memory:
      - project-context
    workflows:
      - deliver-feature
```

> 同一个 `project-context` 库声明被两个项目引用，但因为它的 `scope: project`，平台会为
> **每个项目各建一份**（`${MEMSTORE_PROJECT_CONTEXT__ACME}` vs `__GLOBEX}`），互不可见。
> 删掉一个项目块即下线该项目。

---

## 3. 开多个会话（Session）/ 理解上下文

**会话 = 一次具体任务**（独立沙箱 + 对话线程）。在平台里「进入某项目 → 新建会话 → 发一句话」
即开始。一个项目可同时有多个会话，互不干扰。

关于**上下文**，记住三条：

- 上下文 = 本会话的对话历史 + 沙箱文件，**只对这一个会话有效**。
- 会话结束，上下文消失；**下次新会话从零开始**——除非信息已写入某个 store。
- 所以：临时草稿放 `session` 级库；要跨会话/跨项目沉淀的，放 `project` 或 `agent` 级库。

> 你不需要手写任何会话创建 API。平台按你选的「项目 + 工作流」自动组装会话载荷（把该项目该挂的
> 记忆/知识都挂上）。想预览它会挂什么，跑 `python3 scripts/cma/build.py`（见第 7 节）。

---

## 4. 配置记忆（Memory）

记忆库在 `cma.yaml` 的 `memory_stores:` 目录里声明一次，然后被 agent/project/工作流按 key 引用。
**`scope` 决定共享范围**：

```yaml
memory_stores:
  team-standards:        # 全智能体共享、只读 —— 团队规范
    scope: agent
    access: read_only
    description: "全组织通用规范、完成定义。"
    instructions: "视为权威规范。规划/评审前先读；切勿写入。"

  project-context:       # 按项目隔离、可写 —— 项目长期记忆
    scope: project
    access: read_write
    description: "本项目的决策、术语、历次结论。"
    instructions: "项目长期记忆。记录持久决策；开工前先查。"

  evaluator-calibration: # 全智能体共享、可写 —— 某角色的私有记忆
    scope: agent
    access: read_write
    description: "评审者的校准记忆：反复出现的失败模式。"
    instructions: "你的私有校准记忆。把反复漏掉的模式追加进来。"

  session-scratch:       # 每会话新建、可写 —— 临时草稿
    scope: session
    access: read_write
    description: "单会话临时草稿。会话结束即弃。"
    instructions: "本会话临时草稿区；不要当长期记忆。"
```

引用方式（在哪挂，就在哪写）：

| 想要的效果 | 写在哪 |
|---|---|
| 所有项目所有会话都能用 | `agent.memory:` 里列该库（scope=agent） |
| 仅某项目的会话能用、且每项目独立 | 该 `projects.<key>.memory:` 里列（scope=project） |
| 某个角色私有 | 该工作流 leaf 的 `memory: [..]`（库 scope=agent 则跨项目沉淀） |
| 仅本次会话临时 | 工作流 `session_memory:`（库 scope=session） |

> 选 `scope` 的口诀：**问「这条记忆应该被哪些会话看到？」**
> 全部→`agent`；同项目→`project`；仅这次→`session`。

---

## 5. 配置知识 / RAG（Knowledge）

> 重要：Managed Agents **没有向量检索**。知识 = 挂进沙箱的**文档**，智能体用 `grep`/`read` 查。
> 需要语义检索时，把你的向量库做成 **MCP server**（在 `.mcp.json` 声明）。

在 `cma.yaml` 的 `knowledge:` 目录声明知识来源：

```yaml
knowledge:
  house-style:                  # 智能体级：单个文件
    scope: agent
    type: file
    path: knowledge/house-style.md          # 仓库里的源文件（你直接编辑它）
    mount: /workspace/knowledge/house-style.md
    access: read_only
    description: "写作/工程规范。"

  product-docs:                 # 项目级：整个仓库作为语料
    scope: project
    type: github_repository
    repo: your-org/product-docs             # 换成你的文档仓库
    mount: /workspace/knowledge/product-docs
    access: read_only
    description: "本项目领域文档，用 grep/read 检索。"
```

- `type: file` → 你把文档放进仓库 `knowledge/` 下，平台部署时上传得到 `file_id` 并挂载。
- `type: github_repository` → 平台把整个仓库挂进沙箱，智能体像读代码一样 grep/read。
- 用 `scope` 控制是「全智能体共享知识」还是「按项目各挂各的」。
- 知识是**只读参考**，请保持 `access: read_only`。

智能体侧无需配置——挂载点会自动出现在系统提示里；规划员/生成员会去 `grep` 它而不是凭空猜。

---

## 6. （可选）记忆自整理：Dreams

记忆写久了会重复/过时。**Dream** 让智能体读「一个记忆库 + 一批历史会话」，产出一个**整理过的
新库**（原库不动，审阅后再采用）。平台把它做成**协调员的运维动作**，你只需：

1. 选一个项目（如 `acme`）跑过若干会话后，发起对其 `project-context` 的 dream；
2. 平台异步整理，产出新库供你**审阅**；
3. 满意就「采用」——平台把该项目记忆指向新库，旧库归档；不满意就丢弃。

> Dreams 是**研究预览**功能，需平台开通；未开通时也可手动修剪记忆。详见
> [`memory-and-dreams.md`](memory-and-dreams.md)。

---

## 7. 校验与预览（部署前）

```bash
# 1) 校验：所有记忆/知识/项目/工作流引用都解析无误
python3 scripts/cma/check.py

# 2) 预览：按 项目 × 工作流 打印 agent 载荷 + 会话载荷（含将挂载的记忆/知识）
python3 scripts/cma/build.py

# 只看某个工作流
python3 scripts/cma/build.py deliver-feature

# 切换模型档位（也对应插件 userConfig.default_model）
CMA_MODEL=opus python3 scripts/cma/build.py
```

`build.py` 会对每个项目打印类似：

```
########## PROJECT: acme  (ACME 客户) ##########
===== workflow: deliver-feature  (project=acme, …, resources=[
   ${MEMSTORE_TEAM_STANDARDS},               ← agent 级，跨项目共享
   ${MEMSTORE_PROJECT_CONTEXT__ACME},        ← project 级，本项目独有
   ${MEMSTORE_SESSION_SCRATCH__SESSION},     ← session 级，每会话新建
   ${FILE_HOUSE_STYLE}, your-org/product-docs ← 知识（文件 + 仓库）
]) =====
```

那些 `${…}` 占位符就是「作用域」的体现：带 `__ACME` 的按项目隔离，带 `__SESSION` 的每会话新建。
部署时由运行时替换成真实 id——**你不需要关心**（见下一节）。

---

## 8. 部署上线（deploy.py 运行时）

校验/预览之后，用内置运行时 `scripts/cma/deploy.py` 把声明**兑现**成真实的 Managed Agents 资源。
它**默认干跑**（无需任何凭证，先看它要发哪些 API 调用），加 `--apply` 才真正调用。

```bash
# 干跑：看它会创建/复用哪些 agent、记忆库、知识文件，并如何开会话
python3 scripts/cma/deploy.py agent                                  # 仅确保 agent 存在
python3 scripts/cma/deploy.py session acme deliver-feature "做一个 CSV 导入器"
python3 scripts/cma/deploy.py status                                 # 查看 id 映射表
python3 scripts/cma/deploy.py reset                                  # 清空映射（重新创建）

# 真跑：需要两个环境变量
export ANTHROPIC_API_KEY=sk-...           # 你的 API key
export ANTHROPIC_ENVIRONMENT_ID=env_...   # 一个 Managed Agents 环境（云沙箱）id
python3 scripts/cma/deploy.py session acme deliver-feature "..." --apply
# 插件启用时也可直接用 PATH 上的封装：cma-deploy session acme deliver-feature --apply
```

运行时帮你做的事（你都不用关心）：

1. **建一次 agent，之后复用**（记在 `scripts/cma/.deploy-state.json`）。
2. **按作用域建/复用记忆库**：`agent` 级全局一份、`project` 级每项目一份、`session` 级每会话新建。
3. **上传知识文件**得 `file_id`（`github_repository` 直接挂）。
4. **开会话**并把占位符替换成真实 id；给了消息就发 `user.message` 启动。

> 两个边界（诚实说明）：① 真跑前需先把 `skills/` 上传到你的 workspace（deploy.py 会提醒）；
> ② 需要你预先有一个 environment id（云或自托管沙箱），运行时只消费它、不创建它。
> 架构与完整 API 依赖见 [`platform-design.zh.md`](platform-design.zh.md) §8–§9。

### 部署到 AgentX（你的自托管平台）

如果上线到 AgentX，**你不用跑上面的命令**——由平台的 **git-sync** 服务同步本仓库即可：

1. 在 AgentX **`/settings/connectors`** 配置 GitHub 连接器，设「默认组织（Default Organization）」
   （如 `agentx-team`）。
2. 把本仓库作为一个 **`agents` 类条目**纳入同步：要么作为约定仓库 `{org}/agents/<子目录>`，要么
   作为带 **topic `agents`** 的独立仓库（如 `agentx-team/my-team`）；也可在「Repository 源」里直接
   贴本仓库 git 地址并选 kind=agent。
3. 同步后，本仓库出现在 **`/agents` 市场**，其 `skills/` 进 **Library → Skills**、`knowledge:` 进
   **Library → Knowledge/Documents**、角色进 **My Team → Specialists**。
4. 在某项目里开会话即运行——记忆走 **AgentCore Memory**，知识走 **Bedrock 向量/图 RAG**。

> 你在 AgentX UI 里新建/编辑的内容会**写回** custom org 的约定仓库（git-sync 双向）。official org
> （服务配置里的，如 `aws300`）只读。详见 AgentX `docs/agent-teams-design.md` 第 4 节。

---

## 9. 自定义角色与工作流

- **改角色**：编辑 `agents/specialists/**/*.md`（frontmatter + 正文）。frontmatter 里可写
  `skills:`（用哪些方法）；在 `cma.yaml` 的 leaf 上写 `memory:` 给该角色私有记忆。
- **改工作流**：复制 `agents/workflows/deliver-feature.md` 改名，在 `cma.yaml` 的 `workflows:`
  加一个同名块，再在某个项目的 `workflows:` 里引用它。
- **领域化**：把规划员/生成员/评审员的提示词替换成你的行业语言；保持「生成者≠评审者」不变量。

---

## 10. 常见问题

**Q：为什么智能体「忘了」我上次说的话？**
A：那些话只在上一个**会话的上下文**里。把要长期记住的写进 `project` 或 `agent` 级记忆库。

**Q：项目 A 的记忆会泄漏到项目 B 吗？**
A：不会。`scope: project` 的库平台按项目各建一份（占位符带 `__<PROJECT>` 后缀），互不可见。
   只有 `scope: agent` 的库才跨项目共享。

**Q：我有几千份文档，想做 RAG？**
A：看部署目标。**部署到 AgentX**：直接用平台的 **Library → Knowledge**（KnowledgeService →
   Bedrock Knowledge Base + Neptune GraphRAG），这是**真·向量+图检索**，几千份文档没问题，
   `knowledge:` 里 scope=`project` 的语料会落进该项目的知识库。**部署到 CMA**：少量文档直接当
   `knowledge`（grep 足够）；要语义检索就把向量库做成 MCP server。详见设计文档 §4 的对比表。

**Q：文档/知识库/Skills/连接器在哪管理？**
A：部署到 AgentX 时**复用平台既有面板**——文档/知识库/Skills 在 **Library**、MCP/APP 连接器在
   **`/settings/connectors`**、角色在 **My Team**。本仓库里的 `skills/` / `knowledge:` /
   `agents/specialists/` 经 git-sync 自动出现在这些面板里（映射见设计文档 §2.5）。

**Q：我能给某个子 agent 完全独立的上下文和私有记忆吗？**
A：能。给它独立的 agent 定义（独立 model/tools/MCP）→ 独立上下文；再用 `scope: agent` 的
   私有库只在该角色挂载 → 私有记忆。详见设计文档第 6 节。

**Q：会不会有什么被自动部署/推送？**
A：不会。所有外部动作（部署、推送、dream 采用）都暂存待你人工签核。

---

## 11. 下一步

- 跑通示例：`python3 scripts/cma/build.py` 看 `default` 项目的会话载荷。
- 复制 `default` 项目块开你自己的项目；复制 `deliver-feature` 工作流做你的交付物。
- 深入原理：读 [`platform-design.zh.md`](platform-design.zh.md) 与 [`memory-and-dreams.md`](memory-and-dreams.md)。
