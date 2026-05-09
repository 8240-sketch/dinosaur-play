# Accessibility Requirements: 恐龙叙事英语启蒙游戏

> **Status**: Committed
> **Author**: gate-check / art-bible
> **Last Updated**: 2026-05-09
> **Accessibility Tier Target**: Basic
> **Platform(s)**: Android (API 24+)
> **External Standards Targeted**:
> - WCAG 2.1 Level A (儿童产品基线)
> - Google Android Accessibility Guidelines
> **Accessibility Consultant**: None engaged
> **Linked Documents**: `design/gdd/systems-index.md`, `design/ux/interaction-patterns.md`, `design/art/art-bible.md`

> **Why this document exists**: 面向 4–6 岁幼儿的产品，无障碍 = 可用性。一个触摸目标间距不够的按钮，对成人是"不方便"，对 4 岁孩子是"点不到"。本文件定义项目级无障碍承诺，per-screen 注解在各 UX spec 中。

---

## Accessibility Tier Definition

### 本项目的承诺

**Target Tier**: Basic

**Rationale**: 本游戏面向 4–6 岁中文母语幼儿（主操作者），操作方式为纯触屏点击。Basic tier 满足以下核心需求：

1. **视觉可读性**：幼儿视觉发育未完全，WCAG AA（4.5:1）对比度是最低要求
2. **色觉安全**：约 8% 男性有色觉缺陷，所有语义色彩必须有非颜色备份
3. **触摸目标**：幼儿手指比成人粗，最小 96dp 触控目标（超过 WCAG 44dp 最低标准）
4. **无闪烁**：光敏性癫痫风险——所有动画频率 < 3Hz
5. **TTS 降级**：当 TTS 不可用时，文字高亮必须足以替代语音

**Features explicitly in scope (beyond tier baseline)**:
- 最小触摸目标 96dp（高于 Standard tier 的 48dp 要求）
- 所有语义色彩均有图标/形状/动画备份（超越 Basic 要求）

**Features explicitly out of scope**:
- 屏幕阅读器（TalkBack）支持——目标用户为 4–6 岁幼儿，不使用屏幕阅读器
- 输入重映射——纯触屏，无需重映射
- 字体大小调节——字号已为幼儿优化固定

---

## Visual Accessibility

| Feature | Target Tier | Scope | Status | Implementation Notes |
|---------|-------------|-------|--------|---------------------|
| 最小文字尺寸 — 英文单词 | Basic | 所有词汇选择界面 | Not Started | 28sp 加粗（art-bible Section 7 定义）|
| 最小文字尺寸 — 中文翻译 | Basic | 所有词汇选择界面 | Not Started | 14sp 常规，灰色 |
| 最小文字尺寸 — 对话文字 | Basic | 所有对话界面 | Not Started | 20sp 常规，最小 18sp |
| 文字对比度 — 主文字 on 背景 | Basic | 所有 UI 文字 | Not Started | `#2D2A26` on `#FFF8F0` = 对比度 12.5:1（远超 WCAG AA 4.5:1）|
| 文字对比度 — 中文翻译 | Basic | 词汇选择界面 | Not Started | `#8C8578` on `#FFF8F0` = 对比度 3.8:1（接近 WCAG AA 4.5:1，建议加深至 `#7A756A`）|
| 色彩非唯一指示器 | Basic | 所有语义色彩 | Not Started | 所有语义色彩均有图标/形状/动画备份（art-bible Section 2 定义）|
| 闪烁/频闪限制 | Basic | 所有动画、VFX | Not Started | 所有动画频率 < 3Hz。无频闪效果。CPUParticles2D 粒子运动缓慢 |
| UI 缩放 | Basic | 所有 UI 元素 | Not Started | Godot 自动缩放适配不同屏幕密度，固定 360×800dp 设计基准 |

### Color-as-Only-Indicator Audit

