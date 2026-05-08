# VocabPrimingLoader

> **Status**: Approved — CD-GDD-ALIGN APPROVED WITH NOTES 2026-05-08; N-1 applied (Pillar P3→P4); N-2 applied (art intent anchor); N-3 applied (SFX intent); N-4 applied (OQ-3 priority/timing)
> **Author**: user + agents
> **Last Updated**: 2026-05-08
> **Implements Pillar**: P1（看不见的学习）、P4（家长是骄傲见证者）

## Overview

VocabPrimingLoader 是章节开始前短暂出现的词汇预热动画屏，将本章 5 个英文单词以卡片形式逐一呈现给孩子，并同步展示每个词当前的金星积累状态（来自 `VocabStore.get_gold_star_count(word_id)`）。数据层：在 `_ready()` 中批量查询 VocabStore，以 Tween 协程驱动卡片序列动画，完成后 `queue_free()` 自清理并通知父节点继续进入章节。玩家层：孩子在进入故事前看到熟悉的词汇老朋友——已获得金星的词有发光标记，新词以新鲜面孔亮相，整个序列在 5–8 秒内完成，既让孩子有「准备好了」的仪式感，也让家长扫一眼就知道今天要练哪些词（P4）。整个屏幕是单向播放：无交互，无跳过，自动结束（P1——进度展示，不是测试）。

## Player Fantasy

进入故事前，孩子不是在「复习单词」——他们是在接收进入恐龙世界的密语。

每张卡片从光中浮现，是恐龙语的一个音节。孩子已经掌握的词发出温柔的光晕（那是已经解锁的咒语）；从未见过的词是崭新的符文，即将在这次冒险中第一次亮相。5张卡片落定的瞬间，孩子的全套「本次通行密语」准备完毕，故事自动开启。

孩子不会说「我在预习」——他们只知道「出发前会有一个仪式」，而仪式结束了冒险就来了。正确与否不重要，掌握几个不重要，光是站在密语面前就足够（P1：学习隐形在仪式里）。

家长在旁边看到的是孩子的积累印记：哪些词已经闪光，哪些词还是新面孔。那不是成绩单，那是孩子在这个世界行走的足迹（P4）。

## Detailed Design

### Core Rules

1. **生命周期 — 实例化即启动**：VocabPrimingLoader 由 GameScene 在调用 `StoryManager.begin_chapter()` 之前实例化并通过 `add_child()` 加入场景树。节点加入树触发 `_ready()`，`_ready()` 完成后立即调用 `_start_sequence()`。不提供公开 `start()` 方法——加入场景树即意味着启动。父节点在 `add_child()` 之前以 `CONNECT_ONE_SHOT` 连接 `priming_complete` 信号。

2. **数据加载 — `_ready()` 静态快照**：在 `_ready()` 中，对 `VOCAB_WORD_IDS_CH1` 的全部 5 个词汇 ID 批量调用 `VocabStore.get_gold_star_count(word_id)`，将结果存入局部字典 `_star_counts: Dictionary`。此查询仅执行一次，动画播放期间不再重新查询（静态快照语义）。若 VocabStore 无活跃档案，`get_gold_star_count` 返回安全默认值 `0`，`_ready()` 照常继续。

3. **卡片预建**：数据查询完成后，`_ready()` 按 `VOCAB_WORD_IDS_CH1` 顺序实例化 5 个 `VocabCard` 子节点，调用 `card.setup(word_id, _star_counts[word_id])` 注入数据，并将每张卡片的 `modulate.a` 设为 `0.0`（全透明待显现）。卡片预先布局在固定位置，等待 Tween 按序淡入。

4. **动画序列 — 单 Tween 链，无 `await`**：`_start_sequence()` 调用 `create_tween()` 构造单条 Tween 链，包含以下完整序列：
   - 对 5 张卡片循环追加：`tween_property(card, "modulate:a", 1.0, CARD_APPEAR_SEC)` → `tween_interval(CARD_HOLD_SEC)`
   - 链尾追加：`tween_interval(ASSEMBLED_HOLD_SEC)` → `tween_property(self, "modulate:a", 0.0, FULL_FADE_SEC)` → `tween_callback(_on_sequence_complete)`
   - 不使用 `await tween.finished`，防止节点销毁时协程悬空。

