## ADDED Requirements

### Requirement: 嵌套容器环境中的工具执行

当用户通过嵌套 Shell（Docker 容器、chroot、su 等）改变了 PTY 的 Shell 层级时，Agent 工具执行 SHALL 仍能正常工作：若 PTY 集成已恢复则经 PTY 路径执行；若集成降级则自动回退到 exec 通道执行，MUST NOT 让命令无限挂死。

#### Scenario: 嵌套容器中只读工具正常返回结果

- **WHEN** 用户在 Docker 容器内的嵌套 Shell 中要求 Agent 读取文件
- **THEN** 只读工具经 PTY（集成已恢复）或 exec 通道执行并返回结果，用户看到工具输出而非超时错误

#### Scenario: 嵌套容器中审批命令正常执行

- **WHEN** 用户在 Docker 容器内的嵌套 Shell 中批准 Agent 命令
- **THEN** 命令经可用的执行路径（PTY 或 exec）执行，输出回流到终端，不因帧缺失而挂死
