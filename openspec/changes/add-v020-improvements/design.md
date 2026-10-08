## Context

v0.1.0 桌面客户端已发布。三个用户痛点阻碍日常使用：终端无法复制、AI 下载超时过短、Agent 读大文件上下文超限。详见 proposal.md。

当前技术约束：
- 前端 xterm.js 5.5 + 仅加载 `FitAddon`，无剪贴板 addon
- `run_command` 超时 60 秒（`SettingsService.DEFAULT_RUN_COMMAND_TIMEOUT_SECONDS`），`PtyCommandScheduler.DEFAULT_MAX_ABSOLUTE_MS` 已是 30 分钟（BUG-A 修复时调整）
- SFTP `TransferProperties.progressTimeoutSeconds` = 120 秒
- `read_file` 行数上限 500 行（`SettingsService.DEFAULT_READ_FILE_MAX_LINES`），无行范围参数
- `AgentContextBuilder` 已有 60 条窗口 + 头尾投影 + 淘汰 + 单次恢复机制

## Goals / Non-Goals

**Goals:**
- 终端支持鼠标选择 + 右键菜单复制/粘贴，Ctrl+C 不冲突
- `run_command` 超时提升到 30 分钟，空闲检测保持心跳
- SFTP 无进度超时提升到 5 分钟
- `read_file` 支持行范围分块读取 + 大文件自动摘要
- 系统提示引导模型使用分块读取策略
- 三仓打 v0.1.0 tag + 创建 feature/v0.2.0-improvements 分支

**Non-Goals:**
- 不新增心跳协议（现有 watchdog 已具备心跳语义）
- 不引入服务端 LLM 摘要调用（摘要为结构化提取，不依赖模型）
- 不修改 `agent-context` 的上下文构建逻辑（现有投影/淘汰/恢复机制不变）
- 不变更 REST/WS 契约
- 不做自定义右键菜单之外的剪贴板 UI（如工具栏按钮）

## Decisions

### D1: 剪贴板方案 — `@xterm/addon-clipboard` + 自定义键绑定

**选择**：使用 xterm.js 官方 `@xterm/addon-clipboard`，但不依赖其默认 Ctrl+C 绑定。通过 `terminal.attachCustomKeyEventHandler` 拦截 Ctrl+C，根据 `terminal.getSelection()` 判断分流。

**替代方案**：
- A) 直接使用 addon 默认绑定 → Ctrl+C 被剪贴板独占，破坏中断功能
- B) 不引入 addon，纯手动实现 `navigator.clipboard` 读写 → 重复造轮子，跨浏览器兼容性差

**理由**：addon 提供经过验证的剪贴板读写能力（含 Electron 兼容），自定义键处理器保留中断语义。

### D2: 右键菜单 — 自定义浮动 DOM 菜单

**选择**：禁用 xterm 容器上的浏览器默认右键菜单，渲染 Vue 浮动组件。

**替代方案**：
- A) 使用浏览器原生右键 → 无法控制菜单项和样式，Electron 行为不一致
- B) 使用 xterm 的 `TextAreaClipboardHandler` → 不提供右键菜单 UI

**理由**：自定义菜单可精确控制「复制/粘贴」按钮的启用/禁用状态、深色主题样式、Electron 兼容性。

### D3: 超时调整 — 仅改 settings 层默认值

**选择**：`DEFAULT_RUN_COMMAND_TIMEOUT_SECONDS` 60→1800；已发布的 `V1__init_schema.sql` 不回写（保持校验和不变），追加 `V3__update_run_command_timeout.sql` 更新种子行值与描述（v0.1.0 旧库升级与新库初始化均生效）。`PtyCommandScheduler.DEFAULT_MAX_ABSOLUTE_MS` 已是 30 分钟不改。空闲超时 120 秒不改。

**理由**：watchdog 空闲检测 = 心跳（有输出就续命），绝对上限 = 安全网。下载场景有持续输出，空闲超时不会被触发；绝对上限 30 分钟足够覆盖绝大多数下载。迁移追加新版本而非回写 V1：已发布环境持有旧 V1 校验和，回写会导致旧库 Flyway 校验失败，且 V1 不会重跑、旧库种子值不更新。

### D4: read_file 分块 — 工具签名扩展 + 服务端摘要

**选择**：`read_file` 增加 `start_line`/`end_line` 可选参数。无范围读取达上限时，额外执行 `wc -l` 获取总行数，返回头部 20 行 + 尾部 10 行 + 摘要提示。

**替代方案**：
- A) 纯分块无摘要 → 模型不知道文件有多大，无法判断该读哪些行
- B) 服务端 LLM 摘要 → 引入额外模型调用延迟和成本，违反"只读工具自动执行"的快进快出原则
- C) 不改工具，靠系统提示让模型自己用 `sed -n` → 增加工具调用轮次，浪费上下文

**理由**：行范围参数让模型精确读取，摘要提供全貌导航，两者互补。`wc -l` 是轻量 exec，开销可忽略。

### D5: 系统提示增强 — 工具纪律补充

**选择**：在 `AgentSystemPrompt` 的工具纪律段落补充大文件读取策略指引。

**理由**：即使工具支持分块，模型仍需被引导优先使用 `grep -n` 定位 + 行范围读取，而非一次全量加载。

## Risks / Trade-offs

- **[Ctrl+C 分流边界]** 选中文本后 Ctrl+C 复制而非中断 → 用户可能困惑"为什么 Ctrl+C 没中断"。缓解：有选中时视觉高亮明确，且右键菜单提供替代中断路径（Agent 模式通过提示行停止）。
- **[read_file 摘要开销]** 每次大文件读取额外执行 `wc -l` → 多一次 SSH exec。缓解：仅在读达上限时触发，小文件不触发；`wc -l` 是极轻量命令。
- **[超时调大后的资源占用]** `run_command` 30 分钟 → 一个挂住的命令会占用 PTY 更久。缓解：空闲超时 120 秒仍生效，假死命令会被快速中断；绝对上限 30 分钟是安全网而非预期运行时长。
- **[Electron 右键菜单]** CSP 或 Electron 原生菜单可能拦截自定义右键。缓解：实施时在打包版验证，CSP `default-src` 已允许内联事件。