5. **卡片累积显示**：卡片淡入后保持可见，不自动淡出。5 张卡片在屏幕上逐张累积，ASSEMBLED 阶段时全部同时可见，为孩子提供「今天的密语全套就位」的整体感（P1），并给家长一眼概览所有词汇（P4）。

6. **时序约束**：

   ```
   total_duration = CARD_COUNT × (CARD_APPEAR_SEC + CARD_HOLD_SEC)
                  + ASSEMBLED_HOLD_SEC + FULL_FADE_SEC
   ```

   当前值：`5 × (0.30 + 0.60) + 1.00 + 0.50 = 6.0 秒`，满足 5–8 秒约束。调整调节旋钮时必须验证 `total_duration ∈ [5.0, 8.0]`。

7. **金星视觉三级分层**：`VocabCard.setup(word_id, star_count)` 根据 `star_count` 与 `IS_LEARNED_THRESHOLD`（= 3，来自 `entities.yaml`）计算三级视觉状态：

   | 状态 | 条件 | 视觉表现 |
   |------|------|---------|
   | **FRESH**（新符文） | `star_count == 0` | 无光晕，无星图标，文字中性色 |
   | **PROGRESSING**（积累中） | `1 ≤ star_count < 3` | `star_count` 个半透明星图标，淡金色光晕 |
   | **MASTERED**（已解锁） | `star_count ≥ 3` | 满星，全强度金色光晕，文字呈暖金色 |

   `IS_LEARNED_THRESHOLD` 的权威值在 `entities.yaml` 中，`VocabCard` 引用不拥有此常量。

8. **无交互约束**：根节点（`CanvasLayer` 或 `Control`）设置 `mouse_filter = MOUSE_FILTER_STOP`。场景内不放置任何 `Button` 或 `TouchScreenButton`，不连接任何输入信号，不实现 `_input()` / `_unhandled_input()`。触屏事件在此层被静默消耗，无任何行为触发（P1：进度展示，不是测试）。

9. **中断容错 — 依赖 `SceneTree.paused`（策略 A）**：VocabPrimingLoader 不参与中断处理流程。InterruptHandler 触发时通过 `SceneTree.paused = true` 暂停整个场景树，Tween 随之暂停；恢复后继续播放。`priming_complete` 信号仍正常发出。VocabPrimingLoader 无需守卫超时或感知中断事件。

10. **信号契约与自清理**：`_on_sequence_complete()` 严格按顺序执行：① `priming_complete.emit()` ② `queue_free()`。信号签名：`signal priming_complete()`（无参数）。`queue_free()` 在 `priming_complete.emit()` 之后调用，保证信号传递先于节点移除。

---

### States and Transitions

| 状态 | 描述 | 进入条件 | 退出条件 |
|------|------|---------|---------|
| **INITIALIZING** | `_ready()` 执行：批量查询 VocabStore、实例化 5 个 VocabCard 并注入数据、设置 `modulate.a = 0.0`。同步操作，在单帧内完成。 | 节点加入场景树 | 同帧立即完成 → CARD_SEQUENCE |
| **CARD_SEQUENCE** | 单 Tween 链逐张淡入卡片（`CARD_APPEAR_SEC`）并停留（`CARD_HOLD_SEC`）。已显示的卡片保持可见（累积）。 | INITIALIZING 完成 | 第 5 张卡的 `CARD_HOLD_SEC` 结束 → ASSEMBLED |
| **ASSEMBLED** | 5 张卡全部可见，静止停顿（`ASSEMBLED_HOLD_SEC`）。金星卡辉光可见，新词卡呈「待学」样式。孩子建立「密语就位」整体感；家长一眼概览词汇（P4）。 | CARD_SEQUENCE 完成 | `ASSEMBLED_HOLD_SEC` 结束 → FADING_OUT |
| **FADING_OUT** | 整屏 `modulate.a` 线性降至 `0`（`FULL_FADE_SEC`）。Tween 完成后：① `priming_complete.emit()` ② `queue_free()`。 | ASSEMBLED 结束 | Tween 完成 → 节点销毁 |

