# Sprint 1 -- 2026-05-12 to 2026-05-16

## Sprint Goal
搭建 Pre-Production 基础设施（测试框架、项目骨架、Control Manifest），并实现 Foundation 层 SaveSystem 系统，完成第一个可运行的单元测试。

## Capacity
- Total days: 5
- Buffer (20%): 1 day reserved for unplanned work
- Available: 4 days effective

## Phase Gate: Technical Setup -> Pre-Production
- Verdict: **CONCERNS**
- Architecture: PASS (90.9% coverage, 24/24 ADRs Accepted)
- Gap: No test framework, no src/ structure, no Control Manifest, no sprint plan
- Resolution: This sprint fills all blocking gaps

## Tasks

### Must Have (Critical Path)

| ID | Task | Owner | Est. Days | Dependencies | Acceptance Criteria |
|----|------|-------|-----------|-------------|-------------------|
| S1-01 | 配置 GUT 测试框架：创建 tests/ 目录结构，配置 gutconfig.json，验证 Godot headless 可运行测试 | godot-specialist | 0.5 | 无 | `godot --headless --script tests/gut_runner.gd` 运行成功，至少 1 个 green test |
| S1-02 | 创建 src/ 代码目录结构：按架构文档层创建 src/core/、src/feature/、src/presentation/、src/foundation/ | godot-specialist | 0.25 | 无 | 目录结构匹配 architecture.md System Layer Map |
| S1-03 | 实现 SaveSystem 核心：save_system.gd AutoLoad，load/flush/delete_profile/get_save_path，schema v2，atomic write (.tmp + rename) | godot-gdscript-specialist | 1.5 | S1-01, S1-02 | 所有 TR-save-system-001~009 被覆盖；GUT 测试全部 green |
| S1-04 | SaveSystem 单元测试：覆盖 load/flush/delete/.tmp recovery/schema migration/edge cases | godot-gdscript-specialist | 1 | S1-03 | 至少 12 个 test cases，覆盖率 > 80% |
| S1-05 | 创建 Control Manifest：docs/architecture/control-manifest.md，Required/Forbidden/Guardrails per layer | godot-specialist | 0.5 | S1-02 | 覆盖 Foundation + Core 层规则；Manifest Version 有日期戳 |
| S1-06 | 配置 AutoLoad 顺序：project.godot 中添加 SaveSystem 为第一个 AutoLoad | godot-specialist | 0.25 | S1-03 | Project Settings -> AutoLoad 显示 SaveSystem 排序第一 |

### Should Have

| ID | Task | Owner | Est. Days | Dependencies | Acceptance Criteria |
|----|------|-------|-----------|-------------|-------------------|
| S1-07 | 创建 Risk Register：production/risk-register/register.md，记录 8 个 Open Questions + VoiceRecorder/inkgd 风险 | producer | 0.5 | 无 | 每个风险有 Probability/Impact/Mitigation/Owner |
| S1-08 | 设备验证 Spike：Android 设备上测试 DirAccess.rename() 原子性 + FileAccess.store_string() bool 返回值 | godot-specialist | 0.5 | S1-03 | 记录测试结果到 docs/architecture/open-questions.md |
| S1-09 | 创建 Milestone 定义：production/milestones/pre-production.md，定义 Pre-Production 范围和完成标准 | producer | 0.25 | 无 | 包含 feature list、target date、go/no-go criteria |

### Nice to Have

| ID | Task | Owner | Est. Days | Dependencies | Acceptance Criteria |
|----|------|-------|-----------|-------------|-------------------|
| S1-10 | 创建 Ink 最小测试文件：assets/data/chapter1_minimal.ink.json（3 行叙事 + 1 个选择） | godot-gdscript-specialist | 0.5 | 无 | JSON 可被 inkgd InkResource 加载，can_continue 返回 true |
| S1-11 | CI/CD 基础：.github/workflows/test.yml，push 时运行 Godot headless 测试 | godot-specialist | 0.5 | S1-01 | Push 到 main 触发测试运行，失败时 PR 被阻塞 |

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| GUT v9.6.0 与 Godot 4.6 不兼容 | LOW | HIGH | 已在 project.godot 启用插件；S1-01 第一步验证 |
| DirAccess.rename() 在 Android API 24-33 行为不一致 | MEDIUM | HIGH | ADR-0004 定义了 fallback：rename 失败则读回 .tmp 直写 .json；S1-08 设备验证 |
| Godot headless 模式无法运行 GUT | LOW | MEDIUM | 备选：使用 `godot --script` 在编辑器模式运行 |
| SaveSystem schema v2 migration 逻辑复杂度超预期 | LOW | MEDIUM | 先实现 MVP 格式（无 v1 迁移），v1 迁移推迟到 ProfileManager 实现后 |

## Dependencies on External Factors
- Android 设备可用性（S1-08 设备验证需要）
- Godot 4.6 headless 导出模板是否已安装

## Definition of Done for this Sprint
- [ ] All Must Have tasks completed
- [ ] All tasks pass acceptance criteria
- [ ] GUT 测试框架可运行，至少 1 个 green test
- [ ] SaveSystem 实现完成，12+ 单元测试全部 green
- [ ] Control Manifest 覆盖 Foundation 层
- [ ] src/ 目录结构匹配架构文档
- [ ] No S1 or S2 bugs in delivered features
- [ ] Code reviewed and merged

## Carryover from Previous Sprint
N/A -- 首个 Sprint，无 carryover。
