# 已知问题记录（Known Issues）

> 本文档记录项目开发过程中遇到的 bug、错误和解决方案，避免后续重复踩坑。
> **开发前必读**；**解决问题后必须补充**（症状 / 根本原因 / 解决方案 / 预防措施）。

---

## 记录规范

每条问题按以下结构记录（编号递增）：

    ## N. <一句话标题>
    **发现时间**: YYYY-MM-DD
    **影响范围**: <受影响的模块/流程>
    **症状**: <可观测到的错误表现>
    **根本原因**: <为什么会发生>
    **解决方案**: <如何修复，含命令/代码>
    **预防措施**: <如何避免再次发生>

---

## 1. PowerShell 管道向原生程序传输中文被 GBK 重编码破坏

**发现时间**: 2026-09-20
**影响范围**: Windows PowerShell 5.1 下，任何把含中文的文本经管道 `|` 喂给原生程序（git / 数据库客户端 / cli）的场景
**症状**: `Get-Content file.txt -Raw -Encoding UTF8 | some-native-exe` 执行后，中文变成 `??` 或乱码；但直接读取文件内容显示正常
**根本原因**: PowerShell 把管道数据传给原生程序时，会按 `$OutputEncoding` / 控制台 OEM 代码页（中文系统为 GBK/936）重新编码字节流，UTF-8 的多字节中文被破坏。
**解决方案**:
- 会话内临时切换 UTF-8：`chcp 65001; $OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8`
- 避免用管道把中文喂给原生程序，改用「文件中转 + 程序自身读取」或参数传递
- 永久修复：Windows 设置开启 “Beta: 使用 Unicode UTF-8 提供全球语言支持”，或改用 Windows Terminal
**预防措施**: Windows 下处理含非 ASCII 数据时，一律用文件重定向（`< file` / `--result-file` / `-o file`），禁止用 PowerShell 管道 `|` 直接喂给原生客户端；处理后抽查中文字段。

---

## 2. git submodule / worktree 分支不同步导致提交丢失或指针错乱

**发现时间**: 2026-09-20
**影响范围**: 主控仓库 + `frontend/`、`backend/` 子模块的并行开发
**症状**: 主仓库切到 feature 分支后，子模块仍停留在 `main`（或 detached HEAD）；子模块内的提交未推送，主仓库记录的 submodule 指针指向本地未推送的 commit，他人 clone 后 `git submodule update` 失败
**根本原因**: `git submodule` 默认 checkout 固定 commit（detached HEAD），不跟随主仓库分支切换；worktree 也不会自动为子模块创建同名分支。
**解决方案**:
- 进入子模块开发前，显式创建/切换分支：`cd frontend; git checkout main; git pull; git checkout -b feature/<name>`
- 提交顺序：**先**在子模块内 commit + push，**再**回主仓库 `git add frontend backend; git commit`（记录已推送的指针）
- 推送顺序：先推子模块，后推主仓库
**预防措施**: 遵循 `.qoder/rules/workflow-conventions.md` 的子模块 / worktree 约束；每次操作后用 `git submodule status` 确认指针前缀非 `+`/`-`（`+` 表示子模块 checkout 与主仓库记录不一致，`-` 表示未初始化）。

---

## 3. Windows PowerShell 5.1 运行含中文的 UTF-8 无 BOM 脚本时解析报错

**发现时间**: 2026-09-21
**影响范围**: 仓库内所有含中文字符串 / 注释的 `.ps1` 脚本（如 `scripts/verify-structure.ps1`、`scripts/init-workspace.ps1`）在 Windows PowerShell 5.1 下的执行
**症状**: 脚本无法运行，抛出 `MissingEndCurlyBrace`（“缺少右 `}`”）或 “Try 语句缺少其自己的 Catch 或 Finally 块”，报错行号指向结构完整的 `try {` / `exit 0`，肉眼检查括号并无缺失
**根本原因**: Windows PowerShell 5.1 读取**无 BOM** 的 `.ps1` 时按系统 ANSI 代码页（中文系统为 GBK/936）解码；UTF-8 编码的中文字节被 GBK 误读，而 GBK 尾字节范围包含 `0x7B`/`0x7D`（即 `{`/`}`），会在字符串字面量中注入**游离的花括号**，破坏 `try{}` / `foreach{}` 的括号平衡，导致解析器中途报错。
**解决方案**:
- 将脚本重存为 **UTF-8 with BOM**，PowerShell 5.1 会据 BOM 正确识别为 UTF-8：
  `$c = Get-Content -Raw -Encoding UTF8 $p; [IO.File]::WriteAllText($p, $c, (New-Object Text.UTF8Encoding $true))`
- 或改用 PowerShell 7+（`pwsh`，默认按 UTF-8 读取脚本，无需 BOM）
**预防措施**: 本项目所有含中文的 `.ps1` 一律以 **UTF-8 with BOM** 保存；用会剥离 BOM 的编辑器 / 工具改写脚本后，必须重新执行 `scripts\verify-structure.ps1` 确认可解析（观察 `$LASTEXITCODE` 是否为 `0`，而非仅看中文是否乱码）。

---

## 4. OpenSpec CLI 升级会覆盖 opsx 命令 / 技能的中文翻译

**发现时间**: 2026-09-21
**影响范围**: `.qoder/commands/opsx/*.md`（6 个命令）与 `.qoder/skills/openspec-*/SKILL.md`（6 个技能），共 12 个文件
**症状**: 这些文件正文已中文化；一旦运行 `openspec update` 或重新 `openspec init --tools qoder`，它们会被英文原版重新生成，中文翻译全部丢失（`git diff` 显示整文件回退为英文）。
**根本原因**: 命令与技能文件是 OpenSpec CLI 的**生成物**，由 CLI 按版本模板写出，不感知本地的手工翻译；升级即覆盖。
**解决方案**:
- 升级 OpenSpec CLI 后，重新中文化这 12 个文件。翻译策略：仅译 frontmatter 的 `description` 与正文散文；逐字保留 `name` / `allowed-tools` / `license` / `metadata`、所有代码块、CLI 命令与参数、JSON 字段名、路径、占位符（`<...>`），以及规格 DSL 模板（`## ADDED/MODIFIED/REMOVED/RENAMED Requirements`、`### Requirement:`、`#### Scenario:`、`**WHEN**`/`**THEN**`、`## Purpose`、`## Requirements`）。
- “Store selection” 段、`"Using change: <name>"`、`"(Recommended)"` 等跨文件复用的固定串采用统一译法（沿用已中文化文件的既有用词）。
**预防措施**: 已在 `.qoder/skills/README.md` 第二节标注该覆盖风险；把 OpenSpec CLI 升级视为一次「需重新中文化」的维护动作，升级后先 `git diff --stat .qoder/commands/opsx .qoder/skills/openspec-*` 确认是否被覆盖，再决定重译。

---

## 5. 审批弹窗修改命令（modify）后端未消费，落远端的仍是提案原文

**发现时间**: 2026-09-22
**影响范围**: 审批链路 `ApprovalGate.modify` → AI 工具执行（`AiAgentService.runGated`）
**症状**: 用户在审批弹窗上修改命令后点批准，审计日志 `final_command` 已记录新版本，但 SSH 远端实际执行的是 AI 提案的原命令（端到端实测 `cat` 回读文件内容证实）
**根本原因**: `modify` 只写内存 Entry.modifiedCommand + 审计行；而 `decide()` 后 Entry 从 pending 移除，执行方 await 返回后拿到的局部变量 `command` 永远是提案原文，modifiedCommand 没有任何消费出口。
**解决方案**: 新增 `ApprovalGate.effectiveCommand(approvalId, fallback)`（内存 Entry 优先，已销毁则回读审计行 `final_command`，再回退原文）；`runGated` 批准后经其回读再执行。裁决后 `final_command` 不可变（claimed 拦截后续修改），审计行回读天然无竞态。
**预防措施**: 任何「后置修改 + 前置消费」的字段必须验证消费链路端到端存在（用 FakeSshServer.execCommands() 断言落远端的真实命令），不能只看写入侧成功。

---

## 6. /ws/approval 与 /ws/ai 是广播通道，多 tab 审批/AI 输出全端串台

**发现时间**: 2026-09-22
**影响范围**: 工作区多 tab（同一浏览器开多个 workspace）的审批弹窗、徽章、AI 流式输出
**症状**: 在 tab B 发起的高风险命令，审批弹窗同时出现在 tab A，两个 tab 徽章都 +1；AI 回答也可能写进非发起 tab 的终端
**根本原因**: 后端对 `/ws/approval`、`/ws/ai` 的所有连接推送全部帧（广播语义）；前端每条通道都收到全部帧且无归属过滤；叠加会话 ID 曾为全局单一 ref，多 tab 复用同一 conversation。
**解决方案**: 前端按契约中 required 的 `conversation_id` 做归属过滤（`msg.conversation_id !== ws.conversationId` 则丢弃）；会话改为每 tab 独立创建并持久化在 store 的 workspace 条目上；AI 流式标志/段落状态按 wsId 隔离。
**预防措施**: 接入任何新 WS 通道前先确认后端是广播还是按会话定向；广播通道的前端消费端 **必须** 带归属过滤（回归用例见 `WorkspaceView.spec.ts` 归属过滤段）。

---

## 7. 共享单例 xterm + 切 tab reset 缓冲区，审批留痕与用户输入被抹掉

