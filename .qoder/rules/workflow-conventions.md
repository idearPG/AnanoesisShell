---
trigger: always_on
alwaysApply: true
---

# Workflow Conventions — 开发工作流规范

## 1. 开发流程（Explore → Plan → Implement → Verify → Complete）
- **Explore**：理解需求，阅读 `openspec/specs/`；用 brainstorming 技能澄清；开发前读 `.qoder/known-issues.md`
- **Plan**：用 writing-plans 技能制定计划，任务拆成可独立验证的小步
- **Implement**：用 test-driven-development 技能，RED→GREEN→REFACTOR；遵循 coding-standards
- **Verify**：用 verification-before-completion 跑全部测试；用 requesting / receiving-code-review 评审
- **Complete**：更新 specs，/opsx:archive 归档；仅在用户明确授权后提交/推送，归档不等于提交或发布

## 2. 约束规则
- 不得跳过 brainstorming 直接实现
- 不得在无测试情况下提交实现代码
- 不得在验证前声称完成
- 所有变更必须经 openspec 变更流程

## 3. 质量门禁（提交前）
- [ ] 所有测试通过
- [ ] 符合编码规范
- [ ] 无安全漏洞引入
- [ ] 变更与 spec 一致
- [ ] 关键业务逻辑有注释

## 4. 禁止合并的情况
1. 测试未全部通过
2. 存在未解决的 code review 问题
3. spec 场景未完全实现
4. 引入未记录的破坏性变更
5. 关键业务逻辑缺少注释
6. Spec 漂移检查未通过（见 `.harness/sensors/drift-detection.md`）

## 5. Worktree + 子仓库并行开发（强制）
主仓库用 `git worktree` 并行开发时，**子仓库必须同步创建同名 feature 分支**，禁止停留在 `main`。

### 5.1 创建 worktree 时同步子仓库分支

    git worktree add ../AnanoesisShell-feat-x feature/feat-x
    cd ../AnanoesisShell-feat-x
    cd frontend && git fetch origin && git checkout -b feature/feat-x origin/main && cd ..
    cd backend  && git fetch origin && git checkout -b feature/feat-x origin/main && cd ..

### 5.2 进入 worktree 必检子仓库分支

    cd frontend && git branch --show-current && cd ..
    cd backend  && git branch --show-current && cd ..

若子仓库不在对应 feature 分支，必须立即切换或按 5.1 创建。

### 5.3 合并闭环（Check → Merge → Clean）
- **Check**：在 feature 工作区执行第 6 节的全量验证并记录退出码；任一失败阻止合并
- **Merge**（仅授权后）：先让 frontend/backend 各自的 feature 合入各自 main，验证并推送子仓库 main；主控 feature 更新两个子仓库到这些最终提交，再提交指针、合入主控 main 并验证/推送。
- **Clean**（仅授权后）：确认主控指针引用的子仓库提交可从远端取回且被 main 保留，再清理本任务创建的 worktree 和已合并 feature 分支；不强制删除未合并或由外部管理的工作区。

### 5.4 禁止事项
- 禁止主仓库建 worktree 而子仓库停留在 main
- 禁止只合并 / 推送 / 清理主仓库而忽略子仓库
- 禁止未 Check 直接 Merge、Merge 后不验证直接 push
- 禁止在 feature 工作区直接 push 到 main

> 以下命令基于当前已落地技术栈；兼容性目标另见 `platform-compatibility.md`。

## 6. 当前技术栈验证命令
在主控仓库根目录逐条执行（Windows PowerShell，失败即停）：

```powershell
npm --prefix frontend run type-check
npm --prefix frontend run test
npm --prefix frontend run build
.\backend\mvnw.cmd -f backend/pom.xml -B test
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify-structure.ps1 -Root .
openspec validate --all --strict
```

- 每条原生命令后检查 `$LASTEXITCODE`；不得用最后一条成功覆盖前面失败。
- 当前 frontend 没有 lint 脚本，不能报告“lint 已通过”；需要自动格式/静态门禁时另行接入并验证。
- Windows 下若 Vitest 因盘符大小写/缓存导致收集失败，先核查实际路径，统一绝对 root 后重跑；测试收集失败不等于业务断言失败，也不等于通过。
- 构建发布包还需执行 Maven package 及客户端兼容矩阵；单元测试不替代 Windows 7/10/11 安装验证或真实 Linux E2E。

## 7. 规格与归档的证据边界
- OpenSpec strict 校验只证明规格结构合法，不自动证明实现与每个场景一致；需补代码/测试追溯。
- 本 rules 中“规格为行为真相源”的约束优先于 `.harness/sensors/drift-detection.md` 旧有“代码是真相源”的描述：代码用于证明现状，缺失需登记或补实现；只有经过明确需求决策才能修订规格，不能为了让检查通过而缩减需求。
- 归档前检查工件、未勾选任务和 delta specs；主规格同步不得丢失原场景。保留未完成项及已知实现缺口，不能为归档虚假勾选。
- 存在未完成任务或带风险归档时，展示事实并取得确认；带警告归档不解除第 4 节的合并门禁，也不代表生产安全验收通过。
- 审批 UI 等呈现方式与旧规格文字不一致时显式登记，不在归档中悄悄缩减需求；真正的行为修订走后续 OpenSpec。
- 前后端实现及契约未提交时，明确提示归档不会自动保存子仓库代码；提交/推送仍按子仓库→主仓库顺序且需要授权。

## 8. 发布构建规范（桌面安装包）
- 发布构建**必须全量执行** `scripts/build-desktop.ps1`，**禁止使用任何 `-Skip*` 开关**（`-SkipFrontend`、`-SkipBackend`、`-SkipJre`、`-SkipWipe`、`-SkipBuilder` 均不允许）。
- 全量含义：清库（`~/.ananoesis/data.db*`）→ 前端 `vite build` → 后端 `mvnw package` → JRE 检查/下载 → 暂存三物 → `electron-builder --win nsis`，完整走一遍。
- 即使前后端产物已存在且代码未变，发布时仍必须重新编译打包，确保产物与当前源码一致。
- 清库步骤不可跳过：安装包不携带数据库，但本机验证安装时需要干净首启体验；文件被运行中后端锁住时，必须先停掉后端再构建，不得用 `-SkipWipe` 绕过。
- `-Skip*` 开关仅供本地调试构建使用，任何面向发布（GitHub Release、安装包分发、版本打 tag）的构建一律禁止。
