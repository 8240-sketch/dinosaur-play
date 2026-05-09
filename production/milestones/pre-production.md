# Milestone: Pre-Production

> **Status**: In Progress
> **Start Date**: 2026-05-12
> **Target Date**: 2026-05-30 (3 weeks)
> **Owner**: producer

---

## Scope

Pre-Production 阶段的目标是验证核心技术可行性，建立可运行的 Vertical Slice 骨架，并为 Production 阶段准备好所有基础设施。

### Feature List

| Feature | Priority | Status | Dependencies |
|---------|----------|--------|-------------|
| SaveSystem 实现 + 测试 | P0 | ✅ Done | 无 |
| ProfileManager 实现 + 测试 | P0 | ⏳ Pending | SaveSystem |
| VocabStore 实现 + 测试 | P0 | ⏳ Pending | ProfileManager |
| inkgd Android 验证 | P0 | ⏳ Pending | 第 1 周末 |
| GUT 测试框架可运行 | P0 | ✅ Done | 无 |
| Control Manifest | P0 | ✅ Done | ADR 全部 Accepted |
| Art Bible | P0 | ✅ Done | 无 |
| CI/CD 基础 | P1 | ⏳ Pending | GUT |
| 设备验证 Spike | P1 | ⏳ Pending | SaveSystem |
| Ink 最小测试文件 | P1 | ⏳ Pending | 无 |

### Vertical Slice Scope

Vertical Slice 验证目标：**一次完整的核心循环**

```
主菜单 → 出发冒险 → 第 1 个词汇选择（T-Rex / Triceratops）
→ 正确选择 → T-Rex happy 动画 + TTS
→ 错误选择 → T-Rex confused 动画 → 鼓励重试
→ 通关 → 金星 + 明信片 → 返回主菜单
```

### Go/No-Go Criteria

**可以进入 Production 当且仅当以下全部满足：**

| # | Criterion | Verification Method |
|---|-----------|-------------------|
| 1 | inkgd 在 Android APK 上可推进 ink 对话 | 真机测试 |
| 2 | SaveSystem + ProfileManager + VocabStore 全部实现且测试通过 | GUT 测试报告 |
| 3 | Art Bible 已创建且 Sections 1-4 完整 | 文档审查 |
| 4 | 至少 1 个完整的核心循环可运行（Vertical Slice） | 真机演示 |
| 5 | 4 岁孩子可独立完成一次词汇选择 | 用户测试 |
| 6 | 无 P0/P1 阻断 bug | Bug 追踪 |
| 7 | RISK-0001 (inkgd) 和 RISK-0002 (rename) 已验证 | 设备验证报告 |

### Timeline

| Week | Focus | Key Deliverables |
|------|-------|-----------------|
| Week 1 (May 12-16) | Foundation 层 | SaveSystem ✅, ProfileManager, VocabStore, inkgd 验证 |
| Week 2 (May 19-23) | Core 层 + 美术 | AnimationHandler, TtsBridge, 美术资产到位 |
| Week 3 (May 26-30) | Vertical Slice | 完整核心循环, 用户测试, Go/No-Go 决策 |

---

## Acceptance Criteria

- [ ] All Go/No-Go Criteria above are met
- [ ] Vertical Slice 可在 Android 真机上独立运行
- [ ] 4 岁孩子用户测试通过（至少 1 名）
- [ ] 无 P0/P1 bug