| 位置 | 色彩信号 | 传达含义 | 非颜色备份 | 状态 |
|------|---------|---------|-----------|------|
| 词汇选项按钮 | 暖橙 = 可交互 | 按钮可点击 | 圆角矩形形状 + 图标 + 按下弹性动画 | Not Started |
| 金星图标 | 暖绿 = 词汇已学会 | 学习进度 | 星形图标形状 + 弹跳动画 | Not Started |
| confused 反馈 | 琥珀 = 温和提示 | 选项不匹配 | T-Rex confused 表情 + 肢体动画 | Not Started |
| TTS 高亮 | 亮黄 = 语音播放中 | TTS 状态 | 文字加粗 + 放大 + 词汇背景发光 | Not Started |

---

## Motor Accessibility

| Feature | Target Tier | Scope | Status | Implementation Notes |
|---------|-------------|-------|--------|---------------------|
| 最小触摸目标 | Basic (已超越) | 所有可交互元素 | Not Started | 96dp × 96dp 最小（art-bible 定义，超过 WCAG 44dp 和 Android 48dp 标准）|
| 触摸目标间距 | Basic | 所有相邻可交互元素 | Not Started | ≥ 16dp 间距（幼儿手指更粗，误触率更高）|
| 交互方式 | Basic | 全局 | Not Started | 仅点击（tap），无滑动/拖拽/捏合——降低运动精度要求 |
| 长按交互 | Basic | 家长入口（5 秒长按）| Not Started | 长按期间有视觉进度反馈（圆环填充），可随时取消 |
| 持续按住交互 | Basic | 录音按钮 | Not Started | 按住录音，松开停止。有明确的视觉状态指示（录音中脉冲动画）|

---

## Cognitive Accessibility

| Feature | Target Tier | Scope | Status | Implementation Notes |
|---------|-------------|-------|--------|---------------------|
| 无时间压力 | Basic | 所有游戏状态 | Not Started | 无倒计时、无时间限制——P2 Anti-Pillar |
| 单层导航 | Basic | 全局 | Not Started | 所有屏幕最多 1 层深度，大按钮导航 |
| 每屏信息量限制 | Basic | 所有屏幕 | Not Started | 幼儿屏幕同时呈现 ≤ 5 个可识别元素 |
| 选项数量限制 | Basic | 词汇选择 | Not Started | 每次最多 2 个选项（视觉二选一），降低决策负荷 |
| 错误无惩罚 | Basic | 所有选择 | Not Started | 选错 → confused 动画（好笑）→ 鼓励重试，无扣分/无红色 |
| 文字最小化 | Basic | 所有幼儿界面 | Not Started | 幼儿界面以图标+表情为主，文字为辅助。4 岁孩子不识字 |
| 教程持久性 | Basic | 所有教程 | Not Started | 首次孵化流程可重复（从主菜单进入）|

---

## Auditory Accessibility

| Feature | Target Tier | Scope | Status | Implementation Notes |
|---------|-------------|-------|--------|---------------------|
| TTS 发音 | Basic | 所有词汇 | Not Started | 系统 TTS 播放英文单词发音 |
| TTS 降级 | Basic | TTS 不可用时 | Not Started | 文字黄色高亮替代语音（`--highlight-pulse`）|
| 独立音量控制 | Basic | BGM / SFX / TTS | Not Started | 三条独立音量滑块，持久化到档案 |
| 视觉反馈替代音频 | Basic | 所有音频关键事件 | Not Started | TTS 播放 → 词汇高亮发光；金星获得 → 弹跳动画；confused → 表情动画 |

### Gameplay-Critical SFX Audit

| 音效 | 传达含义 | 视觉备份 | 状态 |
|------|---------|---------|------|
| TTS 发音 | 英文单词发音 | 词汇背景亮黄高亮 + 文字加粗放大 | Not Started |
| 金星获得音效 | 词汇学习成功 | 金星图标弹跳 + 绿色粒子 | Not Started |
| confused 音效 | 选项不匹配 | T-Rex confused 表情 + 肢体动画 | Not Started |
| 按钮点击音效 | 交互确认 | 按钮弹性动画（0.95x → 1.05x → 1.0x）| Not Started |

---

## Platform Accessibility API Integration

| 平台 | API / 标准 | 计划功能 | 状态 | 说明 |
|------|-----------|---------|------|------|
| Android | AccessibilityService / TalkBack | 不支持 | N/A | 目标用户为 4–6 岁幼儿，不使用 TalkBack |
| Android | 系统 TTS | TTS 发音 + 降级 | Not Started | `DisplayServer.tts_speak()` + 文字高亮降级 |

