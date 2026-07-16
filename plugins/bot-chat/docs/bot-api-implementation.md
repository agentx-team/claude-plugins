# `bot` MCP API 实现文档

服务端点：`POST https://agentxapi.nx.run/bots.v1.BotService/McpServer`（**固定共享端点**，bot 身份不在 URL 中）

本 API 是一个 **MCP over HTTP（Streamable HTTP，JSON-RPC 2.0）** 服务。它在你的 3 个底层能力（建 room / 发消息 / 收消息）之上，额外维护一张**按 `session_id` 索引的绑定表**，从而让 Claude Code 插件用极少的调用完成"会话↔room"的绑定生命周期。

**设计原则：** bot 身份与连接级配置（`botId` / `targetUserId` / `requireMention`）**只**通过 **`X-Config` header** 传输（客户端从环境变量构造），**对 MCP 工具语义完全不可见**——`tools/list` 的任何 schema、description 中都不出现这些字段，也不出现 API key。body 只携带 `session_id` + 各工具自身参数。好处：插件装到任何环境后**无需修改任何 json 文件**，只需设 4 个环境变量，且 MCP 上下文占用最小。

---

## 0. 设计总览

```
Claude Code (插件)                     bot MCP 服务端                外部 IM 平台
─────────────────                     ──────────────                ───────────
/bot <name>  ──curl bot_bind──────►  建 room + 记 binding[sid]=room ──创建/邀请──► targetUser
Stop hook    ──curl bot_send──────►  查 binding[sid] → 发消息        ──发送──────► room
/bot status  ──curl bot_status───►  查 binding[sid]
/bot unbind  ──curl bot_unbind───►  删 binding[sid] + leave room     ──退出──────► room
(可选) 入站   ◄─bot_receive─────────  拉取 room 新消息（requireMention 过滤）
```

**关键点：绑定状态是服务端权威**（satisfies「可通过 api 查询绑定状态」）。插件本地只留一个轻量 `bound` 标记文件，用于让 Stop hook 在**未绑定时跳过网络调用**，避免每轮 curl。

---

## 1. 认证与配置

**配置只有一层：`X-Config` header 承载全部连接级配置，MCP 语义（schema/description/body）完全不感知。**

| 位置 | 字段 | 说明 |
|---|---|---|
| Header `Authorization` | `Bearer <API_KEY>` | 鉴权（API key 应能校验对 `botId` 的操作权限） |
| Header `X-Config` | JSON 字符串 | 连接级身份与配置，见下 |

`X-Config` 结构（客户端从环境变量构造）：
```json
{
  "botId": "bot_42",
  "targetUserId": "xxxxx",
  "requireMention": true
}
```

| X-Config 字段 | 环境变量 | 必填 | 说明 |
|---|---|---|---|
| `botId` | `BOT_ID` | ✅ | bot 身份，替代原 URL 路径中的 `{bot_id}` |
| `targetUserId` | `BOT_TARGET_USER_ID` | bind 时必填 | 建 room 时默认邀请/绑定的目标用户（room 的对端） |
| `requireMention` | `BOT_REQUIRE_MENTION` | 否，**默认 `true`** | 仅用于**入站** `bot_receive`。`true` 时群聊只返回"@ 到本 bot"的消息；单聊不受影响 |

**MCP 语义隔离（硬性要求）：**
- `tools/list` 返回的所有工具 schema 与 description 中，**不得出现** `targetUserId`、`requireMention`、`botId`、API key 等字样——这些概念只存在于 header 层。
- `tools/call` 的 `arguments` **不接受**这些字段；若出现，服务端应忽略（或返回错误），以 X-Config 为准。
- 服务端返回的 `structuredContent` 同样不回显 `targetUserId` 等配置内容。

**提示词零泄漏（客户端配套约定）：**
- header 内容（Authorization、X-Config）与全部 `BOT_*` 环境变量**不得出现在任何进入模型上下文的文本**中：MCP server 的 `instructions`、工具 schema、channel 通知 `content`/`meta`、`/bot` 命令的 stdout、structuredContent。
- **配置校验前置到 MCP 初始化阶段**：本地 `bot-channel` 启动时检查必需环境变量（`BOT_ID`、`BOT_API_KEY`），缺失则向 **stderr** 打印缺失项并以非零码退出——Claude Code 将其表现为 server 连接失败（`/mcp` 可见，详情在 `~/.claude/debug/<session-id>.txt`），**不占用任何上下文**。
- 运行期错误同理：详情走 stderr/日志，进入上下文的只允许 generic 原因码（如 `not_configured`、`network`）。

