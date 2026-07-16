# acp-chat 多房间接收：服务端约束与改造说明

本文档记录 acp-chat 依赖的一个 **bot MCP 服务端行为**，以及当前服务端的一条限制
如何与 acp-chat 的多房间模型冲突、需要如何改造。

面向读者：**修改 bot MCP 服务端的人**。acp-chat 客户端侧无需改动（契约已满足，见 §3）。

---

## 1. 现象

在控制房间输入 `/new /some/path roomB` 创建第二个房间后，**原来的控制房间**收到
服务端推送的系统通知：

```
Another session took over this bot; this room no longer receives messages.
```

之后控制房间 `bot_status` 变为 `not_bound`，`bot_send` / `bot_receive` 全部返回
`{ok:false, reason:"not_bound"}`——即该房间被服务端**解绑**了。

这条文案由**服务端**产生（本地任何插件代码中都不存在此字符串），但**触发它的是
acp-chat 的 `/new`**：新房间以 `accept_delivery:true` 绑定，抢占了投递权。

---

## 2. 根因：当前服务端「单 bot 单投递会话」限制

经实测（同一 `botId`、两个不同 `session_id`、均 `accept_delivery:true`）：

| 步骤 | 结果 |
|---|---|
| A 绑定 `{room_name:"A", accept_delivery:true}` | `ok:true`，A 可 send/receive |
| B 绑定 `{room_name:"B", accept_delivery:true}` | `ok:true` |
| 此时查 A | **`{bound:false}`** —— A 的绑定被删除 |
| A `bot_send` / `bot_receive` | `{ok:false, reason:"not_bound"}` |
| B `bot_send` / `bot_receive` | 正常 |

结论：**当前服务端全局只允许每个 `botId` 有一个 `accept_delivery:true` 的活跃投递
会话**；新的投递绑定会**接管**（takeover）并解绑旧的。bot-chat README 亦记载此
行为：

> Only **one** delivery session may be live per bot at a time; binding a new
> session with the same bot id takes over (the previous session's room stops
> receiving).

这对 bot-chat 无害——它同一时刻只需要一个 session 的房间接收。但 acp-chat 的目标是
**多个房间（多个 ACP 会话）同时收发**，正好撞上这条限制。

---

## 3. acp-chat 客户端契约（服务端可依赖，无需客户端改动）

acp-chat 已保证：**每个房间是一个完全独立的三元组**，绝不复用。

| 维度 | 取值 | 代码位置 | 唯一性 |
|---|---|---|---|
| MCP `session_id` | `acp-<uuidv4>`（称 `botSid`） | `store.mjs` `create()` | **每房间唯一**，创建时 `randomUUID()` 生成 |
| 工作目录 `cwd` | `/new` 解析出的绝对路径 | `daemon.mjs` `_createRoom` | 每房间独立记录（可不同、也允许相同路径不同房间） |
| ACP session id | `sess_<uuid>`（kiro `session/new` 返回） | `store.mjs` `setAcpSession()` | **每房间唯一** |

- 所有 bot 调用（`bot_bind`/`bot_send`/`bot_receive`/`bot_status`/`bot_unbind`）
  的 `session_id` 参数**一律传该房间的 `botSid`**（`bot-client.mjs`）。
- 三元组持久化于 `state/rooms.json`，重启后按 `botSid` 恢复（`session/load` 重连
  ACP 会话、按同一 `botSid` 复用 bot 绑定）。

> 因此服务端**只需按 `session_id` 隔离投递**即可区分房间——`session_id` 已经是
> 每房间唯一的稳定句柄，acp-chat 不会用两个房间共享一个 `session_id`。

---

## 4. 服务端需要的改造

**目标**：同一 `botId` 下，**多个 `accept_delivery:true` 的绑定可并存**，各自按
`session_id` 独立投递，互不接管。

> ✅ **已在 AgentX control-plane 落实**（`internal/imbot/mcp_bindings.go` `McpBind`
> 删除了 `DeleteDeliveryBindingsExcept` 接管块；`internal/imbot/mcp_repo.go` 同步
> 删除该方法）。以下勾选项均已满足：

- [x] **取消「单 bot 单投递」的全局互斥**。`bot_bind {accept_delivery:true}` 时，
      **不再**解绑该 bot 下其它 `session_id` 的投递绑定。
- [x] 绑定表键为 **`(botId, session_id)` 复合键**（`bot_mcp_bindings` 上的唯一索引
      `bot_id,session_id`）。
- [x] `bot_receive {session_id}` 仅返回**该 session_id 所绑房间**的消息；不同
      `session_id` 的 receive 完全隔离（每 session 一条队列）。
- [x] `bot_send {session_id}` 发往该 `session_id` 绑定的房间。
- [x] **保留** `bot_bind` 对**同一 `session_id`**的「先解绑旧 room 再绑新 room」
      语义（同一房间重绑仍是替换，不是新增，靠复合键 upsert 实现）——只解除**跨
      `session_id`**的接管。
- [x] 入站路由：一个房间有活跃 MCP 投递会话（`accept_delivery:true`）→ 消息进
      该 `session_id` 的 `bot_receive` 队列；无投递会话的房间（share/AgentX 绑定）
      → 仍走 AgentX agent（`mcpHandleInbound` 按 `session_id != ""` 过滤）。

**回归保护**：改造后请验证 §2 的实验——A、B 两个 `accept_delivery:true` 绑定并存
时，A 在 B 绑定后应**仍为 `bound`**，且 A/B 的 receive 各收各的、互不串扰。

---

## 5. 兼容性说明

- **bot-chat 不受影响**：它同一时刻只有一个投递 session，放宽互斥后行为不变
  （单个投递会话依然正常接管/被接管由它自己的 rebind 决定）。
- **share room 模式不受影响**：`accept_delivery:false` 的共享房间本就不占投递会话，
  入站仍路由到 AgentX agent。
- **鉴权不变**：仍按 `Authorization` + `X-Config.botId` 校验；本改造只影响投递
  绑定的并发数，不涉及鉴权。

---

## 6. 现状（改造前）与 acp-chat 的临时表现

在服务端改造**之前**，acp-chat 每次 `/new` 会抢占投递权，导致：
- 只有**最后一个** `/new` 出来的房间能接收；此前的房间（含控制房间）被解绑。
- outbound（`bot_send`）不受影响——任意房间只要其 `botSid` 仍绑定就能发；但被接管
  的房间 `botSid` 已被服务端删除，故 send 也会 `not_bound`。

改造完成后，多房间可同时接收，acp-chat 无需任何改动即可正常工作。
