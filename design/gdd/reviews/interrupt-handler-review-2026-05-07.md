# GDD Review: InterruptHandler
**Date**: 2026-05-07
**Reviewer**: /design-review pipeline (systems-designer + qa-lead + game-designer + creative-director)
**Verdict**: NEEDS REVISION

---

## Summary

文档骨架扎实，Player Fantasy 优秀，VoiceRecorder 调用顺序正确（interrupt_and_commit BEFORE request_chapter_interrupt），P2 Anti-Pillar 在所有可见错误路径上均合规。但两类阻塞问题必须在实现前修复：

1. **规则步骤不完整**：Rule 4 和 Rule 5 的正式编号步骤遗漏关键状态变更，实现者按正式步骤写代码会产生静默 bug
2. **验收条件不可测**：四个 Blocking AC 涉及私有变量断言或缺席边缘场景覆盖，QA 无法签出

---

## Required Fixes (RF-1 to RF-8)

### RF-1 — CRITICAL — Rule 5：补充 `_back_button_pending = false`

**问题**：`_on_chapter_interrupted()` 表格中 `"user_back_button"` 行未包含 `_back_button_pending = false` 重置步骤。

**影响**：每次 back button 触发中断后，flag 永久锁定 3 秒（直到 timer 超时）。用户第二次按 back 会被 Rule 4 的 guard 拒绝，行为无声音失败。

**修复**：在 Rule 5 表格 `"user_back_button"` 行，在 flush 步骤之前明确加入：「`_back_button_pending = false`」。

---

### RF-2 — CRITICAL — Rule 4 正式步骤：补充状态变更和计时器启动

**问题**：`_unhandled_input` 的编号步骤（1-4）遗漏两件事，虽在"实现注意"中有提及，但不在正式步骤序列里：
- 步骤缺失：`_back_button_pending = true`（应在 `request_chapter_interrupt()` 之前）
- 步骤缺失：启动 BACK_BUTTON_GUARD_TIMEOUT_MS 超时计时器

同样适用于 WM_GO_BACK_REQUEST 路径。

**修复**：在 Rule 4 编号步骤中插入：
- 步骤 2.5（在 `request_chapter_interrupt()` 之前）：`_back_button_pending = true`
- 步骤 5（在 `request_chapter_interrupt()` 之后）：启动 timeout timer；同时补注：正常路径下信号同步触发，`_on_chapter_interrupted()` 会在步骤 5 的计时器启动之前将 flag 重置为 false；timeout timer 专为 E3（SM 未发出信号）的异常路径设计，timer 到期时检查 flag 仍为 true 再重置。

---

### RF-3 — SIGNIFICANT — 新增设计决策：Back Button UX

**问题**：4 岁孩子误触 back button 立即被弹出游戏，没有确认缓冲。当前 9 个 OQ 中无一提及此问题。`exit_confirmation_requested` 信号方案（OQ-9 候选）尚未列为待决议题。

**P2 影响**：Anti-Pillar P2 要求所有中断对孩子无感知。强制场景切换是有感知的中断——与 P2 存在真实矛盾。

**修复**：在 Open Questions 中追加 OQ-9，并标记为 DECISION REQUIRED（而非仅 "consider"）：

> **OQ-9 [DECISION REQUIRED]**：back button 是否需要确认层以防止 4 岁孩子误触？
> - **方案 A（推荐）**：IH emit `exit_confirmation_requested` 信号 → GameScene 负责渲染覆盖层（如 "T-Rex 想留下来！"），由孩子确认后才执行 `change_scene_to_file()`。成本：GameScene GDD 需同步声明此信号的订阅契约。
> - **方案 B**：维持即时跳转，接受 P2 在 back button 路径上的轻微违反。成本最低，但与 Anti-Pillar 存在矛盾。
> 
> 此决策不做出，GameScene GDD 无法完整定义 back button 的 UI 契约。

---

### RF-4 — SIGNIFICANT — Rule 3 FOCUS_IN：防止 profile_switch STOPPED 被误重置

**问题**：FOCUS_IN 路径调用 `confirm_navigation_complete()` 未检查 STOPPED 的来源。`profile_switch` 也会使 SM 进入 STOPPED，若此时 app 返回前台，IH 会错误地将 SM 重置为 IDLE，而实际上 profile_switch 流程尚未完成。

**修复**：在 Rule 3 FOCUS_IN 的 `confirm_navigation_complete()` 调用前，增加来源检查说明：

> 调用 `confirm_navigation_complete()` 前，IH 须确认 STOPPED 状态由 IH 自身发起（而非 `profile_switch` 引起）。实现方式：维护内部标志 `_ih_triggered_stop`，在 IH 调用 `request_chapter_interrupt()` 时置 `true`，在收到 `chapter_interrupted("profile_switch")` 时置 `false`（Rule 5 表格对应行补充此步骤）。仅当 `_ih_triggered_stop == true` 时 FOCUS_IN 路径才调用 `confirm_navigation_complete()`。

---

### RF-5 — SIGNIFICANT — AC-11 重写为可观测行为

**问题**：当前 AC-11 断言 `_back_button_pending == true` 私有变量，GUT 单元测试不可访问 GDScript 私有变量。

**修复**：删除 AC-11，替换为以下三条可观测 AC：

