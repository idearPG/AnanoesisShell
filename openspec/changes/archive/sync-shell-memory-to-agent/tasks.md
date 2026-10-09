## 1. 人工命令持久化接线

- [x] 1.1 `PtyCommandScheduler` 增加人工命令完成回调接口 `ManualCommandListener`（参数：命令原文、退出码、输出、cwd）及 `setManualCommandListener()` 安装方法。在 `handlePrompt()` 中当 `currentCommand == null && state == MANUAL_BUSY` 的 CMD_END+PROMPT 序列完成时，记录人工命令信息并在状态回到 MANUAL_IDLE 时触发回调。验证：单元测试确认回调在人工命令完成后被调用且参数正确
- [x] 1.2 `PtyCommandScheduler` 增加人工命令输出累积缓冲——在 MANUAL_BUSY/MANUAL_IDLE 状态下、无 `currentCommand` 时的 `collectOutput()` 输出需累积到人工命令缓冲中（与 Agent 命令的 `PendingCommand.outputBuffer` 分离），供回调传递输出摘要。验证：单元测试确认人工命令输出被正确累积
- [x] 1.3 `SessionRuntime` 或 `SshTerminalService` 层注入回调实现：接收人工命令信息 → 调用 `CommandExecutionService.claimExecution("manual", ...)` 记录到账本 → 调用 `ConversationService.saveShellEventMessage()` 写入对话历史（内容格式：`命令\nexit=<退出码>\n<输出前500字符>`，截断标注）。验证：集成测试确认 `command_executions` 和 `ai_messages` 均有记录
- [x] 1.4 `conversationId` 获取路径：确认当前 tab 的 `conversationId` 如何传递到持久化触发层。若 `conversationId` 为 null（用户从未创建对话），跳过 `saveShellEventMessage()` 但保留 `command_executions` 记录。验证：测试覆盖 conversationId 为 null 的降级路径

## 2. 嵌套环境状态暴露

- [x] 2.1 `PtyCommandScheduler` 增加 `isNestedShell()` 公开方法，返回当前 `nestedState` 是否为 PROBE_CONFIRMED 或 FALLBACK。验证：单元测试确认初始状态返回 false、探测确认后返回 true
- [x] 2.2 `PtyCommandGateway` 增加 `isNestedShell(String sessionId)` 方法，委托给 `findScheduler(sessionId).isNestedShell()`。验证：单元测试确认网关路由正确、会话不存在时返回 false

## 3. 系统提示词增强

- [x] 3.1 `AgentSystemPrompt.build()` 新增参数 `List<ShellActivity> recentCommands`（ShellActivity 为 record：command, exitCode）。当列表非空时追加"## 最近 Shell 活动"段落，格式为编号列表（`1. $ <命令> (exit=<退出码>)`）。列表为空或 null 时不渲染。验证：单元测试断言有活动时包含段落、无活动时不包含
- [x] 3.2 `AgentSystemPrompt.build()` 新增参数 `NestedEnvInfo nestedEnv`（record：boolean nested, boolean integrationAvailable）。当 nested=true 时追加嵌套环境说明段落（区分集成可用/降级两种措辞）。nested=false 或 null 时不渲染。验证：单元测试断言三种状态（嵌套+集成可用、嵌套+降级、无嵌套）的渲染结果
- [x] 3.3 `AgentTools` 或 `AiAgentService` 增加 `recentManualCommands(String sessionId, int limit)` 查询方法：从 `command_executions` 表按 `session_id` 查 `source='manual'` 的最近 N 条（按 `created_at DESC`），返回 `List<ShellActivity>`。验证：单元测试确认查询条件与排序正确

## 4. AiAgentService 接线

- [x] 4.1 `AiAgentService.runTurn()` 在构建系统提示时：①调用 `recentManualCommands(sessionId, 10)` 获取最近命令列表；②调用 `isNestedShell(sessionId)` 获取嵌套状态；③将两者传入 `AgentSystemPrompt.build()`。验证：集成测试确认系统提示包含最近命令和嵌套状态
- [x] 4.2 上下文恢复路径（`rebuildContextAfterLimit`）同步更新：恢复重建提示词时同样注入最近命令列表和嵌套状态。验证：测试确认恢复后提示词不丢失 Shell 上下文

## 5. JaCoCo 阈值提升

- [x] 5.1 `backend/pom.xml` JaCoCo check 的 `minimum` 从 `0.70` 改为 `0.75`。验证：运行 `mvnw -B verify` 确认门禁通过（若未达 0.75 需补充测试）

## 6. 端到端验证

- [x] 6.1 后端全量测试：`mvnw -B test` 全部通过（含新增的人工命令持久化、嵌套环境暴露、系统提示词增强测试）
- [x] 6.2 前端验证：`npm run type-check` 零错误 + `npm run test` 全部通过（本变更无前端改动，确认无回归）
- [x] 6.3 JaCoCo 覆盖率门禁：`mvnw -B verify` 中 `jacoco:check` 通过（分支覆盖率 ≥ 0.75）
- [x] 6.4 结构校验：`scripts/verify-structure.ps1` 通过
- [x] 6.5 更新 `.qoder/known-issues.md`：记录人工命令记忆同步接线（#33）和 JaCoCo 阈值提升（#34）
