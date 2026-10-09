## 1. 版本分支管理

- [x] 1.1 三仓打 v0.1.0 tag：主控 `git tag -a v0.1.0 -m "release: v0.1.0 desktop client"`，frontend/backend 同理，验证 `git tag -l` 列出 v0.1.0
- [x] 1.2 三仓创建 feature/v0.2.0-improvements 分支并切换，验证 `git branch --show-current` 输出正确
- [x] 1.3 推送 tag 和分支到远端并验证远端可见（三仓各 `git push origin v0.1.0` + `git push origin feature/v0.2.0-improvements`）；全部成功（backend/main tag 已在远端，frontend tag 补推成功；三仓分支均推送至 d6de90f/8390ca5/22a4054）

## 2. 终端剪贴板集成（前端）

- [x] 2.1 安装 `@xterm/addon-clipboard` 依赖（`npm install @xterm/addon-clipboard`），验证 package.json 已更新且 `npm install` 无报错
- [x] 2.2 在 `TerminalTimeline.vue` 的 `initTerminal` 中加载 `ClipboardAddon`，添加 `rightClickSelects: true` 选项，验证终端初始化无报错
- [x] 2.3 实现 Ctrl+C 自定义键绑定：通过 `attachCustomKeyEventHandler` 拦截 Ctrl+C，有选中时调用 `navigator.clipboard.writeText` 复制并 `return false` 阻止默认中断，无选中时放行到 `onData` 保持原有中断行为，验证有选中时 Ctrl+C 不发送 `\x03`
- [x] 2.4 实现自定义右键菜单组件：禁用浏览器默认 `contextmenu`，渲染浮动菜单（复制/粘贴），复制按钮根据 `terminal.getSelection()` 启用/禁用，粘贴按钮通过 `sendInput` 发送到 PTY，样式使用深色主题，验证右键菜单正常弹出且功能正确
- [x] 2.5 补充 `TerminalTimeline.spec.ts` 测试用例：覆盖 Ctrl+C 有选中复制、无选中中断、右键菜单渲染、复制/粘贴按钮状态、Ctrl+V 粘贴分流，验证 `vitest run` 全部通过
- [x] 2.6 核对 spec delta（terminal-workspace）的 Ctrl+V 要求：经源码核实 ClipboardAddon 0.2.0 仅注册 OSC 52 处理器、不拦截键盘事件，Ctrl+V 走 xterm 原生 paste → onData → shellInput/agentInput 分流路径，满足 spec 要求；已补 3 个测试用例证明分流路径

## 3. run_command 超时优化（后端）

- [x] 3.1 修改 `SettingsService.DEFAULT_RUN_COMMAND_TIMEOUT_SECONDS` 从 60 改为 1800，验证编译通过
- [x] 3.2 已发布的 `V1__init_schema.sql` 保持不回写（`run_command.timeout.seconds` 种子还原为 60，校验和不变；v0.1.0 已发布，回写会使已安装旧库 Flyway 校验失败且种子值不更新）；新增 `V3__update_run_command_timeout.sql` 将种子值与描述更新为 1800 秒；同步 `SshPropertiesDefaultsTest`（解析 V1+V3 有效值）、`FlywayMigrationPurityTest`（迁移数 2→3）与 `SettingsApiIntegrationTest` 断言，验证迁移测试通过
- [x] 3.3 确认 `PtyCommandScheduler.DEFAULT_MAX_ABSOLUTE_MS` 已是 30 分钟（1_800_000ms），无需修改；同步其余超时相关测试断言（`ApprovedCommandRunnerTest` 种子恢复值 60→1800 等），全局无残留 60 秒断言
- [x] 3.4 修改 `TransferProperties.progressTimeoutSeconds` 从 120 改为 300，验证编译通过且相关测试更新

## 4. read_file 分块读取 + 大文件摘要（后端）

- [x] 4.1 在 `AgentTools.readFile` 方法签名中增加 `start_line` 和 `end_line` 可选 `@ToolParam` 参数，验证编译通过
- [x] 4.2 实现行范围读取逻辑：传范围时用 `sed -n 'X,Yp'` 替代 `head -n`，结果头部标注 `[行 X-Y / 总 Z 行]`（通过 `wc -l` 获取总行数，wc 失败时降级为 `[行 X-Y]`），验证 `AgentToolsTest` 范围读取用例通过
- [x] 4.3 实现大文件自动摘要：无范围读取达 `max_lines` 上限时，额外执行 `wc -l` 获取总行数，返回头部 20 行 + 尾部 10 行 + 截断提示（含中间省略行数和行范围参数使用引导），验证摘要格式测试通过
- [x] 4.4 在 `AgentSystemPrompt` 的工具纪律段落补充大文件读取策略：先用 `wc -l` 查行数、用 `read_file` 行范围参数分段读取、优先 `grep -n` 定位，验证提示词包含新增指引
- [x] 4.5 更新 `AgentToolsTest` 测试用例至 4 参签名：覆盖范围读取（start_line/end_line）、大文件摘要触发、小文件不触发摘要、边界值（start_line > 总行数、end_line < start_line、start_line ≤ 0 归一、wc/tail 失败降级），37 个用例全部通过

## 5. 集成验证

- [x] 5.1 前端全量门禁：type-check + vitest run + build 全部零错误（复验：24 文件/305 用例全过，退出码 0）
- [x] 5.2 后端全量测试：`.\backend\mvnw.cmd -f backend/pom.xml -B test`，全部通过（复验：883 tests/0 failures/0 errors；JaCoCo 分支覆盖率 ≥ 0.70 门禁通过）
- [x] 5.3 结构验证：`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify-structure.ps1 -Root .`，通过（复验：根 24 项 + vendored skills 8 项 + 子模块 2 项全部 [OK]）
- [x] 5.4 OpenSpec 校验：`openspec validate add-v020-improvements --strict`，零失败（复验退出码 0）
- [x] 5.5 Electron 打包版验证：`scripts/build-desktop.ps1` 构建通过（产物 `frontend/desktop/dist-release/AnanoesisShell-Setup-0.2.0.exe` 193MB，版本号已升至 v0.2.0，不覆盖旧版 v0.1.0）；打包版剪贴板实测（拖选复制、Ctrl+C 分流、Ctrl+V 粘贴、右键菜单）待用户人工进行