**发现时间**: 2026-09-22
**影响范围**: 工作区多 tab 终端历史（命令留痕红线：命令无论是否执行都必须按时间顺序沉淀在 xterm）
**症状**: 审批挂起时切到其它 tab 再切回，该 tab 的用户输入回显、「$ 命令 ⏳待审批」留痕、AI 思考行全部消失，只剩切回之后新写入的内容
**根本原因**: 所有 tab 共享一个 TerminalTimeline/xterm 实例，靠 `watch(activeSessionId)` 里 `terminal.reset()` 隔离历史；reset 会清空整个 buffer，而后台 tab 的写入又被 isActive 过滤丢弃——历史既被抹掉又无处可存。
**解决方案**: 改为 per-tab 独立 TerminalTimeline 实例（WorkspaceView 按 workspaces `v-for` + `v-show` 切换，函数 ref 收集到 `timelineRefs` Map，写入统一经 `writeToWs(wsId, ...)`）；后台 tab 照常写自己的隐藏 buffer（xterm write 不依赖可见性）；切回时调新暴露的 `refit()`（fit + refresh）恢复尺寸。回归用例：「后台 tab 隔离回归」断言写入路由到所属实例。
**预防措施**: 多连接实例场景禁止共享带状态的渲染单例；「切换时 reset」等于丢数据，需用隔离实例而非时序清理。

---

## 8. SFTP listDir 未回填 mtime，文件站修改时间列全显示「-」

**发现时间**: 2026-09-22
**影响范围**: `/api/sessions/{id}/files` 响应与前端文件站「修改时间」列
**症状**: 目录/文件的 mtime 全为 null，UI 上「-」；size 正常
**根本原因**: `SftpService.toFileEntry` 从未调用 `setMtime`（文件曾因环境事故重建丢失该字段）；SSHJ readdir attrs 在 OpenSSH 服务器实际携带完整属性。
**解决方案**: `toFileEntry` 补 `attrs.getMtime() > 0` 时转 `OffsetDateTime`（UTC epoch 秒）回填。
**预防措施**:  DTO 映射函数改动后抽查「每个目标字段是否有真实值」，用 API 响应取证而非只验 200。

---

## 9. 沙箱内 Get-NetTCPConnection 看不到宿主机监听，重启服务误判成功

**发现时间**: 2026-09-22
**影响范围**: Windows 下用沙箱 shell 重启/验证常驻服务（后端 spring-boot:run）
**症状**: 重启脚本报「端口无监听 → 启动成功」，实际旧进程仍存活，新代码未生效（浏览器复测行为与旧版一致）
**根本原因**: 沙箱环境的 `Get-NetTCPConnection`/`Test-NetConnection` 存在宿主机进程盲区（误报 no-listener）；另外 PowerShell 5.1 会把 mvnw 的 `-Dxxx=yyy` 裸参数拆成 lifecycle phase 报错，导致新进程根本没起来。
**解决方案**: 用 `netstat -ano`（需宿主机权限）确认真实监听与 PID，`taskkill /F /PID` 杀旧进程；`-D` 参数整体用引号包住：`.\mvnw.cmd spring-boot:run "-Dspring-boot.run.jvmArguments=-Dfile.encoding=UTF-8"`。
**预防措施**: 重启服务后必须验证 **PID 变化 + 日志 Started 行**，两者缺一不视为重启成功；行为差异（端到端复测）是最强证据。

---

## 10. chrome-devtools take_screenshot 频繁超时，用 a11y 快照 + DOM 度量替代取证

**发现时间**: 2026-09-22
**影响范围**: 浏览器端到端验证的视觉取证环节
**症状**: `take_screenshot`（png/jpeg/webp、inline/filePath）多次调用返回 40504 超时；filePath 模式还可能因 workspace roots 配置拒绝合法路径
**根本原因**: 截图通道对大页面/低质量参数仍不稳定，疑与 CDP 截图往返超时配置有关（偶发可用，不可依赖）
**解决方案**: 取证改用 `take_snapshot`（a11y 树结构确认）+ `evaluate_script` 轮询断言（getBoundingClientRect/scrollWidth/computedStyle 做布局度量，buffer 行文本做内容断言）；xterm 内容读 `.xterm-rows > div` 逐行 textContent。
**预防措施**: 浏览器验证优先写「断言型」脚本（返回布尔+关键数据）而非依赖截图；截图作为可选补充、失败不阻塞流程。

---

## 11. 审批链断链 sessionId：获准命令与只读工具回落 exec，Shell 的 cwd/env 不继承

**发现时间**: 2026-09-22
**影响范围**: Shell → Agent 状态交接（design D3：所有 Agent 远端工具经同一持久 Shell 执行）；审批后命令输出不再回流终端
**症状**: 用户在 Shell 模式 `cd /var/log && touch marker` 后切 Agent 提问，AI 提案 `pwd && ls marker` 批准执行后回答「当前目录 /root、文件不存在」，且终端看不到命令输出回流
**根本原因**: 能力层早已就绪（`ApprovedCommandRunner.run(..., sessionId)` 4 参重载 + `AgentTools` 读 `CTX_SESSION_ID`），但路由信息链路上三处断裂：`TurnRequest` 没有 sessionId 字段 → `AiWebSocketHandler` 接到带 `session_id` 的帧无处可存 → `runTurn` 构造的 toolContext 不含 `CTX_SESSION_ID` → `runGated` 只能调 3 参 `runner.run`（sessionId=null 回落 exec）；前端 `sendAiMessage` 也从未带 `session_id`。组件各自正确，接缝全错。
**解决方案**: 端到端接通链路——`TurnRequest` 加 `@Nullable UUID sessionId`（保留 3 参兼容构造器）；handler 透传 `frame.sessionId()`；`AiAgentService` 用 `buildToolContext` 注入 `CTX_SESSION_ID`，`runGated` 增 toolContext 参改调 4 参 `runner.run`；前端 `user_message` 载荷带 `session_id: ws.sessionId`。回归用例：`approvedCommandIsRoutedThroughSharedPty` / `readOnlyToolIsRoutedThroughSharedPty`（mock PtyCommandGateway 断言 submit 被调且 exec 通道零增量）。
**预防措施**: 跨层路由字段（新增契约字段 → 前端发送 → handler 解析 → service 透传 → 执行层消费）必须在同一变更里端到端接通并各有一道断言；只实现能力层（重载/工具读 context）不算完成，验收时 MUST 含「在用户 Shell 里 cd 后 Agent 命令能看到该目录」这类交接实测。

## 12. Shell 集成组件全绿但从未接线：scheduler 恒为 null，PTY 路径永久回落 exec

**发现时间**: 2026-09-22
**影响范围**: 修复 #11 第一段链路后，获准命令仍走 exec 通道，cwd/env 依旧不继承；日志取证 `PTY 路径不可用，回落 exec 通道`
**根本原因**: 5.x 组件（ShellIntegration / ShellFrameDecoder / PtyCommandScheduler / PtyCommandGateway）单测全绿，但主代码**零处**调用 `setScheduler()` / `new ShellIntegration(...)`——运行时 `runtime.scheduler()` 恒为 null，gateway 抛「会话未安装 Shell 集成」后永远回落。与 #11 同源教训：组件各自正确，接缝全错；「类存在且测试绿」不等于「被装配」。
**解决方案**: 新建 `ShellIntegrationInstaller.install()` 静态接线（构造集成→包装输出监听器剥帧/采集→返回 scheduler + 包装 listener）；`SshTerminalService.open()` 用 `RelayOutputListener`（volatile target）解「createTerminal 先要 listener、包装要先有 terminal」的鸡生蛋问题，安装失败 catch 降级人工终端；`PtyCommandScheduler.handlePrompt` 补 busy→idle 恢复路径（人工命令结束后 PROMPT 帧是唯一证据，无此路径则永久 busy 拒掉所有获准命令）；`TerminalWebSocketHandler.forward` 在用户真实键入时调 `onManualBusy()`；`SshProperties.shellType` 新增配置（默认 bash，第一阶段仅支持 Bash 4+）。
**预防措施**: ①接线类改动的回归验收必须包含「grep 主代码确认装配点存在」；②非 bash 的测试替身（FakeSshServer）必须把 `shellType` 配成非 bash，否则钩子安装代码被远端当命令逐行回显 `command not found`，污染 open 回执帧的顺序断言（`install()` 对不支持类型不向 PTY 写任何字节，降级行为由 `ShellIntegrationInstallerTest` 覆盖）。

## 13. Bash 集成安装代码用子 shell `( ... )` 包裹：钩子设置在父交互 shell 全部丢失，调度器永久 MANUAL_BUSY