服务端要求：
- 每请求解析 `X-Config`；校验 `Authorization` 与 `botId` 的匹配关系（防止 key A 操作 bot B）。
- `bot_bind` 时 X-Config 缺 `targetUserId` 返回错误；`requireMention` 缺省按 `true` 处理。
- 绑定表建议以 `(botId, session_id)` 复合键索引，避免不同 bot 间 session 冲突。

---

## 2. MCP 协议表面

标准 MCP，三个方法即可：

### 2.1 `initialize`
返回 server 能力。本服务只需 `tools`。
```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"bot-chat-plugin","version":"1.0.0"}}}
```

### 2.2 `tools/list`
返回下方所有工具的 schema。

### 2.3 `tools/call`
```json
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"<tool>","arguments":{...}}}
```
统一响应格式：
```json
{"jsonrpc":"2.0","id":2,"result":{
  "content":[{"type":"text","text":"<人类可读结果>"}],
  "structuredContent":{...},        // 机器可解析结果，插件脚本读这里
  "isError": false
}}
```

> 插件脚本用 `curl` 直接发 `tools/call`（不经过 Claude），因此 **`structuredContent` 必须是稳定 JSON**，供 `jq` 解析。

---

## 3. 工具清单

分两层：**会话编排层**（插件实际调用）和**底层能力层**（你已具备的 3 个原子能力，供编排层内部组合，也可单独暴露）。

### 3.1 会话编排层（插件调用这些）

#### `bot_bind` — 创建 room 并绑定当前会话
| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `session_id` | string | ✅ | Claude Code 会话 ID |
| `room_name` | string | ✅ | room 名称 |

（room 对端用户取 X-Config.targetUserId，schema 不感知。）

**服务端逻辑（务必实现"先解绑再绑定"）：**
1. 若 `binding[session_id]` 已存在 → 先对旧 room 执行 `leave_room(old_room_id)`，删除旧绑定。
2. `create_room(name=room_name, targetUserId=X-Config.targetUserId)` → 得 `room_id`。
3. 记 `binding[session_id] = { room_id, room_name, target_user_id, created_at }`（`target_user_id` 仅服务端内部记录，不回显）。
4. 返回。

```json
// 请求 arguments
{"session_id":"abc123","room_name":"my-task"}
// structuredContent
{"ok":true,"room_name":"my-task","rebound":true}
```
`rebound` 在发生自动解绑时为 `true`，否则为 `false`。**响应不暴露 `room_id`**——session↔room 映射由服务端维护，客户端只以 `session_id` 为句柄。

#### `bot_unbind` — 解绑并离开 room
| 参数 | 类型 | 说明 |
|---|---|---|
| `session_id` | string | 会话 ID |

逻辑：查 `binding[session_id]` → `leave_room(room_id)` → 删绑定。未绑定时幂等返回 `ok:true, was_bound:false`。
```json
{"ok":true,"was_bound":true}
```

#### `bot_status` — 查询绑定状态
| 参数 | 类型 | 说明 |
|---|---|---|
| `session_id` | string | 会话 ID |
```json
{"bound":true,"room_name":"my-task"}
// 或
{"bound":false}
```

#### `bot_send` — 向绑定 room 发消息（Stop hook 用）
| 参数 | 类型 | 说明 |
|---|---|---|
| `session_id` | string | 会话 ID |
| `text` | string | 消息正文 |

逻辑：查 `binding[session_id]`；未绑定 → 返回 `ok:false, reason:"not_bound"`（**不报错**，方便 hook 静默跳过）；已绑定 → `send_message(binding.room_id, text)`（room_id 取自服务端绑定表）。
```json
{"ok":true,"message_id":"m_001"}
```

#### `bot_receive` —（可选，入站）拉取 room 新消息
| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `session_id` | string | ✅ | 会话 ID |
| `since` | string | ❌ | 游标/时间戳，只取此后消息 |

