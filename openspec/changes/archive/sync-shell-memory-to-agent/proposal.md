## Why

用户在 Shell 模式下手动执行的命令（如 `docker exec -it <container> bash`、`cd /opt/app`）对 Agent 模式完全不可见。Agent 的系统提示只注入当前工作目录，不知道用户最近做了什么命令、是否进入了容器或嵌套 Shell。结果：用户在 Shell 里进入 Docker 容器后切到 Agent 模式提问，Agent 仍以为自己在宿主机环境，给出完全错误的建议。

基础设施已就绪（`saveShellEventMessage()`、`ai_messages.source = 'shell_event'`、`command_executions` 表），但生产代码从未调用——这是一个"设计好了但没接线"的功能。

## What Changes

- **人工命令持久化**：`PtyCommandScheduler` 完成一条人工命令（CMD_END + PROMPT 序列）时，将命令原文 + 退出码 + 输出摘要写入 `ConversationService.saveShellEventMessage()`，使 Agent 上下文历史包含用户手动执行的所有命令
- **系统提示词增强**：`AgentSystemPrompt.build()` 新增"最近 Shell 活动"段落，注入最近 N 条人工命令的命令原文与退出码，让模型一眼看到用户在 Shell 里做了什么
- **嵌套 Shell 环境感知**：当嵌套 Shell 检测机制触发时（`PtyCommandScheduler.nestedState`），将"当前处于嵌套环境"这一事实注入系统提示，让模型知道用户可能进入了 Docker 容器等嵌套 Shell
- **JaCoCo 阈值提升**：分支覆盖率门禁从 0.70 提升至 0.75

## Capabilities

### New Capabilities

（无新增 capability）

### Modified Capabilities

- `ai-agent`：新增"人工命令记忆同步"需求——Agent 系统提示 SHALL 包含用户最近 Shell 活动摘要，人工命令 SHALL 持久化到对话历史供 Agent 引用；新增"嵌套 Shell 环境感知"需求——系统提示 SHALL 注入嵌套环境状态
- `agent-context`：人工命令记录（`source=shell_event`）SHALL 纳入 60 条上下文窗口与 token 预算计算，与 AI 消息共同构成近期上下文

## Impact

- **后端**：`PtyCommandScheduler`（人工命令完成回调）、`AgentSystemPrompt`（新增 Shell 活动段落 + 嵌套环境段落）、`AiAgentService.runTurn()`（传递最近命令列表 + 嵌套状态）、`SessionRuntime` 或 `PtyCommandGateway`（暴露最近人工命令查询接口）
- **数据库**：无 schema 变更（`ai_messages.source`、`command_executions` 已就绪）
- **前端**：无直接变更（Agent 提示词增强是后端行为）
- **测试**：需新增人工命令持久化触发测试、系统提示词新段落断言、嵌套环境注入测试
- **构建**：JaCoCo 阈值 0.70 → 0.75，可能需要补充测试以维持门禁