**发现时间**: 2026-09-23（接线修复后浏览器终验，known-issues #12 的后续层）
**影响范围**: 获批命令与只读工具仍被拒/回落 exec——日志铁证 `当前状态 MANUAL_BUSY 不接受命令提交` + `PTY 路径不可用，回落 exec 通道`；远端真实 bash 环境下 PROMPT/CWD 帧一次都未出现
**根本原因**: `ShellIntegration.generateBashIntegrationCode` 用 `( ... )` 子 shell 包裹安装语句（原始动机是「防止安装过程触发 DEBUG trap」）——但 bash 会为子 shell 新建进程，内部的 `PROMPT_COMMAND=...`/`trap ... DEBUG` 随子 shell 退出丢失，父交互 shell 从未挂上钩子。单测盲区：所有组件测试只断言生成代码**包含**某些子串，从不验证「在真实 shell 中是否生效」；端到端测试手喂帧绕过了安装代码本身。日志中 `Frame has too few fields: 0;root@localhost:~` 其实是 CentOS PS1 的 OSC 0 窗口标题序列被 decoder 正常丢弃，属噪声而非帧格式 bug。
**解决方案**: 改用花括号组命令 `{ ... }`（在当前 shell 内执行，设置真实生效）；安装语句先于 trap 设置完成，无 DEBUG 触发风暴风险；新增回归用例 `integrationCodeAppliesToCurrentShellNotSubshell` 断言首尾行必须是 `{`/`}` 而非 `(`。
**预防措施**: 约束远端 shell 的生成代码，验收 MUST 包含「代码在当前交互 shell 生效」的结构性断言（组命令 vs 子 shell、变量作用域回写），不能只做子串包含式断言；关键闭环（如 busy→idle 恢复）必须有真实环境的端到端冒烟（浏览器/测试服务器），单测全绿不代表接缝成立。

---

## 14. 首次连接终端刷屏安装代码回显：tty ECHO 在字节到达瞬间回显，与后续执行无关

**发现时间**: 2026-09-23（#13 修复后浏览器终验，用户附截图反馈「每次第一次连接都会打印这些东西」）
**影响范围**: 所有 Bash 会话建立（open 接线）时的用户视觉体验；多行安装代码还触发 readline `>` 续行提示
**根本原因**: 两层叠加。①tty 的 ECHO 由驱动在字节到达瞬间实时处理，bash 尚未执行就无法取消；把 `stty -echo` 与安装代码合并同一次写入仍会被回显（字节已进 tty 线缓冲）。且 `>` 续行提示由 bash 进程自己打印，与 echo 开关无关——多行代码即使静默回显也会留下满屏 `>`。②（后补，真根因）生成的钩子代码里 printf 写成四反斜杠源码（Java 字符串值 = bash 代码中的 `'\\033]'`），bash printf 把 `\\` 解释为**字面反斜杠**，输出的是文本 `\033]1337;...` 而非真实 ESC(0x1B) 字节——于是 ShellFrameDecoder 永远收不到帧（服务端闸门只能靠 5s 兜底开→首连白屏「连接中...」）、字面帧文本剥不掉直接泄漏到用户屏幕（用户截图投诉的正是这个）。此前单测全绿是因为测试直接喂 `\u001B` 真实 ESC 给 decoder，从未验证**生成代码的转义层级**。
**解决方案**: ①三段式静默安装（`ShellIntegration.install()`）：先单独发 `stty -echo\n` 并有限等待其执行（250ms），再写安装代码，最后 `stty echo\n`；同时 `generateBashIntegrationCode` 把钩子设置压缩为**单行**（拼接规则：上行尾为 `{`/`then`/`else` 用空格，其余用 `; `）。②服务端输出闸门（`ShellIntegrationInstaller`）：先经 `relay::switchTo` 回调把输出链切到闸门再写安装代码，吞掉首个有效 1337 帧前的一切转发（含 readline 回显），5s 兜底强制开闸。③printf 转义修正为源码双反斜杠（Java 字符串值 = bash 代码单反斜杠 `\033`，printf 正确产出 ESC 字节）。回归用例：`installSilencesPtyEchoAroundIntegrationCode`（三次独立写入）、`integrationCodeIsSingleLine`、`framePrintfUsesSingleBackslashEscape`（锁转义层级：contains `printf '\033]1337;` + 禁止 `'\\033]` 形态）。
**预防措施**: ①向真实 tty 写多字符序列前区分三层回显机制：驱动 ECHO（字节到达即回显）/ readline 续行提示（bash 进程打印）/ 程序自输出；静默只能控制第二三层，第一层必须先终止其生效再写正文。②凡「Java 字符串 → 生成 shell 代码 → shell 解释器再解析」的多层转义链，测试必须断言**生成代码文本本身**的转义形态，而不能只喂最终期望字节给消费者；必要时在真实终端做端到端冒烟。③编辑含反斜杠+引号逃逸的 Java 源行时 SearchReplace 有损（多次破坏 `\"`），须用 PowerShell 字节级重写并以 `-replace '\\','!'` 校准显示。对远端 shell 的生成代码验收必须包含「在真实终端观察无噪声」的端到端冒烟，不能只看字节序列断言。

## 15. 会话终结后 sessionId 残留：输入持续路由到死会话造成错误风暴，且无重连入口

**发现时间**: 2026-09-23（浏览器终验：硬刷新后活动终端 152 行「[错误] 终端会话不存在或已结束」刷屏）
**影响范围**: 空闲回收/远端关闭/后端重启后的前端体验；断线后功能死路（无任何重连路径）
**根本原因**: 三处叠加——①`WorkspaceView` 收到 closed 帧或 WS onclose 后只改状态不清 `sessionId`，`handleShellInput` 的 guard（`ws.sessionId && channel.connected`）仍放行，字节继续带死会话 id 发送，后端 `requireOwn` 逐帧回错；②会话 id 采纳逻辑 `if (msg.session_id && !state.sessionId)` 只认第一个 id，即使重连成功新会话 id 也被丢弃；③`onStateChange` 回调参数名 `state` 遮蔽外层 `state` 闭包，无法清理已采纳 id；④产品层面缺少断线重连入口（对标 MobaXterm 按 r / FinalShell 按钮）。
**解决方案**: closed 帧与 WS disconnected 两条路径同构处理：清 runtime/store 的 sessionId + 置终态 + 写重连指引行；会话 id 改为恒更新（`msg.session_id !== runtime.sessionId` 即采纳并置 connected）；新增 `TerminalTimeline.disconnected` prop 拦截 r/R 键 emit reconnect（其余输入丢弃），`WorkspaceView.reconnectWorkspace()` 双路径：通道仍连→直发 open，通道已断→connect() 后由状态回调自动补 open；工具栏终态才显示「重连」按钮。故意**不做自动重连**：会话重建丢 cwd/运行中程序，上下文切换必须用户显式确认。回归：`WorkspaceView.spec.ts` 断线重连 4 用例 + `TerminalTimeline.spec.ts` 拦截 4 用例。
**预防措施**: 任何「标识符生命周期小于通道生命周期」的字段（会话 id/令牌），其失效事件（closed/onclose/error 终态）处理必项包含：清空失效值 + guard 拦截后续使用 + 用户可见的恢复入口；错误刷屏类用户反馈先取证「哪个旧 id 还在被使用」，而不是先改文案。

## 16. 切换页面卸载 WorkspaceView 销毁全部终端运行时：回跳后历史与 cwd 全丢

**发现时间**: 2026-09-23（浏览器终验：cd 后切到设置页再回跳，终端空白且会话重建）
**影响范围**: 工作区 ↔ 服务器列表/设置页任意导航往返；所有已连 tab 的终端历史、cwd、运行中程序
**症状**: 回跳 workspace 后原有 tab 终端变空白，重新自动建立全新 shell（cwd 回到登录目录），用户输入历史与远端进程全部丢失
**根本原因**: `runtimeMap`/`timelineRefs` 定义在 `<script setup>` 内 = **组件实例级**状态；vue-router 切页默认卸载组件，触发 `onBeforeUnmount` 销毁全部 WS 运行时，后端按 USER_DISCONNECT 回收会话。之前修过的“切 tab 丢历史”（#7）只覆盖了 tab 切换，未覆盖**路由切换**这一层。
**解决方案**: App.vue 的 `<router-view>` 改 `v-slot` + `<KeepAlive :include="['WorkspaceView']">` 包裹；WorkspaceView 加 `defineOptions({ name: 'WorkspaceView' })`（include 按 name 匹配）；`onActivated` 里对活动 tab 调 `refit()` 恢复尺寸。回归：App.spec KeepAlive 用例（需经 VTU `global.components.RouterView` 注册 stub 并传 slot props，vi.mock 导出对象不解析模板 kebab 组件）+ WorkspaceView.spec name 断言。
**预防措施**: 持有长连接/不可序列化运行时（xterm、WS、定时器）的视图，必须在设计期就回答“路由切走时这些状态去哪里”；单例 store 存了元数据不够，组件实例级 Map 同样会被卸载销毁。测试 VTU 挂载含 `<router-view>` 插槽的组件时，stub 必须经 `global.components` 注册而非只改模块导出。

## 17. Agent 不知道用户终端当前目录：人工 cd 的 CWD 帧被丢弃，提示词无 cwd 注入，“当前目录”全答 /