单条 Tween 链内部驱动所有转换，无外部事件介入。线性单向：`INITIALIZING → CARD_SEQUENCE → ASSEMBLED → FADING_OUT → (销毁)`。

---

### Interactions with Other Systems

| 系统 | 方向 | 接口 | 说明 |
|------|------|------|------|
| **VocabStore**（AutoLoad） | 调用 | `get_gold_star_count(word_id: String) → int` | `_ready()` 中批量调用 5 次（每个 `VOCAB_WORD_IDS_CH1` 词一次）；静态快照，不在动画期间重复查询 |
| **GameScene**（父节点） | 上行信号 | `priming_complete()` | 父节点 `CONNECT_ONE_SHOT` 订阅；收到后调用 `StoryManager.begin_chapter()` |
| **InterruptHandler** | 无直接依赖 | — | 通过 `SceneTree.paused` 间接协作（策略 A）；VocabPrimingLoader 不感知中断事件 |
| **StoryManager** | 无直接依赖 | — | VocabPrimingLoader 不直接调用 StoryManager；由 GameScene 在收到 `priming_complete` 后代为调用 `begin_chapter()` |

## Formulas

```
total_duration = CARD_COUNT × (CARD_APPEAR_SEC + CARD_HOLD_SEC)
               + ASSEMBLED_HOLD_SEC + FULL_FADE_SEC
```

| 变量 | 类型 | 当前值 | 约束 |
|------|------|--------|------|
| `CARD_COUNT` | int | 5 | 固定（= `VOCAB_WORD_IDS_CH1` 长度） |
| `CARD_APPEAR_SEC` | float | 0.30 s | — |
| `CARD_HOLD_SEC` | float | 0.60 s | — |
| `ASSEMBLED_HOLD_SEC` | float | 1.00 s | — |
| `FULL_FADE_SEC` | float | 0.50 s | — |
| `total_duration` | float | **6.0 s** | 必须 ∈ [5.0, 8.0] |

**示例计算（当前默认值）**：
`5 × (0.30 + 0.60) + 1.00 + 0.50 = 4.50 + 1.50 = 6.0 秒` ✓

**边界说明**：各调节旋钮的安全范围已在 Tuning Knobs 章节中设定，以保证 `total_duration` 始终落在 [5.0, 8.0] 约束内。调整任一参数时须人工验证公式结果。

本系统无评分公式，无玩家可见数值运算。全部时序参数以 `const` 声明在类顶部。

## Edge Cases

| # | 场景 | 处理方式 |
|---|------|---------|
| E1 | `VocabStore` 无活跃档案（`_ready()` 时无 profile） | `get_gold_star_count()` 返回 `0`；全部 5 张卡片以 FRESH 状态显示；动画正常完成，`priming_complete` 正常发出 |
| E2 | `VocabStore.get_gold_star_count()` 对某个 `word_id` 返回 `0`（词汇从未出现过） | 该卡片以 FRESH 状态显示；其余卡片正常；不阻断序列 |
| E3 | App 转入后台（InterruptHandler 触发 `SceneTree.paused = true`）时 VocabPrimingLoader 处于 CARD_SEQUENCE 或 ASSEMBLED | Tween 随场景树暂停；节点不销毁；App 恢复后 Tween 继续；`priming_complete` 正常发出（策略 A） |
| E4 | GameScene 在动画播放期间主动销毁 VocabPrimingLoader（非正常路径，如强制场景切换） | Tween 随节点自动释放；`_on_sequence_complete` 回调不执行；`priming_complete` 不发出。GameScene 须自行处理 `begin_chapter()` 的触发（属于 GameScene 职责，不在此 GDD 范围） |
| E5 | 动画播放中 `VocabStore` 内部数据被更新（如词汇金星数变化） | 不影响——数据在 `_ready()` 中已静态快照；运行时不重新查询 |
| E6 | `VOCAB_WORD_IDS_CH1` 为空数组（极端配置错误） | 5 次循环不执行；Tween 链仍含 `tween_interval(ASSEMBLED_HOLD_SEC)` + `tween_property(fade)` + `tween_callback`；`priming_complete` 在 `ASSEMBLED_HOLD_SEC + FULL_FADE_SEC` 后正常发出；屏幕显示空白。此属配置错误，应在开发期 `assert(VOCAB_WORD_IDS_CH1.size() == 5)` 捕获 |

