## ADDED Requirements

### Requirement: 人工命令记忆同步
系统 SHALL 将用户在 Shell 模式下手动执行的每一条可识别命令（经 Shell 集成帧协议解析出 CMD_START + CMD_END 的命令）持久化到当前 tab 对应的对话历史中（`source=shell_event`），内容包括命令原文、退出码与输出摘要。Agent 构建上下文时 SHALL 将这些记录与 AI 消息共同纳入模型输入，使模型能引用用户手动执行过的命令及结果。

#### Scenario: 人工命令自动进入 Agent 上下文
- **WHEN** 用户在 Shell 模式执行一条命令（如 `ls -la /tmp`）并产生 CMD_END 帧
- **THEN** 该命令的原文、退出码与输出摘要作为 `source=shell_event` 消息写入当前对话历史，后续 Agent 回合的上下文历史中包含此记录

#### Scenario: 全部人工命令无过滤记录
- **WHEN** 用户在 Shell 模式连续执行多条命令（`cd /opt`、`docker ps`、`cat config.yml`）
- **THEN** 每条命令均有对应的 `shell_event` 记录写入对话历史，不做内容过滤或去重

#### Scenario: 人工命令输出截断
- **WHEN** 人工命令输出超过摘要上限（如 `cat` 一个大文件）
- **THEN** 写入对话历史的输出摘要被截断并标注截断标记，原始完整输出仍存于 `command_executions` 表

### Requirement: 系统提示词注入最近 Shell 活动
`AgentSystemPrompt` 构建系统提示时 SHALL 包含一个"最近 Shell 活动"段落，列出当前会话最近若干条人工命令的命令原文与退出码，使模型在回答前即可感知用户在 Shell 中做了什么。无最近活动时该段落不渲染。

#### Scenario: 有最近 Shell 活动时注入活动摘要
- **WHEN** 用户最近在当前连接执行了若干命令后切到 Agent 模式提问
- **THEN** 系统提示包含"最近 Shell 活动"段落，列出命令原文与退出码

#### Scenario: 无 Shell 活动时不渲染
- **WHEN** 当前连接尚无任何人工命令记录
- **THEN** 系统提示不包含"最近 Shell 活动"段落

### Requirement: 嵌套 Shell 环境感知
系统 SHALL 检测用户是否进入了嵌套 Shell 环境（如通过 `docker exec -it <container> bash` 进入容器），并在 Agent 系统提示中注入该环境状态。嵌套检测由 `PtyCommandScheduler` 的帧超时探测机制驱动；检测到嵌套环境后，系统提示 SHALL 告知模型当前可能处于嵌套 Shell（如 Docker 容器）中。

#### Scenario: 检测到嵌套 Shell 后注入提示
- **WHEN** 嵌套 Shell 探测机制确认用户进入了嵌套环境（探测标记回显匹配）
- **THEN** Agent 系统提示包含嵌套环境说明（如"用户终端当前可能处于 Docker 容器或嵌套 Shell 中"），模型据此调整命令建议

#### Scenario: 嵌套 Shell 降级后仍注入提示
- **WHEN** 嵌套 Shell 集成重安装失败、降级为 exec 通道模式
- **THEN** 系统提示仍包含嵌套环境说明，同时告知模型 Shell 集成不可用、工具可能无法正常工作

#### Scenario: 未检测到嵌套环境时不渲染
- **WHEN** 用户始终在初始 Shell 中操作，未进入任何嵌套环境
- **THEN** 系统提示不包含嵌套环境段落