**发现时间**: 2026-09-23（浏览器终验：cd /tmp/acceptance 后问“列出当前目录文件”，AI 回答“当前目录 /”；日志铁证 `list_dir: path=/`）
**影响范围**: Agent 模式所有带“当前目录/这个目录”语义的提问；list_dir/read_file 默认路径推断
**根本原因**: 两层断链叠加——①`PtyCommandScheduler.handleCwd` 只在 `currentCommand != null` 时记录 lastCwd（Agent 命令结果），人工 cd 产生的 cmdId=0 CWD 帧被直接丢弃，会话级 cwd 无处可查；②`AgentSystemPrompt.build` 根本没有 cwd 参数，模型只能凭默认猜测 /。与 #11/#12 同源教训：帧链路本身工作（OSC title 日志证明钩子在发帧），但消费端只服务了 Agent 命令自己的那一层。
**解决方案**: ①scheduler 加 `volatile sessionCwd`，handleCwd **无条件**更新（人工与 Agent 帧都是真实状态）+ getter；②`AgentTools.sessionCwdOf(sessionId)` 经现有 `ptyGateway.findScheduler` 查找链取 cwd（无网关/未命中安全返回 null）；③`AgentSystemPrompt.build` 加 4 参重载（cwd 非空白才渲染“当前工作目录”段，未知不渲染避免空路径误导），3 参委托保持既有调用兼容；④`AiAgentService` 存 agentTools 字段，runTurn 与上下文恢复重建提示词两处都注入（恢复路径经 `sessionCwdOfContext(toolContext)` 与首轮共用 sessionId 来源）。回归：`manualCwdFrameUpdatesSessionCwd` / `promptInjectsSessionCwdWhenKnown` / `promptOmitsCwdSectionWhenUnknown` / `sessionCwdOfRoutesToTheSessionScheduler`。
**预防措施**: 凡是“用户动作产生的状态帧”（cd/export/环境变更），消费端不能只服务“系统自己发起的命令”那一层；向模型注入环境上下文时，未知值必须**不渲染**而非给空串，否则模型会把空路径当事实。

## 18. KeepAlive 切页后 lastActiveId 被回退值污染：侧栏回跳落到首个 tab 而非离开前的 tab

**发现时间**: 2026-09-23（浏览器终验：ws-2 活跃时切设置页再点侧栏「工作区」，回跳到 ws-1）
**影响范围**: 多 tab 工作区 + 任意跨页导航往返；侧栏「工作区」回跳入口
**根本原因**: #16 引入 KeepAlive 的次生问题 —— 缓存的 WorkspaceView 内 `watch(effectiveActiveId)` 不随离开路由而停；路由切到 /settings 后 `route.params.workspaceId` 变 undefined，`effectiveActiveId` 的「参数不匹配回退首个 tab」分支返回 ws-1，watcher 把回退值当成真实活跃 tab 登记进 `setLastActive`，覆盖掉 ws-2。登记侧未区分「回退」与「真在看」。
**解决方案**: 登记守卫 `if (id && routeWorkspaceId.value)`：仅当前确实停在 /workspace/:id 路由（参数非空）才登记；参数无效但停在 workspace 页时仍登记回退的首 tab（保留原意）。回归：WorkspaceView.spec 新增「离开 workspace 路由不得覆盖 lastActiveId」（需把 vue-router mock 的 useRoute 改为共享 reactive 对象才能触发 computed 重算）；浏览器双向复验（ws-2 往返、切 ws-1 后往返均正确）。
**预防措施**: 给 KeepAlive 缓存组件内「从路由派生的状态登记」加守卫前，先问：路由离开时这个派生值会变成什么？回退默认值与真实状态同名时（都是“首个 tab id”），必须在登记入口用路由在位性区分，而不是靠消费端事后过滤。

## 19. 首连同一行出现两个提示符：三段式静默安装分次发送，开闸后每条命令各弹一个 prompt（附带修复：登录 banner 竞态泄漏）

**发现时间**: 2026-09-23（用户浏览器实测：首次连接终端显示 `[root@localhost ~]# [root@localhost ~]#`，后续连接正常）
**影响范围**: 所有 bash 会话首连必现双 prompt；登录 banner 泄漏为概率性竞态（首连握手最慢时命中）
**根本原因（真根因，浏览器 xterm buffer 取证实证）**: `ShellIntegration.install()` 旧三段式分次发送（`stty -echo\n` → sleep → 钩子 code\n → sleep → `stty echo\n`）。钩子 code 执行完 PROMPT_COMMAND 弹出**首个提示帧**→ 服务端闸门开闸 + prompt ① 放行；随后 `stty echo` 又是一条命令、bash 执行完再弹 prompt ②——两个 prompt 都在开闸后送达，同一行双提示符。stty 两行的 readline 回显发生在首帧前被闸门吞掉，所以看不到命令文本。「后续连接正常」是旧观察偏差（同一逻辑每条连接都在跑）。（排查插曲：第一层假设曾锁定为“登录 prompt 抢在闸门 `switchTo(gate)` 接入前经原监听器泄漏的竞态窗口”——该窗口确实存在且已修，但修复后浏览器实测 buffer 仍是 2 个 prompt 且**无 Last login banner**，恰铁证登录输出从未泄漏、它不是双 prompt 成因。）
**解决方案**: ①（双 prompt 真修复）`ShellIntegration.install()` 合并为**单条命令行**一次性发送：`stty -echo; {钩子code}; stty echo\n` —— 整行只触发一次 PROMPT_COMMAND → 恰好一个 prompt；回显抑制语义保留在同一行内（行首 stty -echo、行尾 stty echo）。回归：`ShellIntegrationTest.installSendsHooksAsSingleCommandLine`（hasSize(1) + 单行断言）。②（竞态防御保留）新增 `PreInstallMuteListener`（吞 stdout/stderr、**透传 onClosed**）：bash 会话作为 relay 初始监听器，把保护起点提前到第一个字节，封死登录 banner/首 prompt 抢在闸门接入前泄漏的窗口；`installShellIntegration` 的 catch 补 `relay.switchTo(listener)` 兜底，防安装异常把终端永久静音；非 bash 不装静音（banner 照常透传）。回归：`PreInstallMuteListenerTest` 2 用例 + `SshTerminalServiceTest` banner 集成 2 用例（FakeSshServer 新增可注入 loginBanner）。
**预防措施**: ①向同一 PTY 分次写入多条命令行，每条都会触发一次 PROMPT_COMMAND/提示帧——凡“安装/配置序列”都应与钩子代码合并为单行一次发送，而不是依赖 sleep 拼时序。②任何“先透传、后切保护链”的输出接线都有启动竞态窗口，治理点是让初始链就是保护链（默认拒绝），而不是指望“切得够快”。③测试替身若只在输入后出字节，永远测不出“启动即输出”类竞态，需可注入的启动期主动输出（loginBanner 同法）。④假设必须被实验证伪前不得回写文档为“根因”——本条第一层假设通过了单测与全量回归，却在浏览器实证中被打脸，xterm 内存 buffer 取证（promptCount + 有无 banner 行）才是终判。

## 20. Agent 回合无法 Ctrl+C 打断：后端 stop() 死代码零调用，五层链路全断

**发现时间**: 2026-09-23（用户反馈：Agent 对话中按 Ctrl+C 不能像 Shell 一样打断正在跑的程序）
**影响范围**: Agent 模式所有长回合（多轮工具循环/大模型慢响应）用户只能干等，无逃生口
**根本原因**: 五层断链叠加——①契约层：`asyncapi.yaml` 的 AiStreamType 没有任何停止上行类型，前端无处可发；②后端入口层：`AiWebSocketHandler.handleTextMessage` 只认 `user_message`，其余帧直接丢弃；`AiAgentService.stop(UUID)`（中断 worker → InterruptedException → final+停止注记）自实现以来**零调用**，是潜伏死代码；③前端层：Agent 模式 Ctrl+C（`\x03`）只被 `handleAgentKey` 当作“取消输入草稿”，从不区分回合是否在飞；④异常包装层（接通后浏览器实测新暴露）：stop() 确实中断了 worker（日志铁证），但 langchain4j 阻塞流式读把 InterruptedException 包成 `ReactiveException`（RuntimeException 子类）抛出，`runTurn` 的 `catch (InterruptedException)` 分支永远接不到，掉进 `catch (RuntimeException)` 被误分类成 `model_endpoint_error`——用户 Ctrl+C 瞬间看到的不是停止注记而是红字报错；⑤中断标志残留层（第四层修复后 run9 实测再暴露）：reactor 抛出包装异常时会**恢复线程中断标志**，而收尾 `finishWithNote` 的帧发送（Tomcat WS blocking send）就跑在同一被标志污染的 worker 线程上——第一帧发送即失败、连接 1006，停止注记**永远发不出**；旧设计“复位统一由后端 final 帧承担”在“中断自身杀死传输链”的场景下不成立。与 #11/#12/#17 同源教训：能力模块已存在但没接线，单测各测各层永远全绿，接缝处无人验证。
**解决方案**: 五层全部接通：①契约新增上行 `stop_turn`；②`AiStreamFrame.Type` 枚举**末尾**加 `STOP_TURN`（避免中间插入移动 ordinal），handler 新增 `handleStopTurn`（缺 conversation_id 忽略；未命中在飞回合静默——停止是幂等通知，不返错误帧）；③`ws-messages.ts` 加 `StopTurn`；`TerminalTimeline` 新增 `generating` prop，生成态 Ctrl+C 写 `^C` 留痕 + emit `agentStop`；④`runTurn` 的 `catch (RuntimeException)` 顶部加 `causedByInterrupt(e)` cause 链识别（与 classify 同风格自引用/深度守卫），命中则走 `finishWithNote(STOPPED_NOTE, "stopped")` 而非错误帧；⑤后端两处 catch 分支收尾前用 `Thread.interrupted()` **清除**中断标志（取代反模式的 `Thread.currentThread().interrupt()` 恢复标志：收尾帧发送就跑在本线程，标志残留让第一帧即失败；DB 落库必成、帧发送尽力而为），前端 `WorkspaceView.stopAgentTurn` 改为**本地闭环**：发帧后立即清生成态 + 写停止注记行，不等后端收尾帧（丢帧不可接受，双份注记可接受；后端若送达对已复位状态幂等）。回归：`AiWebSocketHandlerTest` 4 用例（手写 JSON 字符串验契约线上键名）+ `AiAgentServiceTest.interruptWrappedInRuntimeExceptionFinishesWithStopNoteNotError` / `stopCleanupRunsOnInterruptFreeThread`（后者首版把断言写在 finally 后自己把泄漏证据擦掉——假绿，修正为 try 内捕获 `leaked` 后再断言）+ 前端 WorkspaceView 本地闭环用例；需求回写 ai-agent spec「受控停止任务」Ctrl+C Scenario（本地闭环语义）+ tasks 17.10。
**预防措施**: ①写完服务能力（stop/cancel/清理事务）必须同步接上至少一个真实触发入口，否则它就是死代码——用“入口存在性检查”收口：契约有下行能力就得有对应上行触发帧；②“中断/取消”类命令应设计为幂等通知：未命中目标时静默成功而非报错，避免竞态窗口（恰在收尾时按 Ctrl+C）把错误噪声抛给用户；③“状态复位由单一真相源（后端帧）驱动”的设计必须前提性回答“真相源帧是否保证送达”——当取消手段（interrupt/关连接）本身可能破坏发送通道时，发起方必须有本地闭环兜底，并对可能的双份送达做幂等兼容；④凡按异常类型分支的取消/中断语义，必须同时识别**被框架包装的** InterruptedException（cause 链遍历），因为阻塞式流读（langchain4j/reactor）从不裸抛；日志里“命中在飞回合=true”但用户看到报错帧，就是这种“入口接了、异常分支没接”的典型指纹；⑤线程中断标志是“远处副作用”：捕获包装异常的线程仍带标志继续执行收尾代码，后续任何阻塞 IO（WS blocking send、JDBC、写文件）可能立即失败——catch 中断类异常后跑阻塞收尾前，必须显式决策 `Thread.interrupted()` 清标志还是 `Thread.currentThread().interrupt()` 恢复标志，并把决策理由写进注释。