---

## Per-Feature Accessibility Matrix

| 系统 | 视觉关注 | 运动关注 | 认知关注 | 听觉关注 | 已解决 | 说明 |
|------|---------|---------|---------|---------|--------|------|
| ChoiceUI | 选项按钮色彩对比 | 96dp 触摸目标 | 每次最多 2 选项 | TTS 发音 + 高亮降级 | Partial | 色彩非唯一指示器待验证 |
| StoryManager | 对话文字可读性 | 无（自动推进）| 信息量控制 | TTS 播放 | Partial | 文字尺寸已定义 |
| VoiceRecorder | 录音按钮可见性 | 按住操作 | 录音为可选邀请 | 录音回放 | Partial | 拒绝权限后静默禁用 |
| HatchScene | 蛋壳光效可见性 | 触屏触发 | 流程简单（触屏→破壳）| 破壳音效 | Partial | 光效频率需验证 < 3Hz |
| MainMenu | T-Rex 表情可辨识 | 大按钮导航 | 单层导航 | BGM + 音效 | Partial | — |
| VocabMap (Parent) | 金星图标可辨识 | 点击操作 | 信息密度较高（面向家长）| 录音回放 | Partial | 非幼儿操作，信息密度可接受 |

---

## Accessibility Test Plan

| 功能 | 测试方法 | 通过标准 | 负责人 | 状态 |
|------|---------|---------|--------|------|
| 文字对比度 | 自动化 — 对比度分析工具 | 所有主文字 ≥ 4.5:1；大文字 ≥ 3:1 | ux-designer | Not Started |
| 色盲模式 | 手动 — Coblis 模拟器 | 所有语义色彩在 3 种色盲模式下可区分 | ux-designer | Not Started |
| 触摸目标尺寸 | 手动 — 在目标设备上测量 | 所有可交互元素 ≥ 96dp × 96dp | qa-tester | Not Started |
| 闪烁频率 | 手动 — 逐帧检查动画 | 所有动画频率 < 3Hz，无频闪 | qa-tester | Not Started |
| TTS 降级 | 手动 — 关闭 TTS 后游戏流程 | 文字高亮正常显示，游戏可完整通关 | qa-tester | Not Started |
| 4 岁孩子测试 | 用户测试 — 独立操作 | 孩子可独立完成选择、导航、通关 | producer | Not Started |

---

## Known Intentional Limitations

| 功能 | 所需 Tier | 未包含原因 | 风险/影响 | 缓解方案 |
|------|----------|-----------|----------|---------|
| TalkBack 屏幕阅读器 | Standard | 目标用户为 4–6 岁幼儿，不使用屏幕阅读器 | 影响视障成人协助者 | 无——目标用户群体不适用 |
| 字体大小调节 | Standard | 字号已为幼儿优化固定 | 影响有低视力的幼儿 | 固定字号已足够大（最小 14sp）|
| 输入重映射 | Standard | 纯触屏操作，无需重映射 | 无 | N/A |
| 高对比度模式 | Comprehensive | v1 范围外 | 影响低视力用户 | 未来版本考虑 |

---

## Audit History

| 日期 | 审计员 | 类型 | 范围 | 发现摘要 | 状态 |
|------|--------|------|------|---------|------|
| 2026-05-09 | gate-check skill | 内部审查 | Pre-Production gate 无障碍检查 | Basic tier 已定义，核心视觉/运动/认知/听觉要求已文档化 | In Progress |

---

## Open Questions

| 问题 | Owner | 截止 | 解决方案 |
|------|-------|------|---------|
| 中文翻译文字 `#8C8578` 对比度 3.8:1 是否需要加深至 `#7A756A`（4.5:1）？ | ux-designer | 第 2 周 | 建议加深 |
| 蛋壳裂缝光效的闪烁频率是否 < 3Hz？需要逐帧验证 | technical-artist | 第 2 周 | 实现后验证 |
| 录音按钮"按住"交互对 4 岁孩子是否足够直觉？需用户测试 | producer | 第 4 周 | 用户测试验证 |
