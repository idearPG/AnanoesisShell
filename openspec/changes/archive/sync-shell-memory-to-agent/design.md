## Context

当前架构中，`PtyCommandScheduler` 已经能通过 Shell 集成帧协议（CMD_START/CMD_END/PROMPT/CWD）区分人工命令与 Agent 命令，并维护 `sessionCwd`。`ConversationService.saveShellEventMessage()` 已就绪但从未被生产代码调用。`AiAgentService.runTurn()` 构建系统提示时只注入 `sessionCwd`，不注入最近命令列表或嵌套环境状态。

`PtyCommandScheduler` 的嵌套 Shell 探测机制（`nestedState`）已在 `fix-agent-container-and-scroll` 变更中实现，能检测用户是否进入了嵌套 bash（如 Docker 容器），但探测结果仅用于内部集成重安装，不对外暴露。

## Goals / Non-Goals

**Goals:**
- 人工命令完成后自动持久化到对话历史，无需用户额外操作
- Agent 系统提示包含最近 Shell 活动摘要 + 嵌套环境状态
- 不改变前端行为（纯后端变更）
- JaCoCo 分支覆盖率阈值提升至 0.75

**Non-Goals:**
- 不做命令智能摘要/NLP 总结（只截断输出，不做语义压缩）
- 不做跨 tab 命令共享（每个 tab 的命令只写入自己的对话历史）
- 不做命令过滤/去重（用户要求全部记录）
- 不解析容器名/ID（只告知"在嵌套 Shell 中"，不尝试提取具体容器信息）

## Decisions

### D1: 人工命令持久化触发点——PtyCommandScheduler 回调

**选择**：在 `PtyCommandScheduler` 中增加人工命令完成回调（`onManualCommandComplete`），当 CMD_END + PROMPT 序列完成一条人工命令时触发。回调由上层（`SshTerminalService` 或 `SessionRuntime` 的装配层）注入，负责调用 `ConversationService.saveShellEventMessage()`。

**替代方案**：
- 在 `ShellIntegrationInstaller` 的输出链包装中拦截——过于底层，输出链只看到原始字节流，无法界定命令边界
- 在前端 WebSocket handler 中记录——前端没有命令退出码和完整输出的结构化数据

**理由**：`PtyCommandScheduler` 是唯一同时拥有命令原文、退出码、输出和 CWD 的组件，且已经区分 MANUAL 和 AGENT 状态。回调模式保持了与现有 `nestedShellCallback` 一致的设计模式。

### D2: 最近 Shell 活动查询——CommandExecution 表查询

**选择**：通过 `CommandExecutionMapper` 查询 `source='manual'` 的最近 N 条记录（按 `created_at DESC LIMIT 10`），提取命令原文和退出码，注入系统提示。

**替代方案**：
- 从 `ai_messages` 表查 `source='shell_event'`——也可以，但这些记录是"对话历史"语义，查询需要关联 `conversation_id`；而 `command_executions` 直接按 `session_id` 查询更直接
- 在 `PtyCommandScheduler` 内存中维护最近命令列表——进程重启丢失，且与持久化重复

**理由**：`command_executions` 表已有 `source`、`command`、`exit_code`、`session_id` 字段，查询简单且持久。

### D3: 输出摘要截断策略

**选择**：写入 `saveShellEventMessage()` 的内容格式为 `命令原文\nexit=<退出码>\n<输出前 500 字符>`。超过 500 字符的输出截断并追加 `...（已截断）`。完整输出已在 `command_executions.stdout` 中保存。

**理由**：500 字符足够展示命令的关键输出（如 `ls` 前几行、`docker ps` 表头），同时避免单条记录占用过多上下文预算。

### D4: 嵌套环境状态暴露——PtyCommandGateway 暴露查询

**选择**：在 `PtyCommandGateway` 上增加 `isNestedShell(sessionId)` 方法，委托给对应 `PtyCommandScheduler` 的 `nestedState` 查询。`AiAgentService` 在构建系统提示时调用此方法。

**替代方案**：
- 通过事件推送（回调 + 状态缓存）——过度设计，系统提示构建是同步的拉取模式
- 在 `SessionRuntime` 上暴露——`SessionRuntime` 不直接感知调度器的嵌套状态

**理由**：与 `sessionCwdOf()` 的设计模式完全一致（`AgentTools.sessionCwdOf()` → `PtyCommandGateway.findScheduler()` → `scheduler.sessionCwd()`），复用现有查找链。

### D5: conversationId 获取路径

**选择**：人工命令持久化需要 `conversationId`。当前 tab 的 workspace 在前端持有 `sessionId` 和 `conversationId`，但后端需要一种方式从 `sessionId` 找到对应的 `conversationId`。查询路径：`command_executions` 表已有 `conversation_id` 列；`SshTerminalService` 在创建会话时可接受 `conversationId` 参数（前端在建连时已知道 tab 对应的 conversation）。

**降级**：若 `conversationId` 为 null（用户在 Shell 模式但从未创建过对话），则跳过 `saveShellEventMessage()` 写入，只写 `command_executions`。Agent 回合启动时从 `command_executions` 查询最近命令作为补充。

### D6: 系统提示词结构

**选择**：`AgentSystemPrompt.build()` 新增两个可选参数：
- `recentShellCommands: List<ShellActivity>` — 最近 Shell 活动列表（命令 + 退出码）
- `nestedEnvironment: NestedEnvInfo` — 嵌套环境信息（是否嵌套、集成是否可用）

两个参数都可为 null/空，此时对应段落不渲染。

## Risks / Trade-offs

**[风险] 大量人工命令撑爆上下文** → 系统提示只注入最近 10 条命令摘要（非全量）；对话历史中的 `shell_event` 记录受 60 条窗口 + token 预算双重约束。极端情况下（用户执行了上百条命令），旧记录自然退出窗口。

**[风险] JaCoCo 阈值提升导致构建失败** → 先跑一次 `jacoco:report` 测量当前覆盖率，确认是否已达到 0.75。若未达到，需补充测试。

**[权衡] 输出摘要 500 字符** → 可能丢失关键信息（如长日志中的错误行），但完整输出会快速消耗上下文预算。完整数据保留在 `command_executions` 表中，模型可通过 `read_file` 等工具获取完整内容。

**[权衡] 不解析容器名/ID** → 模型只知道"在嵌套 Shell 中"，不知道具体容器名。解析容器名需要从 PTY 输出中提取（不可靠），增加复杂度但收益有限——模型可以通过执行 `hostname` / `cat /etc/hostname` 自行确认。