## 21. 长时安装命令被 60s 绝对超时误杀：调度器把“总时长上限”错当“无输出上限”，正常执行中的 yum 被 Ctrl-C

**发现时间**: 2026-09-23（用户反馈：让 Agent 安装 JDK，实际还在安装但因时间太长被自动打断）
**影响范围**: Agent 模式所有超过 `run_command.timeout.seconds`（默认 60s）的正常长任务：装包、编译、大文件拷贝；Shell 模式不受影响（直连不经调度器）
**根本原因**: `PtyCommandScheduler.dispatchCommand` 把超时实现为一次性 `schedule(this::onTimeout, timeoutMs)` 绝对定时器：到时无条件 `send(CTRL_C)`，不看命令是否在持续输出。“超时”的真实意图是“卡住没反应该打断”，但实现成了“跑太久就杀掉”；而等待方（`ApprovedCommandRunner.tryPtyPath` / `AgentTools.tryPtyPath`）的 `future.get` 又各自拿同一个 settings 超时做第二层绝对等待，双层叠加持旧语义。与 #20 同族：能力参数（timeout 设置项）被接进了错误的语义位置。
**解决方案**: 超时改双维语义：①**空闲超时**：`PendingCommand` 新增 `dispatchedNanos/lastActivityNanos`，`collectOutput`（AGENT_OWNED 分支）与 `onFrame` 刷新活动打点；`onTimeout` 改 watchdog：idle 与 elapsed 均未超限则按 `min(timeout-idle, maxAbs-elapsed)` 续排（+20ms 防自旋），只有真空闲超限才发 Ctrl-C；②**绝对上限兜底** `DEFAULT_MAX_ABSOLUTE_MS = 30min`（新 6 参构造器可注入，5 参委托默认）防无限输出型命令跑飞永久占住输入权；③等待方对齐：新增静态 `ptyWaitCeilingSeconds(settingsTimeout) = max(settings, 1800+10)`，两处 `future.get` 改用它——等待上限 MUST 晚于调度器中断，否则等得早的一方会拿不到结果误回落 exec 重跑（与 #22 交叉）。回归：`PtyCommandSchedulerTest` activeOutputExtendsTimeout / absoluteCapInterruptsEvenIfActive / ptyWaitCeilingCoversAbsoluteCap；浏览器终验：Agent 执行 80 次连续输出的 tick 循环完整跑完（旧实现 60s 必杀），final 为 STOP 且模型拿到 tick-80。
**预防措施**: ①“超时”类参数先定义清楚它限的是什么：总时长还是无进展时长；对“持续有输出的长任务”两者必须分开（空闲超时 + 绝对上限兜底是交互式终端命令的通用做法，MobaXterm/SecureCRT 同款）；②多层都有同一个超时参数时，必须画出“谁先断谁”的序关系：内层（执行）先断、外层（等待）晚断，否则外层提前拿不到结果就会走错误回落；③中断手段（Ctrl-C）的触发条件要携带证据（timedOut 标志 + 观察窗口），不能只凭定时器到点就断定命令卡死。

## 22. 工具阶段停止被吞成“PTY 不可用”：回落 exec 把同一条命令重跑，Agent 怎么按 Ctrl+C 都停不下来

**发现时间**: 2026-09-23（用户反馈：agent 输出时无法中途打断，它始终会按上一步输出分析执行命令直到把任务跑完）
**影响范围**: Agent 模式工具执行（只读工具/已批准命令）阶段的所有停止操作；#20 修的是“模型流式读阶段能停了”，本条是剩下的工具阶段
**根本原因**: 三个吞点串成断链，每个单看都“合理”：①`ApprovedCommandRunner.tryPtyPath` 的 `catch (InterruptedException) { return null; }`——注释写“回落”，于是 stop() 的 interrupt 被当成“PTY 通道坏了”，同一条已批准命令经 exec 通道**重跑一遍**；②`AgentTools.tryPtyPath` 抛普通 `RuntimeException("中断")` 撞上 `executeOrReturnError` 的 `catch (RuntimeException)` “PTY 路径不可用回落 exec”——同一个回落模式；③`AiAgentService.runReadOnly` 把任何 RuntimeException 伪装成 `tool_result(ERROR)` 回喂模型——模型收到“执行失败”就接着分析另想办法，表现为“停不下来”。另缺最后一环：stop() 只 interrupt 本地等待线程，远端 PTY 上正在跑的命令（安装中的进程）从未收到 Ctrl-C。测试为什么没发现：RED 初版断言“execCommands 为空”在现实现下竟直接绿——测试替身环境下 exec 回落在命令发送前就被中断标志拦住，真实环境却会重跑；“停止不得伪装成工具失败”这个帧层断言（TOOL_RESULT 不存在）才是稳定可观测的吞点痕迹。
**解决方案**: ①新增 `support/TurnCancelledException`（RuntimeException，cause 约定为 InterruptedException；类型本身即“用户停止”标记）；②两处吞点透传：runner 的 catch(InterruptedException) 改抛 TurnCancelled（禁 return null 回落）；AgentTools 的 catch(RuntimeException) 前加 `catch (TurnCancelledException e) { throw e; }`；`runReadOnly` 的 catch 先 `causedByInterrupt(e)` 识别（含被 Spring callback 框架包装的）再重抛；③`causedByInterrupt` 扩展为 `instanceof InterruptedException || instanceof TurnCancelledException`（权威标志抛的实例无 interrupt 源）；④**权威停止标志** `stopRequested`（集合，不依赖线程标志）：stop() 命中在飞回合时置位、submit 的 finally 清除；检查点布在轮首/工具间/流式增量三处，任何一层把异常吞成普通失败都兜得住；⑤stop() 接远端打断：`runTurn` 登记 `inFlightSession`（conversation→session），stop() 经 `AgentTools.interruptInFlightCommand` → `findScheduler().interruptCurrent()`（BUG-A 同步实现的 Ctrl-C+观察窗口机制）向远端发 Ctrl-C。回归：`AiAgentServiceTest` 3 用例（只读/已批准路径禁回落+TOOL_RESULT 不得出现、stop 经调度器 interruptCurrent）；浏览器终验：300-tick 循环执行中按 Ctrl+C → stop_turn 上行 → 远端 `^C` 回显（tick2-87 处截断）→ 停止注记 → 终端 5s 稳定无后续输出。
**预防措施**: ①catch 后“回落另一条通道”的降级逻辑，MUST 先排除“取消/中断”类异常——取消不是通道故障，降级重跑等于把用户刚取消的事又做一遍；②“停止”类语义要有不依赖异常传播的兜底信号（权威标志/世代号）：异常每穿一层就被包装/吞掉一次，只有每层都写对才生效，而标志在任何检查点都可单独生效；③验证“不得发生 X”的 RED 断言，选在现实现下**必然红**的可观测量（帧/调用/审计），而不是受环境影响的执行结果（本条初版 exec 命令数断言在测试替身下假绿）；④本地 interrupt 只解决“不等了”，远端副作用（正在跑的进程）需要显式控制帧（Ctrl-C）才能停，两层缺一层都是“停不下来”。

## 23. Shell 模式方向键调历史把 xterm 渲染全乱：后端 PTY 永远 80x24，前端从未同步过 winsize