## Dependencies

### 上游依赖（本系统依赖这些系统）

| 系统 | 依赖类型 | 具体接口 |
|------|---------|---------|
| **VocabStore**（AutoLoad） | 方法调用 | `get_gold_star_count(word_id: String) → int`（`_ready()` 中批量调用 5 次） |

### 下游依赖（依赖本系统的系统）

| 系统 | 依赖类型 | 具体接口 |
|------|---------|---------|
| **GameScene**（父节点） | 信号订阅 | `priming_complete()` — 收到后调用 `StoryManager.begin_chapter()` |

### 双向声明要求

- **VocabStore GDD** 已声明 `get_gold_star_count(word_id)` 接口；VocabPrimingLoader 作为新调用方须在 VocabStore GDD 的 Interactions 表中补充（Open Questions #1）
- **StoryManager GDD** 中 `begin_chapter()` 的四步顺序约束不受 VocabPrimingLoader 影响——VocabPrimingLoader 在 `begin_chapter()` 调用之前完全结束，两者无重叠

## Tuning Knobs

| 常量 | 默认值 | 安全范围 | 影响的游戏体验 |
|------|--------|---------|-------------|
| `CARD_APPEAR_SEC` | 0.30 s | 0.15–0.50 s | 单张卡片淡入速度。过快（<0.15s）卡片闪现无仪式感；过慢（>0.50s）每张卡占时过长导致总时长超限 |
| `CARD_HOLD_SEC` | 0.60 s | 0.40–0.90 s | 卡片完全显示后停留时长。过短（<0.40s）孩子来不及看清词汇；过长（>0.90s）配合 5 张卡导致总时长超限 |
| `ASSEMBLED_HOLD_SEC` | 1.00 s | 0.60–1.50 s | 5 张全部可见后的整体停顿。此刻是孩子建立「密语就位」整体感的窗口；过短（<0.60s）整体感消失；过长（>1.50s）章节开始前等待感明显 |
| `FULL_FADE_SEC` | 0.50 s | 0.30–0.80 s | 整屏淡出时长。过快（<0.30s）突兀；过慢（>0.80s）叙事节奏拖沓 |

**联动约束**：调整任意参数后须验证：
```
5 × (CARD_APPEAR_SEC + CARD_HOLD_SEC) + ASSEMBLED_HOLD_SEC + FULL_FADE_SEC ∈ [5.0, 8.0]
```

建议单独调整时每次只改一个参数并验证公式结果仍在约束范围内。

## Visual/Audio Requirements

> **美术意图锚点**：卡片的感知目标是「法器从虚空中凝现」，而非「单词卡从底部弹出」。`modulate.a: 0→1` 的淡入是最低实现；美术可在此基础上叠加卡片发光边框的渐现、符文粒子散落等效果，使「从光中浮现」的意象落地。FRESH 状态的中性色不是「空白」，而是「尚未被孩子点亮的符文」——视觉上应有「等待被唤醒」的潜力感。最终判断依据：孩子第一次看到这个屏幕时，应该感觉像在进行一个仪式，而不是在背单词。

### 视觉

**VocabCard（单张卡片）**
- 背景：圆角卡片，`--surface-bg` 暖米白底色，带轻微阴影（体积感）
- 英文单词：居中大字，20–24sp 加粗（`--text-primary`）
- 金星状态视觉：
  - **FRESH**：无星图标，无光晕，文字 `--text-primary` 中性色
  - **PROGRESSING**：`star_count` 个半透明星图标（`--accent-dino` 淡金色），卡片边缘淡金色光晕（低不透明度）
  - **MASTERED**：满 3 星实心图标（`--accent-dino` 全亮度），卡片边缘强金色光晕，文字呈暖金色
