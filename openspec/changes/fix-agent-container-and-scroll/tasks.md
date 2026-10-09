## 1. 嵌套 Shell 检测（后端）

- [x] 1.1 `PtyCommandScheduler` 新增帧活动超时字段 `lastFrameNanos`，在 `onFrame`/`collectOutput` 中刷新；新增 6 参构造器（追加 `nestedDetectTimeoutMs`，默认 8000ms，0 表示禁用）
- [x] 1.2 `PtyCommandScheduler` 新增 `scheduleNestedProbe()` 方法：MANUAL_IDLE 且距上次帧超过阈值时触发，向 PTY 写入 `echo _ANANOESIS_NESTED_PROBE_$$\n`；在 `onStdout` 中检测该标记回显
- [x] 1.3 探测确认后调用 `ShellIntegration.reinstall(terminal, shellType, ...)` 用新 nonce 重新安装集成代码；新增 `nestedReinstallAttempts` 计数器，最多尝试 1 次
- [x] 1.4 重装后仍无帧（再等一个超时周期）则设置 `nestedFallback=true`，`submitCommand` 抛 `IllegalArgumentException` 走 exec 回落
- [x] 1.5 `SshProperties` 新增 `nestedDetectTimeout` 配置项（`shell.nested-detect-timeout-seconds`，默认 8）；`SshTerminalService.open()` 传入调度器构造
- [x] 1.6 回归测试：`PtyCommandSchedulerTest` 新增 `nestedShellDetectedAfterFrameTimeout`（模拟帧超时→探测→重装）、`nestedShellFallbackToExecAfterFailedReinstall`（重装失败后 submitCommand 抛异常）

## 2. Shell 集成重安装（后端）

- [x] 2.1 `ShellIntegration` 新增 `reinstall(nonce)` 方法：复用 `generateBashIntegrationCode` 生成新 nonce 的代码，经现有 `install()` 单行发送路径写入 PTY
- [x] 2.2 `ShellIntegrationInstaller` 新增 `reinstall()` 静态方法：构造新 nonce + 新调度器 + 新帧剥离监听器，返回新 `Outcome`
- [x] 2.3 `SshTerminalService.installShellIntegration` 新增 `reinstallShellIntegration()` 方法：用新 Outcome 替换 runtime 的 scheduler 和输出链
- [x] 2.4 回归测试：`ShellIntegrationTest.reinstallGeneratesNewNonceAndCode`（新旧 nonce 不同）、`ShellIntegrationInstallerTest.reinstallProducesNewOutcome`

## 3. 用户滚动位置感知（前端）

- [x] 3.1 `TerminalTimeline.vue` 新增 `userScrolledAway` ref 和 `isViewportAtBottom()` 函数：通过 `terminal.buffer.active.viewportY` 与 `terminal.buffer.active.baseY - terminal.rows` 比较（容差 2 行）
- [x] 3.2 挂载 xterm `onScrollLines` 监听器：每次滚动后调用 `isViewportAtBottom()` 更新 `userScrolledAway`；在 `cleanupTerminal()` 中释放
- [x] 3.3 `writeToTerminal()` 改为条件滚底：`terminal?.write(data)` 后仅当 `!userScrolledAway.value` 时调用 `scrollToBottom()`
- [x] 3.4 用户滚回底部时自动恢复跟随：`onScrollLines` 回调中 `isViewportAtBottom()` 为 true 则清除 `userScrolledAway`
- [x] 3.5 `refit()` 保持无条件 `scrollToBottom()`（切回 tab 时用户期望看到最新内容，不受此变更影响）
- [x] 3.6 回归测试：`TerminalTimeline.spec.ts` 新增 `writeDuringScrollDoesNotForceScrollToBottom`（模拟用户滚动后写入不触发 scrollToBottom）、`scrollBackToBottomResumesAutoFollow`（滚回底部后恢复跟随）

## 4. 端到端验证与文档

- [x] 4.1 后端全量测试通过：`mvnw -B test` 零失败（888/888）
- [x] 4.2 前端全量测试通过：`npm run test` + `npm run type-check` 零失败（308/308 + vue-tsc 0 错误）
- [ ] 4.3 浏览器终验：(A) docker exec 进容器后 Agent 提问→命令执行→结果回流；(B) Agent 流式回复中向上滚动→不被拉回→滚回底部→恢复跟随（需真实 Linux + Docker 环境，待人工验证）
- [x] 4.4 更新 `.qoder/known-issues.md` 补充两条新记录（#31 嵌套 Shell 帧丢失 + #32 流式输出强制滚底）
