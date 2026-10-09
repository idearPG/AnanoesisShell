## MODIFIED Requirements

### Requirement: 交互式终端会话
系统 SHALL 为每个独立连接提供持久交互式终端，支持用户输入命令、实时流式回显输出，并正确呈现常见交互行为（彩色输出、光标控制、中断信号）。人工与 Agent 命令 SHALL 使用所属连接的同一持久 Shell；PTY 输出按合流处理，不承诺拆分标准输出与标准错误。经审批的 `run_command` 执行超时 SHALL 为 1800 秒（30 分钟），空闲超时（无 stdout/stderr 输出）SHALL 为 120 秒作为心跳检测。

#### Scenario: 命令实时回显
- **WHEN** 用户在终端输入命令并回车
- **THEN** 系统流式展示该命令经 PTY 合流后的标准输出与标准错误，不重复渲染同一份执行输出

#### Scenario: 交互式程序可用
- **WHEN** 用户运行需要交互的程序（如 top、vim）
- **THEN** 终端正确渲染其界面并转发用户的按键输入，此时不接受 Agent 自动命令注入

#### Scenario: 中断运行中的命令
- **WHEN** 用户发送中断信号（Ctrl-C）
- **THEN** 系统将该信号转发至远端前台命令；只有取得结束证据才标记为终止，不能确认时明确显示状态未知

#### Scenario: AI 下载大文件不超时
- **WHEN** AI 代理通过 `run_command` 执行 wget/curl 下载大文件，下载过程持续产生输出（进度条）
- **THEN** 命令在 30 分钟内不被执行超时中断；watchdog 因持续收到输出而不断重置空闲计时器

#### Scenario: 下载假死被心跳检测
- **WHEN** `run_command` 执行过程中远端连续 120 秒无任何 stdout/stderr 输出
- **THEN** 空闲超时触发，系统向远端发送 Ctrl-C 中断命令，模型收到超时反馈
