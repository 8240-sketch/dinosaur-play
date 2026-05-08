# Review Log: MainMenu

---

## Review — 2026-05-08 — Verdict: MAJOR REVISION NEEDED → Revised (RF-1~RF-13 + R1~R8)

Scope signal: M
Specialists: game-designer, systems-designer, ux-designer, qa-lead, godot-gdscript-specialist, creative-director
Blocking items: 13 (RF-1~RF-13) | Recommended: 8 (R1~R8)
Summary: 第三轮审查，确认 2026-05-08 APPROVED 版本所有历史修复均在位。本轮新发现 13 个阻断项：(B1) PARENT_HOLD → PROFILE_SWITCHING 转换路径缺失——状态表标注切换器「可点击」但合法转换表无此路径，实现行为未定义；(B2) LAUNCHING_GAME 死状态——`change_scene_to_file()` 失败不触发 `chapter_load_failed`，无退出路径，游戏卡死；(B3) F-4 除零风险——测试注入 `PARENT_HOLD_DURATION=0.0` 时 `clamp(inf,0,1)=1.0` 立即跳转 ParentVocabMap；(B4) `begin_session()` 重复调用——Rule 12 仅保护「再来一次！」路径，「算了先歇会儿」→ 重新点击「出发冒险！」会再次执行 Rule 11c；(B5) 3 档布局零间距——槽3 右边缘 x=272 与家长按钮左边缘 x=272 重叠，必然误触；(B6) P2 支柱违反——LOAD_ERROR 出口按钮为纯文字，4-6 岁目标用户无法自主选择退出路径；(B7) `_deferred_confused` 标志未在 LOAD_ERROR 非延迟退出路径清除，ONE_SHOT 回调未断开，幽灵 `play_confused()` 在 IDLE 状态触发；(B8/B9/B10) 缺少 EC-5/EC-8/EC-10 对应的 AC；(B11) AC-23 缺 GUT spy 注入规格；(B12 新发现) PARENT_HOLD 状态下「出发冒险！」标注「可点击」但无合法转换路径；(B13 新发现) PROFILE_SWITCHING 状态下「出发冒险！」标注「可点击」但无合法转换路径。8 项推荐修复已同步应用（R1~R8）。4 项原 blocking 降级为 recommended（`trex_recognize` 规格交叉引用、家长发现机制→OQ-3、AC-22 客观标准、ProfileManager 信号订阅文档）。GDD AC 总数由 25 增至 28（新增 AC-26/27/28）。
Prior verdict resolved: 2026-05-08 APPROVED 所有历史修复均在位。
Action taken: 写入 main-menu.md RF-1~RF-13 + R1~R8 全部修复；Open Questions 新增 OQ-3；GDD 状态更新为 Approved — RF-1~RF-13 + R1~R8 applied 2026-05-08；review log 本条追加。

---

## Review — 2026-05-08 — Verdict: APPROVED

Scope signal: M
Specialists: game-designer, ux-designer, systems-designer (via /design-system), creative-director (CD-GDD-ALIGN gate)
Blocking items: 0 | Notes: 2
Summary: GDD 8/8 节全部完成。/design-system retrofit 模式重新撰写所有缺失节。CD-GDD-ALIGN 门 APPROVED WITH NOTES（无阻断项）。注意项：(1) Rule 8 非活跃档案金星"暂无数据"占位标注实施时必须与"0"并存；(2) AC-22 `trex_recognize` 动画质量人工评审条目已加入 Acceptance Criteria。
Prior verdict resolved: Yes — MAJOR REVISION NEEDED (2026-05-07) → APPROVED (2026-05-08)
Design decisions confirmed: begin_session()=MainMenu 调用；DG-2（非活跃金星缓存）推迟 v1.1；D1~D4 四项 UX 决策维持。
Action taken: 写入全部 8 个 GDD 节；GDD 状态更新为 Approved；systems-index 更新 MVP 进度 9/9。

---

## Review — 2026-05-07 — Verdict: MAJOR REVISION NEEDED

Scope signal: M
Specialists: game-designer, ux-designer, systems-designer, qa-lead, creative-director
Blocking items: 9 | Recommended: 5
Summary: GDD 完成度 1/8 节，Overview 存在两处与已锁定权威文档的直接数据冲突（BL-1 动画规格应为 trex_recognize 而非 IDLE；BL-2 档案槽上限应为 3 而非 2）。UX 层有三处针对 4-6 岁目标用户的可用性阻塞（长按无反馈、家长按钮尺寸/位置违反 80dp 标准、档案切换无可发现性设计）。系统层缺少完整状态机定义（6 个状态）和 9 处边界值规格。Acceptance Criteria 全部缺失，且长按测试钩子未设计。
Prior verdict resolved: No — 首次审查
Design decisions collected: 长按反馈=先弹气泡再长按；已通关章节=允许重玩；档案槽=头像+名字+词汇金星；家长按钮=纯图标。
Action taken: 运行 /design-system 重新撰写 GDD。