**发现时间**: 2026-09-22（用户反馈：切回 Shell 模式按上下键显示之前的指令时 xterm 渲染全部错乱，要求参照成熟 SSH 客户端实现）
**影响范围**: 所有终端会话：长命令折行错乱、readline 行编辑（方向键/Home/End）跨行乱跳、resize 窗口后远端排版与真实列数不符；表面看是“方向键 bug”，实际任何超过 80 列的命令都会埋下错乱
**根本原因**: 后端 `SshTerminalService.allocatePTY` 固定按 80x24 分配，WS 协议的 resize 链路（handler.resize → `SshTerminalSession.resize` → `changeWindowDimensions` 触发 SIGWINCH）完好但前端 `TerminalTimeline` 从头到尾**没有一处 emit resize**：xterm 用 fit 适配了容器真实尺寸，远端 PTY 却永远按 80 列排版。readline 类行编辑靠终端几何重绘：远端按 80 列算光标、本地按真实列数渲染，上调历史时一条超过 80 列的旧命令（如本会话反复用的长 yum/echo 命令）两边折行位置不一致，重绘叠加就把整屏搅乱。与 #11/#12 同族：链路两头各自正确、接缝从未接上，单测永远测不出“前端不发帧”。
**解决方案**: 参照成熟客户端（MobaXterm/PuTTY 连接即同步、切回即校验）的做法，前端统一尺寸上报：①`TerminalTimeline` 新增 `syncSize(force)`：`proposeDimensions()` 守卫（容器隐藏/零尺寸时 fit 是 no-op，旧 cols/rows 还是默认 80x24，若照常 emit 会把远端错误重置）→ fit → 与 lastSyncedCols/Rows 去重 → emit resize；挂载、window resize、ResizeObserver（侧边栏/弹窗等容器尺寸变化不触发 window 事件）都走非 force；②首帧时机：WS 未就绪时帧被父级丢弃，故 `WorkspaceView` 在 session_id 被采纳时（首连/重连同一路径）`nextTick(() => timelineRefs.get(wsId)?.refit())` 驱动一次 force 补发；refit 同时承担切回 tab 的几何校验；③cleanup 断 observer 并重置 lastSynced 防重挂载去重吞帧。回归：前端 `TerminalTimeline.spec.ts` 4 用例（挂载 emit/refit 强制重发/隐藏容器不发/observer 去重）+ `WorkspaceView.spec.ts` 2 用例（会话采纳触发 refit/resize→通道帧）；浏览器实证：新 tab 发 `resize 97x22` → 远端 `stty size` 回 `22 98→22 97` 同步；>80 列 echo 命令按真实列数折行；`\x1b[A` 调历史长命令完整重显无错乱；隐藏 tab 切回补发且 stty 同步。修复后 #21/#22 的 tick 验证中方向键/历史均正常。
**预防措施**: ①两端几何系统（本地渲染 vs 远端 PTY 排版）只要存在代理关系就必须有“连接即同步 + 变化事件同步 + 切回校验补发”三层，缺任何一层都会以“某个交互动作触发才暴露”的形态还债；②“去重/守卫”必须区分“无变化”与“从未成功同步过”（force 通道），否则首帧在错误时机（通道未就绪/容器隐藏）被丢后永远无人补发；③fit/proposeDimensions 在隐藏容器下返回 undefined/no-op，凡拿它的结果往外发必先校验有效性，不能拿 terminal.cols 的旧默认值充数；④历史 recall 类交互（方向键/Ctrl-R） MUST 交由远端 shell/readline 通过 PTY 回显，前端绝不自绘/重复写入渲染内容，否则两边几何必然打架。

## 24. 打断 Agent 回合后再执行，模型重复思考不执行——MANUAL_BUSY 结构性死锁（拒绝提交→无完成帧→永久 busy 自锁闭环）

**发现时间**: 2026-09-23（用户反馈：把 agent 对话打断后再执行，agent 返回重复之前的思考，就是不执行，附截图）
**影响范围**: Agent 模式 PTY 调度链路：回合停止后只要在 Shell 敲过任意键（哪怕半行未回车），后续全部获准命令被拒，模型无限重试
**根本原因**: `PtyCommandScheduler` 状态机自锁闭环——busy 的唯一置入路径是 WS input 帧 `onManualBusy()`；busy 的唯一恢复证据是 `currentCommand==null` 时的 PROMPT 帧（需命令真正执行完才出现）；而 `submitCommand` 在 MANUAL_BUSY 下**直接拒绝**不发命令→永无 PROMPT→永久 busy。被拒命令以 tool_result 失败回喂模型→模型重提同一命令→再被拒（日志铁证：curl nodejs 安装命令获准后报"当前状态 MANUAL_BUSY 不接受命令提交"→round=2 重复思考）。与 #21/#22 同族：阻塞态的恢复证据链依赖被它拒绝的事件本身。
**解决方案**: 参照现行 ssh 客户端"注入前清行"：①busy 静默自愈过期（`DEFAULT_BUSY_EXPIRE_MS=10s`，从最后一次按键起算、连续按键重排）：到期仍 busy 且无在飞命令→Ctrl-C 清疑似半行→MANUAL_IDLE→tryDispatchNext；②busy 提交从拒绝改排队（enqueueCommand）；③busy 且无在飞命令时收到 CMD_START（用户前台程序在跑）取消自愈，防 Ctrl-C 误杀 top/vim；④PROMPT 恢复/onManualIdle/onStopping 统一取消自愈任务。RED：ManualBusySelfHeal 5 用例（7 参构造器编译失败）；GREEN 后定向 31/31、全量 771/771。浏览器终验：打断→按键→审批命令排队约 10s 后自动派发执行。
**预防措施**: ①状态机任何"拒绝进入"的阻塞态，其恢复证据 MUST NOT 依赖被它拒绝的动作本身触发（拒绝+等待=自锁闭环），必须有独立于事件流的兜底恢复路径（超时/心跳/人工）；②"不凭静默猜测"只适用于**在飞命令完成判定**；用于**空闲终端输入权归还**时应做成有界自愈（带清行副作用）而非永久封锁；③排队+延迟执行远比拒绝+重试友好：拒绝会被回喂模型引发重试风暴，模型无法用任何策略绕过状态锁；④自愈类定时任务必须在新证据（PROMPT/CMD_START/显式 idle）到达时取消，否则恢复后窗口内误发 Ctrl-C（测试检测"未取消的旧任务"必须制造新旧窗口差，单次 sleep 越界会连正确实现一起假红）。

## 25. 断线重连时旧回合打断指令被时序缺口吞掉：AI 通道尚未恢复，stop_turn 帧无处可发

**发现时间**: 2026-09-23（reset-agent-memory-on-reconnect 变更 D7，用户真实路径终验：下载到一半 Ctrl+C 再断连重连）
**影响范围**: 断线重连链路：重连瞬间若 AI 通道（/ws/ai）尚未恢复，打断旧在飞回合的 stop_turn 上行帧被丢弃，旧回合在后端继续占用 inFlight/审批等待，新提问被 ERR_BUSY 阻塞
**根本原因**: reconnectWorkspace 的“先打断旧对话再解绑”序列假设 AI 通道已连接；而三条 WS 通道重建有先后时序窗口，通道未就绪时 send 要么抛异常要么静默丢帧，打断指令没有送达保证。与 #20 第五层同族：取消/停止类指令的送达不能依赖“恰好在线”的乐观假设。
**解决方案**: 通道已连接则直发 stop_turn；否则注册一次性 onStateChange 监听，等 connected 后补发再解绑 conversationId；需求回写主 spec「断线重连」：“若重连瞬间 AI 通道尚未恢复，打断指令 MUST 在通道恢复后补发”。回归：前端 WorkspaceView.spec 重连用例；浏览器终验（kill 后端模拟整条 WS 断连）：重连按钮→三通道重建→重置注记→新提问无 ERR_BUSY。
**预防措施**: ①凡“必须先发生再发生”的跨通道指令，都要回答“发送时通道不在怎么办”——补发队列或状态监听是一次性还是常驻（一次性用完即退订，防重复补发）；②模拟整条 WS 断连用 kill 后端而非 kill vite：后者会触发页面 HMR full reload 破坏 SPA 状态验证前提；CDP Offline 不掐既有 WebSocket，不能用于模拟断连。

## 26. 审批点「取消」AI 仍发起下一轮 + 回合结束后 ❯ 提示符要敲键才出现：两个用户实测反馈的收尾语义缺口