> **AC-11a**（单元/集成）：章节进行中连续两次触发 back button，间隔在 `BACK_BUTTON_GUARD_TIMEOUT_MS` 窗口内，`chapter_interrupted` 信号只发出一次。
> 
> **AC-11b**（单元/集成）：back button 触发后，等待 `BACK_BUTTON_GUARD_TIMEOUT_MS + 100ms`，再次触发 back button 可正常执行完整中断序列（`chapter_interrupted` 再次发出）。
> 
> **AC-11c**（集成）：SM 处于 COMPLETING 状态（`is_story_active == false`）时触发 back button，`BACK_BUTTON_GUARD_TIMEOUT_MS` 到期后 `push_warning` 被记录，此后 back button 恢复响应。

---

### RF-6 — SIGNIFICANT — 补充 4 个缺失 AC

追加以下 AC（编号接续当前 AC-17）：

> **AC-18**（集成）：`change_scene_to_file()` 返回 `err != OK` → `push_error` 记录，不调用 `confirm_navigation_complete()`，SM 维持 STOPPED；后续 FOCUS_IN 路径可将 SM 恢复至 IDLE（E9 覆盖）。
> 
> **AC-19**（单元）：`flush()` 返回 `false` → `push_error` 记录，IH 无崩溃，无孩子可见错误，中断流程完成。
> 
> **AC-20**（单元）：VoiceRecorder `is_instance_valid() == false`（权限被拒绝降级场景）→ 中断流程跳过 VoiceRecorder，继续执行 `request_chapter_interrupt()` 和 `flush()`，无崩溃。
> 
> **AC-21**（单元）：计时器 `wait_time` 属性值在 2.9–3.1 秒范围内（验证 `BACK_BUTTON_GUARD_TIMEOUT_MS / 1000.0` 换算正确，防止 3000 秒 bug）。

---

### RF-7 — SIGNIFICANT — 文档化 COMPLETING 状态的数据风险

**问题**：SM 处于 COMPLETING 状态时（`is_story_active == false`），若发生后台中断，IH 直接调用 `flush()`。但此时 `end_chapter_session()` 尚未完成，`completed_chapters` 标记可能缺席本次 flush。金星数据（RUNNING 阶段写入）安全；通关标记有丢失风险，影响 P4 家长视图。

**修复**：在 Edge Cases 中追加 E10，或在 E4 旁补注：

> **E10 — COMPLETING 阶段中断**：SM 处于 COMPLETING 时发生 FOCUS_OUT/PAUSED，`is_story_active == false`，IH 直接调用 `flush()`。`end_chapter_session()` 尚未完成，`completed_chapters` 标记可能未写入本次 flush（下次 session 恢复时将重新完成）。金星词汇进度（RUNNING 阶段已写入）不受影响。**设计决策**：接受此低概率丢失风险，或 IH 在 COMPLETING 状态下监听 `chapter_completed` 信号后再 flush。

---

### RF-8 — MINOR — Rule 2：指定信号连接模式

**问题**：`chapter_interrupted` 信号连接模式未指定。若实现者误用 one-shot 连接，第一次 back button 中断后连接断开，后续所有 back button 静默失效。

**修复**：在 Rule 2 中 `chapter_interrupted` 订阅说明处添加一行：「连接模式：持久（非 one-shot）。IH 在整个生命周期内监听此信号。」

---

## OQ 状态更新

以下 OQ 在当前 IH GDD 中标记为待解决，实际已由 StoryManager GDD（2026-05-07 补丁）解决：

| OQ | 状态 | 解决位置 |
|----|------|---------|
| OQ-1 | ✅ RESOLVED | story-manager.md Rule 13：`request_chapter_interrupt(reason)` |
| OQ-4 | ✅ RESOLVED | story-manager.md Rule 14：`confirm_navigation_complete()` |
| OQ-7 | ✅ RESOLVED | story-manager.md Interactions 表：`current_state` 为 public 只读属性 |

这三个 OQ 可在修订时标记为 RESOLVED，并注明 "story-manager.md 2026-05-07 patch"。

---

## Affirmations (保留原文，不修改)

- **Player Fantasy 段落**：「六个月后...Apple!...偏高、不确定」的具体未来情感时刻准确锚定 P3/P4，是本轮所有 GDD 中 Player Fantasy 写法的最佳范例
- **P2 Anti-Pillar 合规**：所有错误路径均为 `push_error`/`push_warning`，无孩子可见状态
- **VoiceRecorder 调用顺序**：`interrupt_and_commit()` 先于 `request_chapter_interrupt()` 的顺序设计正确，确保录音路径写入 P3 数据链

---

## Noise / Deprioritized

以下发现不阻塞修订，可在实现阶段处理：
- MINOR-8：`current_chapter_id` ghost dependency（文档清洁度）
- MINOR-9：F-1 变量表缺 `_background_flush_pending`（小补充）
- MINOR-10：「导航完成后」措辞（Godot 4 deferred 行为注释）
- SIGNIFICANT-7：E3 GDScript 单线程下理论可达性（RF-2 注释中已处理）
- QA WARNING 1-9：测试分类（实现阶段测试规划时处理）
- MINOR-12：COMPLETING 双重 flush（已被 RF-7 覆盖）

---

## Verdict Summary

| 类别 | 数量 |
|------|------|
| CRITICAL fixes | 2 (RF-1, RF-2) |
| SIGNIFICANT fixes | 5 (RF-3 through RF-7) |
| MINOR fixes | 1 (RF-8) |
| OQ resolutions | 3 (OQ-1, OQ-4, OQ-7) |
| Deprioritized | 7 |

**NEEDS REVISION — 修复 RF-1~RF-8 并更新 OQ-1/4/7 状态后，可重新提交审核。**
