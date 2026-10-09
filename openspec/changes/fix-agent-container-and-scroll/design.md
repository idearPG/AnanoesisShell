## Context

当前 Shell 集成（`ShellIntegration.generateBashIntegrationCode`）生成的钩子代码定义了 bash 函数 `_ananoesis_prompt_hook` 和 `_ananoesis_debug_hook`，PROMPT_COMMAND 和 DEBUG trap 引用这些函数名。当用户在 PTY 中启动嵌套 bash（`docker exec -it container bash`），子 bash 通过环境变量继承了 PROMPT_COMMAND 字符串和函数引用，但 bash 函数体默认不通过环境传递（除非显式 `export -f`，而我们的安装代码未做此操作）。嵌套 bash 执行 PROMPT_COMMAND 时函数不存在，帧产出静默失败。

前端 `TerminalTimeline.writeToTerminal()` 每次写入后无条件调用 `scrollToBottom()`，Agent 流式回复期间高频触发（每个 SSE delta 一次），用户向上滚动被立即拉回。

## Goals / Non-Goals

**Goals:**
- 嵌套 bash 环境下 Agent 命令不挂死，能自动恢复集成或降级到 exec 通道
- 流式输出期间用户可自由滚动查看历史，不影响输出写入
- 方案对现有 Shell 模式、Agent 模式、审批链路零侵入

**Non-Goals:**
- 不支持非 bash 嵌套 Shell 的集成安装（仅降级到 exec）
- 不做自动检测嵌套层级深度（仅检测"帧缺失"事实）
- 不实现"一键回到容器外层"的 Shell 导航辅助

## Decisions

### D1: 嵌套 Shell 检测 — 帧超时 + 探测命令

**方案**：`PtyCommandScheduler` 新增"帧活动超时"探测。当调度器处于 MANUAL_IDLE 状态（无在飞命令）但超过 `nestedDetectTimeout`（默认 8s）未收到任何帧（PROMPT/CWD/CMD_START/CMD_END），判定为"疑似嵌套 Shell"。此时向 PTY 写入一行探测命令（`echo _ANANOESIS_NESTED_PROBE_$$`），若回显中出现该标记但无有效帧，确认嵌套 Shell 存在。

**替代方案**：
- (A) 修改集成代码为 `export -f` 导出函数——被否决：嵌套 Shell 可能是 sh/dash 不支持 `export -f`，且 Docker 容器内 bash 版本不确定
- (B) 在 PROMPT_COMMAND 中内联全部逻辑（不引用函数）——被否决：代码体积大且拼接复杂度高，维护成本超过探测方案
- (C) 用 OSC 序列探测——被否决：嵌套 Shell 可能不处理 OSC

**选择帧超时的理由**：与现有空闲超时（#21/#24）语义正交——空闲超时限定命令执行时长，帧超时限定"空闲 Shell 应该持续产出帧"的预期。两者独立不互相干扰。

### D2: 集成重安装 — 复用现有 ShellIntegration.install()

确认嵌套后，构造新的 nonce 并重新调用 `ShellIntegration.install()`。由于当前 Shell 已有一个旧 PROMPT_COMMAND（引用不存在的函数），新安装代码会保存旧值（`_ANANOESIS_OLD_PC`）并覆盖为新函数。新函数在嵌套 bash 中定义并立即可用。

重装最多尝试 1 次。若重装后仍无帧（再等一个超时周期），降级为 exec 通道模式：调度器标记 `nestedFallback=true`，后续 submitCommand 直接抛 IllegalArgumentException，调用方（ApprovedCommandRunner / AgentTools）走已有 exec 回落路径。

### D3: 滚动位置感知 — viewport offset 检测

**方案**：`TerminalTimeline` 新增 `userScrolledAway: boolean` 标志。通过监听 xterm 的 `onScrollLines` 或 `onScrollPages` 事件（xterm.js 5.x 提供 `buffer.viewportY` 与 `buffer.length`），当用户滚动使 viewport 偏离底部超过阈值（2 行）时置位。`writeToTerminal()` 检查该标志：置位时跳过 `scrollToBottom()`。

**恢复自动跟随**：用户滚动回底部（viewport offset 在阈值内）时清除标志，后续写入恢复自动滚底。也可通过鼠标点击终端底部区域或按 End 键触发。

**替代方案**：
- (A) 用 `terminal.options.scrollback` 限制——被否决：影响全局缓冲区大小
- (B) 每次写入前检查 `terminal.buffer.active.viewportY === terminal.buffer.active.baseY`——这是正确的检测方式，但 xterm.js 5.x 的 buffer API 需要确认具体属性名

**选择 viewport offset 的理由**：最小侵入，不改变 xterm 配置，仅增加写入前的条件判断。

### D4: 前端滚动状态的数据流

```
xterm onScrollLines → 计算 viewportOffset → 更新 userScrolledAway
  ↓
writeToTerminal(data) → terminal.write(data) → if (!userScrolledAway) scrollToBottom()
  ↓
用户滚回底部 → userScrolledAway = false → 后续写入恢复自动跟随
```

`refit()`（切回 tab 时调用）保持现有 `scrollToBottom()` 行为——切回时用户期望看到最新内容。

## Risks / Trade-offs

- **[帧超时误判]** → 用户长时间不操作（如离开座位）后回来提问，可能触发嵌套检测。缓解：仅在调度器有活动（最近收到过帧或命令提交）后才启动探测定时器；完全空闲超过 5 分钟的会话不触发。
- **[重装集成破坏嵌套 Shell 状态]** → 向嵌套 Shell 写入安装代码会出现在其终端中。缓解：安装代码已在 stty -echo 环境下执行（用户看不到），且是单行命令不触发续行提示。
- **[viewport API 兼容性]** → xterm.js 版本升级可能改变 buffer API。缓解：封装为 `isViewportAtBottom()` 函数，升级时只需修改一处。
- **[嵌套检测增加 PTY 写入]** → 探测命令会出现在 PTY 输出中。缓解：探测命令简短（`echo _ANANOESIS_NESTED_PROBE_$$`），且只在空闲超时后触发一次。