- 卡片尺寸：宽约屏幕 80%，高适配内容（英文单词 + 金星区域）

**序列布局**
- 5 张卡片垂直排列，等间距居中布局；ASSEMBLED 时 5 张同时可见
- 若屏幕高度不足（小屏手机），卡片可缩小至最小 48dp 高（含内边距）
- 整屏背景：`--surface-bg` 或半透明遮罩（与 GameScene 背景区分，视美术决定）

**过渡**
- 单卡淡入：`modulate.a: 0→1`，`CARD_APPEAR_SEC`
- 整屏淡出：`modulate.a: 1→0`，`FULL_FADE_SEC`，线性

### 音频

| 事件 | 音频行为 |
|------|---------|
| 序列开始（CARD_SEQUENCE 进入） | 可选：柔和背景音（与 BGM 融合，低混音，≤−18dB） |
| 每张卡片淡入时 | 可选：轻微「卡片出现」音效（设计期可先留空） |
| MASTERED 卡片淡入时 | 可选：短暂金光音效（区分 FRESH/PROGRESSING）。**意图**：「已解锁的咒语展示自身魔力」，类似武器出鞘或魔法卡面被翻开的短促响声，而非「答题正确」的激励音。孩子听到时应感觉「这个符文认识我」，不是「我做对了」（P1 保护） |
| ASSEMBLED 停顿 | 静默（保留空间感，孩子扫视 5 张卡片） |
| 整屏淡出（FADING_OUT） | 可选：柔和过渡音效（回响/淡出） |
| 整屏消失后（`priming_complete` 发出） | 无音效（交由 GameScene / StoryManager 处理章节开场） |

**P1 约束**：无 TTS 朗读词汇——序列是仪式，不是发音练习。TTS 由 StoryManager 在章节内容中触发。

## UI Requirements

### 节点层级（参考结构）

```
VocabPrimingLoader (CanvasLayer / Control)
├── Background (ColorRect, --surface-bg 或半透明遮罩)
└── CardContainer (VBoxContainer, 垂直居中)
    ├── VocabCard_0 (Control / PanelContainer)
    │   ├── WordLabel (Label, 英文单词)
    │   └── StarRow (HBoxContainer, 星图标列)
    ├── VocabCard_1
    ├── VocabCard_2
    ├── VocabCard_3
    └── VocabCard_4
```

### 布局规则

1. VocabPrimingLoader 根节点铺满全屏（`AnchorPreset: Full Rect`）；`mouse_filter = MOUSE_FILTER_STOP` 消耗所有触屏输入
2. `CardContainer` 垂直居中（`grow_vertical = CENTER`），卡片间距 8–12dp
3. 每张 `VocabCard` 宽 ≥ 屏幕宽 80%，高 ≥ 48dp（可见内容区，含内边距 8dp）
4. `WordLabel` 字号 20sp 加粗，水平居中
5. `StarRow` 位于 `WordLabel` 下方，星图标尺寸 16–20dp，间距 4dp
6. 整屏 `modulate.a` 由 Tween 控制（淡出时作用于 VocabPrimingLoader 根节点自身）

### 状态可见性

| UI 元素 | INITIALIZING | CARD_SEQUENCE | ASSEMBLED | FADING_OUT |
|---------|-------------|--------------|-----------|------------|
| Background | 显（静） | 显（静） | 显（静） | 渐隐 |
| 当前动画卡片 | 隐（alpha=0） | 淡入→显 | 显（已全亮） | 渐隐（整屏） |
| 已完成卡片 | 隐 | 显（保留） | 显 | 渐隐（整屏） |
| 待动画卡片 | 隐（alpha=0） | 隐（alpha=0） | 显（已全亮） | 渐隐（整屏） |

### 触控规范

- 无任何可交互元素，无触控目标尺寸要求
- `mouse_filter = MOUSE_FILTER_STOP` 确保触屏事件不穿透至下层 GameScene

## Acceptance Criteria

所有 BLOCKING 条件必须通过；ADVISORY 条件在发布前确认。

**核心流程**

