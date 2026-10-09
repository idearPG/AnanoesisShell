## Why

用户报告两个影响 Agent 模式可用性的 BUG：

1. **Agent 进入 Docker 容器后无响应**：用户在 Agent 模式下 SSH 连接到 Linux 主机后，手动执行 `docker exec -it <container> bash` 进入容器，Agent 此后不再响应提问。根因是 Shell 集成钩子（PROMPT_COMMAND 引用 `_ananoesis_prompt_hook` 函数）以环境变量形式被子 bash 继承，但函数体本身不被继承——嵌套 bash 执行 PROMPT_COMMAND 时报 "command not found"，帧产出静默失败，调度器永远等不到 CMD_END/PROMPT 帧，命令挂死直到超时。

2. **Agent 回复时无法向上滚动**：Agent 流式回复期间，每次 `writeToTerminal()` 都无条件调用 `scrollToBottom()`，用户向上滚动查看历史时立即被拉回底部。根因是 `TerminalTimeline.scrollToBottom()` 没有检测用户是否已主动滚动离开底部。

## What Changes

- **嵌套 Shell 检测与集成重安装**：当调度器在命令提交后长时间未收到任何帧（超过可配置阈值，默认 8s），且当前无在飞命令时，判定为"疑似嵌套 Shell"——向 PTY 写入一行探测命令（输出特殊标记 + 当前 Shell 层级），确认后重新发送集成代码到当前 Shell 层。
- **用户滚动状态感知**：`writeToTerminal()` 在写入数据后仅在用户视口位于底部时才自动滚底；用户主动向上滚动时不强制拉回，新输出照常写入 buffer 但不干扰浏览。提供手动回到底部的入口（如滚动条拖到底或按 End 键）。

## Capabilities

### New Capabilities

（无新增 capability）

### Modified Capabilities

- `terminal-workspace`：新增"嵌套 Shell 环境下的 Agent 命令执行"场景——嵌套 bash/dash 中 Shell 集成 MUST 自动恢复或给出明确降级提示；新增"流式输出期间保留用户滚动位置"场景——异步输出不得强制拉回已离开底部的视口。
- `ai-agent`：新增"嵌套容器/Shell 环境中的工具执行"场景——Agent 工具在嵌套环境中 MUST 仍能执行并返回结果（经 exec 通道降级或集成恢复）。

## Impact

- **后端**：`PtyCommandScheduler` 新增帧超时探测逻辑；`ShellIntegration` 可能需要改为自包含内联脚本（不依赖函数引用）或新增嵌套重装路径；`SshTerminalService` 接线探测定时器。
- **前端**：`TerminalTimeline.vue` 的 `writeToTerminal()` 增加滚动位置检测；新增 `userScrolledAway` 标志与鼠标/滚轮事件监听。
- **测试**：后端新增嵌套 Shell 帧超时探测回归；前端新增滚动行为回归用例。
- **不涉及**：契约变更、数据库迁移、新依赖。