（@提及过滤取 X-Config.requireMention，schema 不感知。）

逻辑：查绑定 → 拉 room 消息 → 若 X-Config.requireMention 且为群聊，仅保留 @ 本 bot 的消息 → 返回。
```json
{"messages":[{"id":"m_010","from":"user_1","text":"进度如何","ts":"..."}],"next_since":"..."}
```
> 本插件的 3 个必需功能**不使用**入站；`bot_receive` 仅为未来"双向对话"预留。真要做双向，见 §6。

### 3.2 底层能力层（你已有的 3 个原子能力）

供编排层**内部**调用。`room_id` 只存在于这一层与绑定表中，**不出现在任何编排层工具的请求/响应里**——对外唯一句柄是 `session_id`：

| 工具 | 参数 | 对应你的能力 |
|---|---|---|
| `create_room` | `name`, `target_user_id` | ① 创建 chat room |
| `send_message` | `room_id`, `text` | ② 向指定 room 发消息 |
| `receive_message` | `room_id`, `since?`, `requireMention?` | ③ 接收指定 room 消息 |
| `leave_room` | `room_id` | 退出 room（`bot_unbind`/重绑需要） |

> `leave_room` 是原能力的补充：解绑要求"Leave room"，请确保服务端具备。

---

## 4. 绑定表存储要求

- **键**：`session_id`（Claude Code 每个会话唯一）。
- **值**：`{ room_id, room_name, target_user_id, created_at }`。
- **一致性**：`bot_bind` 必须"先解绑旧的再绑新的"（**同一 `session_id`** 只允许一个 room）。
- **持久化**：建议存 Redis/DB，TTL 可选（如 7 天无活动自动清理并 leave room，防泄漏 room）。
- **并发**：同一 `session_id` 的 bind/unbind 应串行化（加锁），避免竞态导致悬挂 room。

> **投递会话并发（多房间接收）**：默认实现里，每个 `botId` 全局只允许一个
> `accept_delivery:true` 的活跃投递会话，新的投递 bind 会**接管**并解绑旧的
> （bot-chat 单会话使用无碍）。若要支持**同一 bot 下多房间同时接收**（acp-chat
> 的多会话编排场景），需把"先解绑旧的"的范围**限定在同一 `session_id` 内**，
> 而**不**跨 `session_id` 接管——即绑定表以 **`(botId, session_id)` 复合键**索引，
> `bot_receive` 按 `session_id` 隔离投递。详见
> `plugins/acp-chat/docs/multi-room-delivery.md`。

---

## 5. 错误约定

| 场景 | 返回 |
|---|---|
| 缺 `targetUserId` | `isError:true`, text 说明 |
| `bot_send` 未绑定 | **非错误**：`structuredContent:{ok:false,reason:"not_bound"}`，`isError:false` |
| room 已被外部删除 | `bot_send` 返回 `ok:false,reason:"room_gone"`；服务端顺手清理绑定 |
| 鉴权失败 | HTTP 401 |

> `bot_send` 未绑定/room 失效**不要**用 `isError`，否则 Stop hook 每轮报错刷屏。

---

## 6.（可选）双向对话扩展

若日后要让 room 里的人把消息推进 Claude 会话，本 API 需再实现 **Channel**（研究预览）语义：把 bot 注册进 `.mcp.json` 并声明 `experimental["claude/channel"]`，用 `notifications/claude/channel` 推入站、用 reply 工具回消息（参见 Claude Code channels-reference）。这会让工具 schema 常驻上下文、增加 token，故与本插件"纯出站省 token"目标冲突，**默认不启用**。

---

## 7. 服务端实现清单（TL;DR）

- [ ] MCP HTTP：`initialize` / `tools/list` / `tools/call`
- [ ] 解析 `Authorization` + `X-Config`（`targetUserId`,`requireMention`）
- [ ] 绑定表（键 `session_id`），bind 时先解绑+leave 旧 room
- [ ] `bot_bind` / `bot_unbind` / `bot_status` / `bot_send`（+可选 `bot_receive`）
- [ ] 底层 `create_room` / `send_message` / `leave_room` / `receive_message`
- [ ] `bot_send` 未绑定/room 失效返回非错误结果
- [ ] `structuredContent` 稳定 JSON，供 `jq` 解析
