## ADDED Requirements

### Requirement: 嵌套 Shell 环境下的集成恢复

当用户在交互式 PTY 中启动嵌套 Shell（如 `docker exec -it <container> bash`、`su - user`、`chroot`），系统 SHALL 检测到帧产出中断并在可配置超时后自动向当前 Shell 层重新发送集成代码，恢复命令边界帧的产出。若重装失败（如嵌套 Shell 为非 bash 类型），系统 SHALL 将调度器降级为 exec 通道模式并在终端内给出用户可理解的提示，而非让命令无限挂死。

#### Scenario: 用户 docker exec 进入容器后 Agent 命令仍可执行

- **WHEN** 用户在 Shell 模式执行 `docker exec -it <container> bash` 进入嵌套 bash 后切到 Agent 模式提问
- **THEN** 系统在帧超时阈值内检测到无帧产出，自动向嵌套 Shell 重新安装集成钩子，Agent 命令经恢复后的 PTY 调度器正常执行并返回结果

#### Scenario: 嵌套 Shell 为非 bash 时降级到 exec 通道

- **WHEN** 嵌套 Shell 为 sh/dash/zsh 等非 bash 类型且集成重安装失败
- **THEN** Agent 工具经 exec 通道降级执行（与未安装集成时行为一致），终端显示提示说明自动命令已切换为独立执行模式

#### Scenario: 帧超时阈值可配置

- **WHEN** 管理员设置 `shell.nested-detect-timeout-seconds` 为自定义值
- **THEN** 系统按该值判定帧超时，0 表示禁用嵌套检测（保持旧行为）

### Requirement: 流式输出期间保留用户滚动位置

当 Agent 流式回复或 Shell 持续输出时，系统 SHALL 检测用户是否已主动向上滚动离开终端底部。若用户视口不在底部，新输出 MUST 继续写入 xterm buffer 但 MUST NOT 强制滚动到底部（不拉回用户视口）。仅当用户视口已在底部时才自动跟随滚底。

#### Scenario: 用户向上滚动查看历史不被拉回

- **WHEN** Agent 正在流式回复且用户向上滚动查看历史输出
- **THEN** 用户视口停留在滚动位置，新内容继续出现在 buffer 底部但不强制拉回；用户手动滚回底部后恢复自动跟随

#### Scenario: 用户未滚动时正常跟随输出

- **WHEN** Agent 流式回复且用户未滚动（视口在底部）
- **THEN** 终端自动跟随最新输出滚动，行为与本变更前一致