**发现时间**: 2026-09-23（cancel-ends-turn-auto-prompt 变更，用户两条追加需求：①弹窗点取消应只结束本次对话不再发起下一轮/调工具；②AI 结束后应自动换行显示 ❯ 并把光标移过去，现状要敲键盘提示符才出现）
**影响范围**: BUG-G：所有审批取消场景，模型收到“用户已拒绝”回喂后继续推理另想办法或重复提案，用户感知为“取消了还在转”；BUG-H：Agent 模式每次回合结束（回答完成/错误/停止/取消终结/轮次上限）屏幕停在无提示符空档，光标不落位
**根本原因**: BUG-G——取消与超时共用 rejected() 回喂路径，拒绝事实被当作“工具结果”喂回模型，把“是否继续”的决定权交给了模型，而用户点取消是确定性的终结信号；BUG-H——❯ 提示符是惰性实现（ensureAgentPromptLine 由按键事件驱动写入），“输出结束→等待输入”的状态转换点没有任何一方主动渲染。与 #20/#24 同族：收尾语义只做了“状态复位”，没做“用户下一步体验”的闭环。
**解决方案**: BUG-G：`ToolOutcome` 第 5 参重定义为 `userRejected`（零消费方直接重命名），`runGated` 仅 `ApprovalOutcome.CANCELLED` 置真（超时/中断保持 false 维持回喂现状）；`loopRounds` 执行循环遇取消 break（不再执行后续工具），proposals/tool 消息落库循环改按 outcomes 实际长度截断配对（原 `outcomes.get(index++)` 遍历全部 calls 会越界），落完后 `finishWithNote(CANCEL_END_NOTE, "approval_cancelled")` 终结不回喂。BUG-H：`TerminalTimeline` 新增 expose `openAgentPrompt()`（复用 ensureAgentPromptLine 幂等），`WorkspaceView` 四类触点（Final/Error 帧、stopAgentTurn 本地闭环、重连重置注记）在 Agent 模式调用；`writeToTerminal` 在提示行已打开且无草稿时先 `\r\x1b[K` 清行再写输出（防异步输出拼在 ❯ 后）；`ensureAgentPromptLine` 换行后消费 `initialPromptWritten` 标志（否则首次写入双清行把刚落的 ❯ 也抹掉——实现 GREEN 时由测试抓出）。回归：后端 `AiAgentServiceTest#userCancellationEndsTurnWithoutAnotherModelCall`（streamCallCount==1 + finishReason=approval_cancelled + 注记落库）+ 前端 TerminalTimeline 4 用例/WorkspaceView 5 用例；浏览器终验：touch 审批点取消→留痕“→ 已拒绝”+终结注记+持续观察无新回合+❯ 自动落位，落位行直接键入新问题畅通，回答完成后 ❯ 再次落位。
**预防措施**: ①“拒绝/取消”类回喂先问该不该喂：确定性终结信号（用户主动取消）由编排层直接终结，只有需要模型改道的信息（超时/参数错）才回喂；②循环可提前 break 时，所有按下标配对遍历（`outcomes.get(index++)`）都须改为按短集合实际长度截断，否则越界或错配；③凡把 UI 元素（提示符/光标位）的呈现挂在按键事件上的实现，必须在每个“输出结束→等待输入”收尾点主动渲染，验收时不能只测按键后是否正确，还要测输出刚结束、无任何按键时的静态画面；④同一写入入口叠加多个“清占位行”标志时必须互相消费（换行离开占位行即视为已清除），双清会把刚写入的内容一并抹掉；⑤验证终端交互类改动的浏览器终验，取证前整页强刷排除 HMR 混合态。

## 27. 删除最后一条模型配置报 409：生效配置拒删设计与自动生效规则互锁，用户永远删不掉最后一条

**发现时间**: 2026-09-24（用户附截图反馈：删到只剩最后一条再删报「模型配置加载失败：Response returned an error code」）
**影响范围**: 设置页模型配置删除链路；与桌面壳空库首启诉求同源（零配置必须是合法态）
**症状**: 删除当前生效配置返回 409；且前端 banner 把删除失败渲染成「模型配置加载失败」，错误原因被生成客户端吞成技术黑话
**根本原因**: 三层叠加——①`ModelConfigService.delete()` 对生效配置抛 ConflictException（历史契约 TRACEABILITY Q4/R11 承诺「删除生效→409」，防 AI 能力静默失效）；但 create 时首条自动生效（`autoActivated = activeConfigId().isEmpty()`），“只剩一条”必然“它就是生效项”，两规则互锁使最后一条永远删不掉——而 requireActive 零配置时本就报可读引导「尚无生效的模型配置」、界面也有缺配置提示，防御的前提（静默失效）不成立；②前端 SettingsView 把加载/变更共用的 error 写死「加载失败」文案；③openapi 生成客户端 ResponseError 把后端 Error JSON 的 message 吞成固定串 "Response returned an error code"。
**解决方案**: 契约级行为变更（用户裁定）：`delete()` 移除 409 分支，删生效配置时同步 `settingsService.deleteKey(ACTIVE_CONFIG_KEY)` 不留悬空指针；同步修订 contract/openapi.yaml（删 409 响应）、TRACEABILITY R11 与错误码表、主 spec model-provider 新增「删除生效中的模型配置」场景；前端新增 `describeApiError`（解 ResponseError body 透出后端 message）+ banner 改「操作失败」。TDD：先改集成测试断言 204+指针清空（RED 精确 2 失败），GREEN 后全量回归 BE/FE 双 0。
**预防措施**: ①“拒绝操作保护用户”的设计必须检查与其它不变量（如首条自动生效）是否互锁成死态：任何“用户永远无法达成 X”的状态设计都是错的，除非 X 本身非法；②零配置/空库这类初始合法态的处置路径（requireActive 报错文案、UI 缺配置提示）必须在设计时同步验证，而不是用拒绝操作回避空态；③行为变更触及 contract/ 承诺时，契约行、错误码表、openapi、主 spec 四处必须同批修订。

## 28. 桌面壳 CSP `style-src 'self'` 拦截 xterm DOM 渲染器动态样式表：打包后 ANSI 着色全丢，思考/回复同色