| # | 条件 | 类型 |
|---|------|------|
| AC-1 | GameScene 调用 `add_child(loader)` 后，VocabPrimingLoader 自动开始动画，无需外部 `start()` 调用 | BLOCKING |
| AC-2 | 5 张卡片按 `VOCAB_WORD_IDS_CH1` 顺序逐张淡入；每张卡片在前一张停留完成后才开始动画 | BLOCKING |
| AC-3 | 第 5 张卡片停留完成后，5 张卡片同时可见（ASSEMBLED）停顿 `ASSEMBLED_HOLD_SEC`，随后整屏淡出 | BLOCKING |
| AC-4 | 整屏淡出完成后，`priming_complete` 信号发出，节点 `queue_free()` 自清理 | BLOCKING |
| AC-5 | 总动画时长（默认参数）≤ 8 秒，≥ 5 秒 | BLOCKING |

**金星视觉分层**

| # | 条件 | 类型 |
|---|------|------|
| AC-6 | `get_gold_star_count() == 0` 的词汇，卡片无金色光晕，无星图标（FRESH 状态） | BLOCKING |
| AC-7 | `1 ≤ get_gold_star_count() < 3` 的词汇，卡片显示对应数量的半透明星图标和淡金色光晕（PROGRESSING 状态） | BLOCKING |
| AC-8 | `get_gold_star_count() ≥ 3` 的词汇，卡片显示满星实心图标和强金色光晕（MASTERED 状态） | BLOCKING |

**无交互**

| # | 条件 | 类型 |
|---|------|------|
| AC-9 | 动画播放期间，孩子触屏任意位置，动画不受干扰，无按钮响应，无跳过行为 | BLOCKING |
| AC-10 | 触屏事件不穿透至下层 GameScene（`mouse_filter = MOUSE_FILTER_STOP` 验证） | BLOCKING |

**容错**

| # | 条件 | 类型 |
|---|------|------|
| AC-11 | `VocabStore` 无活跃档案时，全部 5 张卡片以 FRESH 状态正常显示，序列正常完成 | BLOCKING |
| AC-12 | App 转入后台（`SceneTree.paused = true`）后恢复，动画从暂停点继续播放，`priming_complete` 正常发出 | BLOCKING |

**信号正确性**

| # | 条件 | 类型 |
|---|------|------|
| AC-13 | `priming_complete` 在 `queue_free()` 之前发出，父节点收到信号时节点仍有效 | BLOCKING |
| AC-14 | `priming_complete` 仅发出一次（Tween 链末尾 callback 触发一次） | BLOCKING |

**视觉规范**

| # | 条件 | 类型 |
|---|------|------|
| AC-15 | 5 张卡片在 ASSEMBLED 状态下全部同时可见，无卡片因透明或遮挡不可见 | ADVISORY |
| AC-16 | 每张卡片宽 ≥ 屏幕宽 80%，高 ≥ 48dp（在目标 Android 设备上验证） | ADVISORY |

## Open Questions

| # | 问题 | 优先级 | 解决时机 |
|---|------|--------|---------|
| OQ-1 | **VocabStore GDD 双向更新**：VocabPrimingLoader 调用 `get_gold_star_count(word_id)`，需在 VocabStore GDD 的 Interactions 表中补充 VocabPrimingLoader 为新调用方。 | LOW | 本 GDD 批准后核查 |
| OQ-2 | **GameScene 中途销毁策略**：Edge Case E4（GameScene 强制销毁 VocabPrimingLoader）中，GameScene 如何触发 `begin_chapter()` 由 GameScene 自身处理；建议 GameScene GDD 中声明此边界职责。 | LOW | GameScene 实现时确认 |
| OQ-3 | **小屏适配**：5 张卡片垂直排列在低端小屏（360dp × 640dp）上是否有足够空间？如高度不足，是否改为横向滚动或 2×3 网格布局？此计算无需等美术资产，现在即可验证（5×48dp 卡高 + 4×8dp 间距 = 272dp，余量约 250dp 用于背景/间距——需实测确认）。 | HIGH | **本 GDD 批准后立即计算，美术介入前确认布局方案**（Vertical Slice 前必须解决） |
