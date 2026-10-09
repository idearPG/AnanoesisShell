## Why

v0.1.0 桌面客户端已发布，但三个用户体验痛点阻碍日常使用：终端无法复制文本（运维人员最基本的操作）；AI 通过 `run_command` 下载大文件时 60 秒超时过短必然失败；Agent 读取大文件时上下文超限报错。同时需要将版本基线标记为 v0.1.0 并开启 v0.2.0 开发线。

## What Changes

- 终端 xterm 新增剪贴板集成：`@xterm/addon-clipboard` + `rightClickSelects` + 自定义右键菜单（复制/粘贴），并解决 Ctrl+C 与中断快捷键的冲突（有选中时复制，无选中时保持中断）
- `run_command` 执行超时从 60 秒调整为 1800 秒（30 分钟），利用现有 watchdog 空闲检测作为心跳；SFTP 传输无进度超时从 120 秒调整为 300 秒
- `read_file` 工具增加 `start_line`/`end_line` 行范围参数实现分块读取；大文件达到行数上限时自动附加结构摘要（总行数 + 头尾片段 + 导航提示）；系统提示补充大文件读取纪律
- 在三仓当前 main 上打 `v0.1.0` tag，创建 `feature/v0.2.0-improvements` 分支用于后续开发

## Capabilities

### New Capabilities

（无新增能力）

### Modified Capabilities

- `terminal-workspace`: 新增剪贴板复制/粘贴能力、自定义右键菜单、Ctrl+C 智能分流（选中=复制/未选中=中断）
- `ssh-connection`: `run_command` 执行超时从 60 秒提升至 1800 秒，空闲检测保持 120 秒作为心跳
- `sftp-transfer`: 无进度超时从 120 秒提升至 300 秒
- `ai-agent`: `read_file` 工具签名增加行范围参数；大文件自动摘要；系统提示增强
- `agent-context`: 无规格级行为变更，但 `read_file` 返回内容结构变化（摘要 + 范围标注）影响上下文构建的输入形态

## Impact

- **前端**：`TerminalTimeline.vue`（addon 加载 + 右键菜单 + 键绑定拦截）、`package.json`（新增 `@xterm/addon-clipboard`）
- **后端**：`SettingsService`（默认超时值）、`V3__update_run_command_timeout.sql`（新增迁移更新种子行，V1 保持校验和不变）、`TransferProperties`（progress 超时）、`AgentTools.java`（read_file 签名 + 摘要逻辑）、`AgentSystemPrompt.java`（提示词）
- **测试**：前端 `TerminalTimeline.spec.ts`；后端 `AgentToolsTest`、超时相关用例
- **依赖**：新增 npm 包 `@xterm/addon-clipboard`
- **契约**：无 REST/WS 协议变更（工具参数变化对前端透明）
- **Git**：三仓打 tag + 创建 feature 分支