**发现时间**: 2026-09-24（用户附对比截图：安装包内 AI 渲染与浏览器 dev 不一致，思考内容与回复全白）
**影响范围**: 桌面形态全部终端/AI 渲染（WorkspaceView 共享 xterm 的 ANSI 色彩：思考 dim、❯ 青色提示符、彩色命令输出全部退化）
**症状**: 浏览器 dev 思考内容灰色（\x1b[2m dim）、回复白色；打包壳内同为白色；背景色正常（外部 CSS 生效）
**根本原因**: xterm DOM 渲染器的全部着色规则（ANSI 16/256 色类、dim 的 50% 淡化色）不在随 bundle 的 xterm.css 里，而是 `DomRenderer._injectCss` 用 `document.createElement('style')` 动态注入（实证：node_modules 源码 L155-275）；桌面 CSP 任务 3.2 当时注释断言「xterm 只走 CSSOM 动态设样式不受 CSP 拦截」只对 per-span 颜色成立，动态 `<style>` 元素受 style-src 管控——无 'unsafe-inline' 即被 Chromium 整块拦截。取证链：先证伪“旧 bundle”假设（包内/暂存/当前三处 dist 逐文件 SHA256 一致），再源码定位注入机制。浏览器 dev 不注入 CSP 故正常。
**解决方案**: `vite.config.ts` DESKTOP_CSP 的 style-src 补 'unsafe-inline'（xterm.js 官方对 DOM 渲染器的明确要求；script-src 保持 'self' 不连带放宽），重建后经 `npm run build` 产物 index.html 验证 meta 已含。实证验收：重打包后桌面壳内思考恢复灰色。
**预防措施**: ①对第三方库定 CSP 前，必须区分其样式注入的三种通道（外部 css 文件 / 元素 style 属性经 CSSOM / 动态 `<style>` 标签），只有第一种被 'self' 覆盖；对带运行时样式生成的库（xterm/编辑器/canvas 类）先查官方 CSP 文档再做 grep 推断；②“打包后与浏览器不一致”类反馈，第一步用哈希对比证伪/坐实“bundle 不同”，再查环境差异（CSP/GPU/字体），不要直接怀疑代码；③CSP 拦截在 Electron 不白屏只静默降级，复验时必项检查 devtools console 的 Refused to apply inline style 告警是否消失。

## 29. 内网自托管模型思考内容以 think 开闭标签内联在正文：后端只认 reasoning_content 字段，终端里满屏原始标签

**发现时间**: 2026-09-24（用户附截图：MindIE 部署的 Qwen3 在桌面壳/浏览器里思考内容未渲染为灰色 [思考] 段，而是带 think 开闭标签混在回答里；云端模型正常）
**影响范围**: 全部 AI 聊天渲染（桌面壳与浏览器 dev 同犯，因为根因在后端）；model-provider「思考与非思考双模式」MUST 条款不满足
**症状**: 思考模式下面板里出现字面 think 开/闭标签对，标签内文本与回答同色同段；而云端（DashScope/DeepSeek 兼容端点）经 reasoning_content 独立字段返回思考，渲染正常
**根本原因**: 后端流式消费只认 `AssistantMessage` 元数据的 `reasoningContent` 键（OpenAI 兼容扩展字段），content 里的增量无条件全部归 answer_delta；而 Qwen3 类自托管推理服务（MindIE/vLLM 部署）把思考直接内联在 content 里逐字流出，不填独立字段——同一 OpenAI 协议下思考的两条载体通道只实现了一条。
**解决方案**: 新增 `InlineThinkTagParser`（有状态增量分流器：标签内归 thinking、标签外归 answer、标签字符吞掉；尾部可能是半截标签前缀的字符扣在待定缓冲防 SSE 分片拦腰截断泄漏碎片；回合结束 flush，未闭合标签余文归思考）；`streamRound` 仅在思考模式接线（与 reasoningContent 同口径，非思考模式原样透传不解析，回归用例钉住）；分流后仍走既有 thinking_delta/answer_delta 帧型与 reasoning/content 双列落库，前端零改动。TDD：RED 4 用例精确 3 失败（透传守卫用例先行绿）→ GREEN 定向 42/42 → 全量 807/807；主 spec model-provider 补「内联思考标签分流」场景。
**预防措施**: ①接 OpenAI 兼容协议时“思考”有两类载体（独立字段 reasoning_content vs 正文内联 think 开闭标签），只实现前者就会在内网自托管模型上碎掉，选型探测必须覆盖两类；②流式文本里找定长标记必须按“跨分片截断”设计（待定后缀缓存 + 回合末 flush），任何“等收齐再正则切”的方案都保不住实时性；③编辑工具链会把成对尖括号标记当控制序列处理：源码/提交信息里需要这类字面量时用字符串拼接（"<"+"think"+">"）构造，写入后必须读回磁盘核实。

## 30. 升级安装后桌面快捷方式图标不更新：keepShortcuts 不重建 lnk + Explorer 图标缓存按路径复用旧位图

**发现时间**: 2026-09-24（用户真机反馈：win.icon 修好后重装，开始菜单/exe 属性图标都新，唯独桌面快捷方式仍是 Electron 默认图标）
**影响范围**: 所有升级安装路径的用户桌面；首次安装不受影响
**症状**: 取证：已装 exe 仍是旧版（用户装的 win.icon 修复前的包）；且桌面 lnk 写入时间停在首次安装——electron-builder 的 keepShortcuts 机制（卸载旧版时保留快捷方式、升级时不重建）使 lnk 根本不重写；即便重建，lnk 图标按「exe 路径+索引」取自 exe，Explorer 图标缓存命中旧位图不刷新（模板只发 SHCNE_ASSOCCHANGED，刷关联不刷图标缓存）
**根本原因**: 三层叠加：①用户装的是修复前包（时间戳取证坐实）；②keepShortcuts 升级路径跳过 CreateShortCut；③NSIS/Explorer 图标缓存无主动失效通知。
**解决方案**: 新增 `frontend/desktop/installer/installer.nsh` 经 `nsis.include` 注入 `customInstall` 宏（在 addDesktopLink 之后执行）：无条件 Delete+CreateShortCut 重建桌面 lnk（参数与模板一致）→ SHChangeNotify(SHCNE_UPDATEIMAGE+FLUSH / SHCNE_ASSOCCHANGED+FLUSH) 弃图标缓存 → `ie4uinit.exe -show` 兑底。注入机制用对照实验坐实：临时塞非法指令 BogusCommandProbeXYZ → makensis 报「Error in macro customInstall … installSection.nsh on line 82」→ 删除探针重建 exit=0。注意 nsh 不能放默认 build/ 位（构建脚本每次清空该暂存目录），放固定的 installer/ 目录；getResource 对找不到的 include 会抛 InvalidConfigurationError，构建成功即路径解析正确。
**预防措施**: ①“图标没变”类反馈先取证已装 exe 时间戳判断用户装的是哪版包，再查 lnk 写入时间判断快捷方式是否被重建，两层原因处置完全不同；②验证“配置真的生效”不能只看构建 exit=0（静默跳过也绿），用故意破坏法对照实验证明注入链路存在；③NSIS 自定义宏的执行时机查模板源码确认（customInstall 在 addDesktopLink 之后），不要凭文档记忆。

## 31. 嵌套 Shell（docker exec -it ... bash）后 Agent 停止响应：Shell 集成钩子函数不经环境继承，帧静默缺失

**发现时间**: 2026-10-08
**影响范围**: Agent 模式下用户通过 `docker exec -it <container> bash` 或任何方式启动嵌套 bash 后的全部命令执行
**症状**: 用户进入 Docker 容器后，Agent 提问不再执行命令，模型反复思考不执行或超时；Shell 模式不受影响（直连不经调度器）
**根本原因**: `ShellIntegration.generateBashIntegrationCode` 把 PROMPT_COMMAND 设为调用 bash 函数 `_ananoesis_prompt_hook`；bash 环境变量（PROMPT_COMMAND 字符串）会被子进程继承，但 shell 函数定义不经 `export -f` 不随环境传递。嵌套 bash 每次提示符执行 PROMPT_COMMAND 时函数不存在 → 报错被静默吞掉 → CMD_END/PROMPT 集成帧零产出 → `PtyCommandScheduler` 在 AGENT_OWNED 状态下 `future.get` 一直等待至绝对超时。exec 通道不受影响（独立 SSH session），故障仅出现在依赖持久 PTY 帧边界的链路。与 #13 同族：集成代码在当前 shell 生效不等于在嵌套 shell 生效。
**解决方案**: 帧超时探测 + 集成重安装：①`PtyCommandScheduler` 新增 `lastFrameNanos` 帧活动计时，MANUAL_IDLE 超过 `nestedDetectTimeout`（默认 8s）无帧则发送探测命令 `echo _ANANOESIS_NESTED_PROBE_$$`；②`collectOutput` 检测探测标记回显确认嵌套 Shell 存在，触发 `ShellIntegration.reinstall(nonce)` 用新 nonce 重新安装集成代码；③最多重装 1 次，仍无帧则降级 `nestedFallback=true`，`submitCommand` 抛异常走 exec 回落；④`SshProperties.nestedDetectTimeout` 配置项（默认 8 秒，0 禁用）。回归：`PtyCommandSchedulerTest` 2 用例 + `ShellIntegrationTest.reinstallGeneratesNewNonceAndCode` + `ShellIntegrationInstallerTest.reinstallProducesNewOutcome`。
**预防措施**: ①注入 shell 变量/钩子的逻辑在任何后代 shell 里不一定可用——函数定义、别名、局部变量都不经环境继承，只有变量值会传递；②排查"进入容器/子shell后功能静默失效"类问题先检查注入机制跨进程存活能力；③"无帧"类静默失败必须有独立于命令超时的探测兆底（帧超时探测与命令空闲超时正交）。

## 32. Agent 流式回复期间强制滚底，用户无法向上滚动查看历史

**发现时间**: 2026-10-08
**影响范围**: Agent 模式所有流式回复（SSE delta 高频写入）期间的终端滚动体验
**症状**: Agent 回答时每次文本增量都把视口拉回底部，用户无法向上滚动查看之前的对话历史；只有等回复完全结束后才能松手
**根本原因**: `TerminalTimeline.writeToTerminal()` 每次写入后无条件调用 `scrollToBottom()`，而 Agent 流式回复期间每个 SSE delta 都经此路径，高频触发（每 delta 一次）把用户滚动立即覆盖。与 #23 同源：终端渲染侧行为未考虑用户主动交互的优先级。
**解决方案**: 滚动位置感知：①新增 `userScrolledAway` ref + `isViewportAtBottom()` 函数（`buffer.active.viewportY >= buffer.active.baseY - terminal.rows - 2`，容差 2 行）；②挂载 xterm `onScroll` 监听器，每次滚动后更新 `userScrolledAway`；③`writeToTerminal` 改为条件滚底（仅 `!userScrolledAway` 时 `scrollToBottom()`）；④`refit()`（切回 tab）保持无条件滚底（用户期望看到最新内容）；⑤用户滚回底部时自动恢复跟随。回归：`TerminalTimeline.spec.ts` 3 用例（滚动中写入不拉回/滚回底部恢复跟随/refit 无条件清除标志）。
**预防措施**: ①终端自动滚底 MUST 以“用户未在查看历史”为前提，任何高频写入路径都要先检查滚动位置；②`refit()`/切回 tab 等场景的用户预期是“看到最新内容”，与流式写入的“不打扰用户查看历史”是两个独立语义，不能共用同一开关；③viewport API 封装为独立函数（`isViewportAtBottom()`），xterm.js 版本升级时只需改一处。

## 33. Shell 模式人工命令对 Agent 不可见，记忆不同步

**发现时间**: 2026-10-09
**影响范围**: Shell 模式与 Agent 模式的上下文切换（用户进入 Docker 容器后 Agent 不知道）
**症状**: 用户在 Shell 模式执行命令（如 `docker exec -it <container> bash`）后切换到 Agent 模式，Agent 不知道用户执行了什么命令，也不知道用户进入了嵌套 Shell，仍基于宿主机环境给出错误建议
**根本原因**: `PtyCommandScheduler` 已能区分人工命令与 Agent 命令（CMD_START/CMD_END/PROMPT 帧序列），`ConversationService.saveShellEventMessage()` 已就绪但从未被生产代码调用——设计好了但没接线。同时 `nestedState` 探测结果仅用于内部集成重安装，不对外暴露
**解决方案**: sync-shell-memory-to-agent 变更：①`PtyCommandScheduler` 增加 `ManualCommandListener` 回调接口和输出累积缓冲，人工命令完成后触发回调；②`SshTerminalService` 注入回调实现：写 `command_executions` 账本 + 写 `ai_messages` 对话历史；③`PtyCommandGateway.isNestedShell()` 暴露嵌套状态；④`AgentSystemPrompt.build()` 新增最近 Shell 活动和嵌套环境段落；⑤`AiAgentService.runTurn()` 和上下文恢复路径同步注入
**预防措施**: ①新帧协议功能如果只写了 service 方法但没在生产代码中调用，应有集成测试覆盖接线点；②回调模式（与 `nestedShellCallback` 一致）保持调度器不依赖上层服务类的设计

## 34. JaCoCo 分支覆盖率阈值从 0.70 提升到 0.75

**发现时间**: 2026-10-09
**影响范围**: 后端构建门禁（`mvnw verify`）
**症状**: 无（主动提升）
**根本原因**: 随测试覆盖逐步完善，实际覆盖率已超过 0.70，提升阈值确保新增代码保持较高覆盖水平
**解决方案**: `backend/pom.xml` JaCoCo check 的 `<minimum>` 从 `0.70` 改为 `0.75`。排除规则不变（contract/entity/mapper/package-info/Application）
**预防措施**: 渐进式提升策略，后续随测试完善继续逐步提升，不一刀切 100%

---

**最后更新**: 2026-10-09
**维护者**: AI Agent + 开发团队
