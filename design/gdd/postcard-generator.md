# PostcardGenerator

> **Status**: Approved — CD-GDD-ALIGN APPROVED WITH NOTES 2026-05-08; N-1 applied (FRESH 待探索意图); N-2 applied (P3 分工说明); N-3 applied (OQ-4 30s Pass/Fail 标准)
> **Author**: user + agents
> **Last Updated**: 2026-05-08
> **Implements Pillar**: P3（声音是成长日记）、P4（家长是骄傲见证者）

## Overview

PostcardGenerator 是章节通关后自动触发的一次性图像生成工具，将本次通关的成果固化为一张 1080×1080 像素的恐龙明信片 PNG，并保存至 Android 系统图库。数据层：订阅 `StoryManager.chapter_completed` 信号，由 GameScene 实例化，查询 `ProfileManager`（孩子姓名）和 `VocabStore`（5 个词的金星数量），通过 `SubViewport` 将固定明信片模板场景渲染为 `Image`，调用 `OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)` 定位 Android 图库目录，以 `FileAccess` 写入 PNG 文件，完成后 `queue_free()` 自清理（参见 ADR-0003 关于 Android 图库存储方案和媒体扫描风险）。玩家层：通关结束时，手机相册里多出一张孩子名字打在上面、5 个恐龙词汇金星状态一目了然、T-Rex 站在正中央的明信片——家长打开微信朋友圈就能分享（P4）；孩子在六个月后看到自己曾经学过的词，那时已经全是金星了（P3 记忆锚点）。生成流程对孩子不可见；家长在孩子通关后在系统相册里发现这张卡片。

**参见 ADR-0003**（`docs/architecture/adr-0003-android-gallery-save.md`）关于 `OS.get_system_dir` 在 Android API 24–34 上的行为和媒体扫描 (`MediaStore`) 备选方案。

**P3 分工说明**：PostcardGenerator 承担 P3（声音是成长日记）的**视觉记忆维度**——明信片将通关成果固化为相册时间戳，是孩子成长轨迹的视觉章节。P3 的**声音维度**（录音回放、孩子声音存档）由 VoiceRecorder 系统承担。两者协同构成完整的成长日记体验。

## Player Fantasy

孩子通关的时候，家长未必在看屏幕。通关发生在孩子那边，游戏在走，孩子在玩；而家长在另一个时刻，翻照片、找截图，或者只是无意识地往上滑。就在那里——一张从没见过的图静静躺着：霸王龙站在正中央，孩子的名字印在上面，五个英文词整整齐齐排在两侧，每个词旁边各跟着一颗金色的星。没有弹窗，没有推送通知，没有人告诉家长去看。明信片就这样出现了，等着这个偶然的目光。

金星不需要说明。有几颗星是实心的，有几颗还只是轮廓，家长一眼就能看懂——不需要先理解任何评分规则，不需要问孩子「这个答对了没有」。那五个词是今天学到的词，星的状态是今天的进展，明信片把全部信息都说清楚了，没有多余的东西需要解读。家长当下就想把这张图发出去——发给另一半，发到朋友圈，可以一个字的注释都不写，图本身就在说：孩子今天学会了霸王龙，剩下几个词还在路上。

半年之后，家长在相册里又翻到这张明信片。孩子凑过来，指着霸王龙说了声「T-Rex」，语气里没有任何迟疑，像在叫一个早就认识的老朋友。当时那五个词只有两颗是满星，现在全都亮着了。家长想的不是孩子进步了多少，而是那个下午本身的样子——孩子还小，那些词还是陌生的，那是第一次与霸王龙相遇。这张明信片不会改变，一直在相册里，等着被再次翻到，再次想起。

## Detailed Design

### Core Rules

1. **一次性节点身份**：PostcardGenerator 是普通节点（非 AutoLoad），由 GameScene 在收到 `StoryManager.chapter_completed` 信号后立即实例化并 `add_child`。生命周期单向线性：实例化 → 数据查询 → SubViewport 构建 → 数据注入 → 等待渲染 → 图像写入 → `queue_free()`，不允许重用或重置。GameScene 设 `_postcard_generating: bool` guard，防止同一章节内重复实例化；`postcard_saved` 或 `postcard_failed` 信号触发后重置此 guard。

2. **数据查询 — `_ready()` 内同步完成**：所有上游数据在 `_ready()` 中同步查询，不延迟，不 `await`：`ProfileManager.get_section("profile").get("name", "")` 获取孩子姓名；对 `VOCAB_WORD_IDS_CH1` 全部 5 词调用 `VocabStore.get_gold_star_count(word_id)`，结果存入 `_star_counts: Dictionary`。降级规则：姓名为空字符串时继续生成（模板名字字段留空）；单词金星查询失败时该词计为 0 星，继续生成。数据缺失不触发整体中止（P4：降级卡片优于不生成卡片）。时机依据：StoryManager 的 `VocabStore.end_chapter_session()` 在 `chapter_completed` 发出前已调用，金星数据已结算，无竞争窗口。

3. **SubViewport 构建与数据注入顺序（四步顺序约束）**：以下四步全部在 `_generate()` 协程的首个 `await` 之前完成，顺序不可调换：
   - **(a)** 创建 SubViewport → 设置 `size = Vector2i(1080, 1080)` → 设置 `render_target_update_mode = SubViewport.UPDATE_ALWAYS` → `add_child(viewport)`
   - **(b)** `load("res://scenes/postcard/Postcard.tscn")` → 实例化 → `viewport.add_child(postcard_instance)`；加载失败 → 直接转静默失败（Rule 5）
   - **(c)** 调用 `postcard_instance.setup(_child_name, _star_counts)` 注入全部数据；**注入必须在 `await` 前完成**，否则渲染空数据
   - **(d)** `await get_tree().process_frame`（等待渲染队列提交）→ 再次 `await get_tree().process_frame`（等待 GPU 命令执行完毕，防范低配 Android GPU 延迟返回空图）

4. **图像获取与文件写入**：两帧等待后执行：`viewport.get_texture().get_image()` 获取图像；若 `img == null` 或 `img.is_empty()` → 静默失败；`DirAccess.make_dir_recursive_absolute(dir_path)` 创建目录，失败 → 静默失败；`FileAccess.open(path, FileAccess.WRITE)` 打开文件，返回 `null` → 静默失败；`fa.store_buffer(img.save_png_to_buffer())` 写入，`fa.close()`。

5. **静默失败策略**：以下所有异常路径均静默处理，不向孩子展示任何 UI 变更：

   | 失败场景 | 处理方式 |
   |---------|---------|
   | `OS.get_system_dir` 返回空字符串 | `push_warning` → 尝试 Fallback 路径（见 Rule 6）|
   | `Postcard.tscn` 加载失败 | `push_warning` → `_finish(false, "scene_load")` |
   | SubViewport 图像为空 | `push_warning` → `_finish(false, "empty_image")` |
   | 目录创建失败 | `push_warning` → `_finish(false, "mkdir_failed")` |
   | `FileAccess.open` 返回 null | `push_warning` → `_finish(false, "file_open")` |
   | 磁盘写入异常（磁盘满） | `push_warning` → `_finish(false, "write_error")` |

   理由：P4 语境下失败是"家长未能在相册发现卡片"，不是"孩子看见报错"，通关体验不可被打断。

6. **文件路径规则**：
   - 主路径：`OS.get_system_dir(OS.SYSTEM_DIR_PICTURES) + "/TRexJourney/"` （API 24–28 可靠）
   - Fallback 路径：若主路径不可写，回退至 `OS.get_user_data_dir() + "postcards/"` （应用沙盒内部存储，始终可写；API 29+ Scoped Storage 应对方案，详见 ADR-0003）
   - 文件名格式：`postcard_ch{N}_{YYYYMMDD_HHmmss}.png`，时间戳来自 `Time.get_datetime_string_from_system()`，去除 `":"` `"-"` `"T"` 特殊字符
   - Rule 1 的 guard 确保同一会话内同秒不存在两个实例，无需额外后缀处理重名

7. **信号契约与 `queue_free()`**：所有路径统一经由 `_finish(success: bool, reason: String)` 退出：成功时 `emit postcard_saved(path: String)`；失败时 `emit postcard_failed(reason: String)`；两者之后均调用 `queue_free()`。两个信号仅供调试与未来崩溃日志分析，**GameScene 不监听也能正常运行**。信号不触发任何面向孩子的 UI 变更。

---

### States and Transitions

| 状态 | 描述 | 进入条件 | 退出条件 |
|------|------|---------|---------|
| **IDLE** | 节点已实例化，等待引擎调用 `_ready()` | 节点 `add_child` 后的初始状态 | 引擎调用 `_ready()` |
| **QUERYING** | `_ready()` 同步查询 ProfileManager 和 VocabStore 数据 | `_ready()` 开始执行 | 所有查询完成（成功或降级）；`_generate()` 协程启动 |
| **BUILDING** | 创建 SubViewport、加载 Postcard.tscn、注入数据（Rule 3 步骤 a–c） | QUERYING 完成且进入 `_generate()` 协程 | 注入完成进入 `await`；或 Postcard.tscn 加载失败 → FAILED |
| **AWAITING_RENDER** | 等待两帧 GPU 渲染完成 | BUILDING 注入步骤完成 | 第二帧返回；或图像为空 → FAILED |
| **WRITING** | 获取 Image，写入 PNG 至 Android 图库 | AWAITING_RENDER 两帧返回且 Image 有效 | 写入成功 → DONE；写入失败 → FAILED |
| **DONE** | 生成成功，emit `postcard_saved`，准备销毁 | WRITING 成功完成 | `queue_free()` 后节点销毁 |
| **FAILED** | 任意静默失败路径，emit `postcard_failed`，准备销毁 | 任意 Rule 5 异常路径触发 | `queue_free()` 后节点销毁 |

```
IDLE → QUERYING → BUILDING → AWAITING_RENDER → WRITING → DONE
                     ↓              ↓               ↓
                   FAILED ←─────────────────────── FAILED
```

---

### Interactions with Other Systems

| 系统 | 方向 | 接口 | 说明 |
|------|------|------|------|
| **StoryManager**（via GameScene） | 触发源 | `chapter_completed(chapter_id: String)` 信号 | GameScene 订阅此信号，实例化 PostcardGenerator；PostcardGenerator 本身不直接依赖 StoryManager |
| **ProfileManager**（AutoLoad） | 调用 | `get_section("profile").get("name", "")` | `_ready()` 中查询孩子姓名；空字符串时降级继续 |
| **VocabStore**（AutoLoad） | 调用 | `get_gold_star_count(word_id: String) → int`（× 5） | `_ready()` 中批量查询 5 个词的金星数；查询失败时降级为 0 |
| **GameScene**（父节点） | 上行信号 | `postcard_saved(path)` / `postcard_failed(reason)` | 仅供调试；GameScene 不监听也能正常运行 |
| **InterruptHandler** | 无直接依赖 | — | PostcardGenerator 在通关后生成，通关时 GameScene 已结束 Story 循环；若 App 转后台恰好在 AWAITING_RENDER 帧等待期间，`SceneTree.paused` 暂停帧处理，`await process_frame` 自动延迟到恢复后继续执行 |

## Formulas

**D1 — 金星视觉等级映射**

```
star_tier(star_count) =
  FRESH       if star_count == 0
  PROGRESSING if 1 ≤ star_count < IS_LEARNED_THRESHOLD
  MASTERED    if star_count ≥ IS_LEARNED_THRESHOLD
```

| 变量 | 类型 | 来源 | 值 |
|------|------|------|-----|
| `star_count` | int | `VocabStore.get_gold_star_count(word_id)` | 0–∞（实际上限由 VocabStore 约束） |
| `IS_LEARNED_THRESHOLD` | int | `entities.yaml`（权威定义，此 GDD 引用不拥有） | 3 |

示例：`star_count = 2` → `2 < 3` → PROGRESSING（2 颗半透明星，淡金色光晕）

**D2 — 文件名时间戳格式**

```
timestamp = Time.get_datetime_string_from_system()
            .replace(":", "")
            .replace("-", "")
            .replace("T", "_")

filename = "postcard_ch" + chapter_num + "_" + timestamp + ".png"
```

| 变量 | 类型 | 说明 |
|------|------|------|
| `chapter_num` | String | 从 `chapter_id` 提取，如 `"ch1"` → `"1"` |
| `timestamp` | String | 格式 `YYYYMMDD_HHmmss`（秒级精度，确保同一会话内无重名） |

示例：`chapter_id = "ch1"`，生成时刻 `2026-05-08T14:30:22` → `postcard_ch1_20260508_143022.png`

本系统无评分公式，无玩家可见数值运算。全部路径常量以 `const` 声明在类顶部。

## Edge Cases

| # | 场景 | 处理方式 |
|---|------|---------|
| E1 | `OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)` 返回空字符串（Android API 29+ Scoped Storage 或特殊设备） | 回退至 `OS.get_user_data_dir() + "postcards/"`；若此路径也不可写，`_finish(false, "no_dir")`，静默失败 |
| E2 | `ProfileManager` 无活跃档案（`_ready()` 时 profile 未加载） | `get("name", "")` 返回空字符串；继续生成，Postcard 名字字段显示为空；不阻断生成（P4：卡片比无卡片更好） |
| E3 | `VocabStore.get_gold_star_count()` 对某 `word_id` 返回 0（词汇从未出现） | 该词以 FRESH 状态渲染（无星，无光晕）；其余词正常；不阻断 |
| E4 | `Postcard.tscn` 中字体或贴图在 Release 包首帧未完成 GPU Upload（Android Release 资源缓存延迟） | 等待两帧（Rule 3d）已覆盖大多数情况；QA 阶段在 Release 包真机截图验证；若仍出现灰块，增加等待帧至 3 帧（见 Tuning Knobs） |
| E5 | App 转入后台（InterruptHandler 触发 `SceneTree.paused = true`）时 PostcardGenerator 处于 AWAITING_RENDER | `await get_tree().process_frame` 随场景树暂停；App 恢复后继续执行；`_finish()` 正常发出信号（框架保证，无需额外处理） |
| E6 | 磁盘空间不足，`store_buffer()` 写入失败 | `push_warning("postcard: disk full")`；`_finish(false, "write_error")`；静默失败；不向孩子展示任何 UI |
| E7 | GameScene 在生成期间被销毁（极端路径，如强制场景切换） | PostcardGenerator 随父节点销毁，`await` 自动中止；`_finish()` 不执行；磁盘上不留残片（未完成的写入缓冲随进程清理） |
| E8 | 同一章节内 `chapter_completed` 信号发出两次（异常情况） | GameScene `_postcard_generating` guard（Rule 1）阻止第二次实例化；PostcardGenerator 层无需防护 |
| E9 | `chapter_id` 字符串无法解析出章节编号（如空字符串或非预期格式） | `chapter_num` 默认为 `"unknown"`；文件名退化为 `postcard_chunknown_{timestamp}.png`；文件仍写入，不阻断 |

## Dependencies

### 上游依赖（本系统依赖这些系统）

| 系统 | 依赖类型 | 具体接口 |
|------|---------|---------|
| **ProfileManager**（AutoLoad） | 方法调用 | `get_section("profile").get("name", "")` — `_ready()` 中调用一次 |
| **VocabStore**（AutoLoad） | 方法调用 | `get_gold_star_count(word_id: String) → int` — `_ready()` 中批量调用 5 次 |
| **StoryManager**（via GameScene） | 信号（间接） | `chapter_completed(chapter_id)` — PostcardGenerator 不直接订阅；由 GameScene 代为监听并实例化 PostcardGenerator |

### 下游依赖（依赖本系统的系统）

无。PostcardGenerator 是 Polish/Output 层末端节点，无其他系统依赖其输出。

### 双向声明要求

- **ProfileManager GDD** 已声明 `get_section("profile")` 接口；PostcardGenerator 作为新调用方须在 ProfileManager GDD 的 Interactions 表中补充（Open Questions OQ-1）
- **VocabStore GDD** 已声明 `get_gold_star_count(word_id)` 接口；PostcardGenerator 作为新调用方须在 VocabStore GDD 的 Interactions 表中补充（Open Questions OQ-1）
- **StoryManager GDD** 已声明 `chapter_completed` 信号；GameScene 作为订阅方已在 StoryManager GDD 中；PostcardGenerator 通过 GameScene 间接触发，无需额外更新 StoryManager GDD

## Tuning Knobs

| 常量 | 默认值 | 安全范围 | 影响的行为 |
|------|--------|---------|-----------|
| `RENDER_WAIT_FRAMES` | 2 | 2–4 | SubViewport 渲染后等待帧数。值过低（< 2）→ 低配 Android GPU 延迟导致 `get_image()` 返回空图；值过高（> 4）→ 无意义延迟（E4 对策调节旋钮） |
| `SUBDIR_NAME` | `"TRexJourney"` | 任意有效目录名 | Pictures 目录下的品牌子目录名；修改时注意已有卡片将散落在旧目录 |
| `FALLBACK_SUBDIR` | `"postcards"` | 任意有效目录名 | Scoped Storage fallback 时的子目录名（位于 `user_data_dir` 下） |

**调节旋钮不含视觉参数**：Postcard 模板（背景颜色、字号、布局间距等）全部封装在 `Postcard.tscn` 和 `VocabCardPanel.tscn` 场景内，由美术直接修改场景资产，不通过 PostcardGenerator 常量控制。

## Visual/Audio Requirements

> **美术意图锚点**：明信片是「冒险纪念品」而非「成绩单」。T-Rex 必须是最大的视觉元素，超过词汇区总面积——T-Rex 主导时，整张卡片是冒险感；词汇卡主导时，整张卡片变成测验感。金星状态通过图标数量（而非仅颜色）传达——满足色盲可用性。家长打开微信朋友圈时，图本身即说清楚一切，无需配文。

**视觉规格（Postcard.tscn — 1080×1080px 画布）**

明信片分为四个垂直区块：

| 区块 | y 范围 | 高度 | 内容 |
|------|--------|------|------|
| **标题带** | 0–120px | 120px | 孩子姓名（左，52px 加粗）+ 生成日期（右，28px 浅灰） |
| **T-Rex 主视觉** | 120–640px | 520px | T-Rex 居中，最大宽度 540px（占画布 50%），底部略入词汇区制造层叠感；T-Rex 周围淡暖金色放射状光晕（alpha 0.3→0） |
| **词汇卡区** | 600–910px | 310px | 5 张词汇卡按 2+3 布局（上排 2 张 × 440×130px；下排 3 张 × 280×110px） |
| **底部签章带** | 910–1080px | 170px | 品牌图标 + 项目名（小字）+ 成就标语「Chapter 1 · 5 words explored」 |

**词汇卡（VocabCardPanel）金星三级视觉**

| 状态 | 条件 | 视觉表现 |
|------|------|---------|
| **FRESH** | `star_count == 0` | 中性冷灰描边，无星图标，无光晕，文字白色。**美术意图**：FRESH 应传达「待探索」而非「空白/缺席」，避免家长将零星解读为「学习失败」。美术实现时建议在冷灰底色上叠加一个轻量视觉提示（如细小「?」轮廓或恐龙爪印纹理），与 PROGRESSING 形成「待探索 → 进行中 → 完成」的有意义渐进 |
| **PROGRESSING** | `1 ≤ star_count < 3` | 淡金色描边，`star_count` 颗半透明星（28×28px），淡金色内发光 |
| **MASTERED** | `star_count ≥ 3` | 金色描边，3 颗实心满星，强金色内发光，文字暖金色 |

字号规格：上排词汇卡英文单词 52px 加粗（全大写）；下排词汇卡 40px 加粗（全大写）。

**家长视线路径（扫一眼优先级）**

```
第1眼（0–300ms）：T-Rex 图形 — 最大面积，本能注意
第2眼（300–700ms）：孩子姓名（左上）— 确认「这是谁的」
第3眼（700ms–1.5s）：词汇卡区 — MASTERED 词金色光晕先被捕获
第4眼（1.5s+）：底部签章 — 可选，作为出处被阅读
```

**音频**

PostcardGenerator 生成过程对孩子完全不可见，无任何音效。

## UI Requirements

PostcardGenerator 不是游戏内交互界面，`Postcard.tscn` 是专用于 SubViewport 离屏渲染的模板场景，不加入可见场景树。

**Godot 节点树（参考结构）**

```
Postcard (Control, 1080×1080)
├── Background (TextureRect / ColorRect)         ← 背景渐变或纹理
├── HeaderBand (Control, y=0, h=120)
│   ├── ChildName (Label)                        ← 孩子姓名，52px 加粗
│   └── DateLabel (Label)                        ← 生成日期，28px 浅灰
├── TRexArea (Control, y=120, h=520)
│   ├── TRexGlow (TextureRect)                   ← 光晕 sprite，alpha 叠加
│   └── TRexSprite (TextureRect)                 ← T-Rex 主图
├── VocabCardsContainer (Control, y=600, h=310)
│   ├── TopRow (HBoxContainer)                   ← 2 张词汇卡，440×130px
│   │   ├── VocabCard_0 (VocabCardPanel)
│   │   └── VocabCard_1 (VocabCardPanel)
│   └── BottomRow (HBoxContainer)                ← 3 张词汇卡，280×110px
│       ├── VocabCard_2 (VocabCardPanel)
│       ├── VocabCard_3 (VocabCardPanel)
│       └── VocabCard_4 (VocabCardPanel)
└── FooterBand (Control, y=910, h=170)
    ├── BrandIcon (TextureRect)
    ├── BrandName (Label)
    └── AchievementTag (Label)                   ← "Chapter 1 · 5 words explored"
```

**VocabCardPanel 内部节点树（可复用子场景）**

```
VocabCardPanel (PanelContainer)
└── VBox (VBoxContainer)
    ├── StarRow (HBoxContainer)
    │   ├── Star_0 (TextureRect)                 ← 根据 star_count 设 modulate/texture
    │   ├── Star_1 (TextureRect)
    │   └── Star_2 (TextureRect)
    └── WordLabel (Label)                        ← 英文单词，全大写，加粗
```

**Postcard.tscn 数据注入接口**

```gdscript
## 主入口 — 一次性注入所有数据（在 SubViewport.add_child 后、await 前调用）
## child_name: 孩子姓名（ProfileManager 提供，最多 NAME_MAX_LENGTH 字符）
## star_data:  词汇金星字典 {word_id: String → star_count: int}
##             示例: {"ch1_trex": 3, "ch1_triceratops": 1, "ch1_eat": 0, "ch1_run": 2, "ch1_big": 3}
## card_order: 词汇卡排列顺序（Array[String]，按显示位置给 word_id 列表）
##             默认使用 VOCAB_WORD_IDS_CH1 顺序
func setup(child_name: String, star_data: Dictionary, card_order: Array[String] = []) -> void
```

`Postcard.tscn` 不加入可见场景树，不设置 `mouse_filter`，不连接任何输入信号。SubViewport 在渲染完成后随 PostcardGenerator `queue_free()` 一并销毁。

## Acceptance Criteria

所有 BLOCKING 条件必须通过；ADVISORY 条件在发布前确认。

**核心生成流程**

| # | 条件 | 类型 |
|---|------|------|
| AC-1 | GameScene 收到 `chapter_completed` 后，PostcardGenerator 节点被实例化并加入场景树，无需额外调用 `start()` 方法 | BLOCKING |
| AC-2 | `_ready()` 完成后，`_generate()` 协程自动启动，无需外部触发 | BLOCKING |
| AC-3 | 生成完成后，PNG 文件出现在 `OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)/TRexJourney/` 目录下（或 Fallback 路径） | BLOCKING |
| AC-4 | 生成完成后，PostcardGenerator 节点通过 `queue_free()` 自清理；GameScene 场景树中不留残留节点 | BLOCKING |
| AC-5 | `postcard_saved(path)` 信号在 `queue_free()` 之前发出（调试信号时序正确） | BLOCKING |

**图像内容正确性**

| # | 条件 | 类型 |
|---|------|------|
| AC-6 | 输出 PNG 尺寸为 1080×1080 像素 | BLOCKING |
| AC-7 | PNG 中包含正确的孩子姓名（与 ProfileManager 返回值一致） | BLOCKING |
| AC-8 | `star_count == 0` 的词汇卡显示 FRESH 状态（无星，无光晕） | BLOCKING |
| AC-9 | `1 ≤ star_count < 3` 的词汇卡显示 PROGRESSING 状态（对应数量半透明星 + 淡金色光晕） | BLOCKING |
| AC-10 | `star_count ≥ 3` 的词汇卡显示 MASTERED 状态（满星 + 强金色光晕 + 暖金色文字） | BLOCKING |
| AC-11 | 5 个词汇按 `VOCAB_WORD_IDS_CH1` 顺序排列在 2+3 布局中 | BLOCKING |

**对孩子不可见**

| # | 条件 | 类型 |
|---|------|------|
| AC-12 | 生成过程中，孩子屏幕上不出现任何弹窗、进度条、提示文字或任何 UI 变化 | BLOCKING |
| AC-13 | 生成失败时（磁盘满、权限拒绝等），孩子屏幕上不出现任何错误提示 | BLOCKING |

**容错**

| # | 条件 | 类型 |
|---|------|------|
| AC-14 | `ProfileManager` 无活跃档案时，PNG 仍生成（名字字段为空），`postcard_saved` 正常发出 | BLOCKING |
| AC-15 | 所有词汇 `get_gold_star_count()` 返回 0 时，5 张卡片均以 FRESH 状态生成，PNG 文件正常写入 | BLOCKING |
| AC-16 | 同一章节内 `chapter_completed` 信号触发两次，仅生成一张 PNG（GameScene guard 有效） | BLOCKING |

**视觉质量（真机验证）**

| # | 条件 | 类型 |
|---|------|------|
| AC-17 | 在目标 Android 设备（Release APK）上截图，词汇卡文字清晰可读，无灰块或空白区域 | ADVISORY |
| AC-18 | T-Rex 图形在 PNG 中清晰，无模糊或失真（1080px 分辨率） | ADVISORY |
| AC-19 | 明信片发至微信朋友圈后，文字和图形在手机屏幕上一眼可读（实机 QA 确认） | ADVISORY |

## Open Questions

| # | 问题 | 优先级 | 解决时机 |
|---|------|--------|---------|
| OQ-1 | **双向声明更新**：ProfileManager GDD 和 VocabStore GDD 的 Interactions 表中需补充 PostcardGenerator 作为新调用方 | LOW | 本 GDD 批准后核查（`/design-review` 会捕获此项） |
| OQ-2 | **ADR-0003 已创建**：`docs/architecture/adr-0003-android-gallery-save.md` 记录 `OS.get_system_dir` 在 Android API 24–34 上的行为、Scoped Storage 风险及 MediaStore 备选方案（Status: Proposed，Week 1 真机验证后转 Accepted） | HIGH | ✅ **ADR-0003 已创建 2026-05-08**；Week 1 真机验证转 Accepted |
| OQ-3 | **Android WRITE_EXTERNAL_STORAGE 权限声明**：API 28 及以下需在 AndroidManifest.xml 中声明此权限；Godot 4.6 导出模板是否自动处理，或需手动添加？ | HIGH | Week 1 真机验证时确认（可在 Godot 项目设置 → Android → Permissions 中检查） |
| OQ-4 | **MediaStore 扫描延迟**：文件写入后，Android 媒体库不一定立即扫描新 PNG（旧设备需手动触发 `MediaScannerConnection`）。**明确 Pass/Fail 标准**：「家长通关后 30 秒内翻开系统相册，卡片已可见」为 PASS；超过 30 秒或需手动刷新为 FAIL。Godot 4.6 是否提供原生 MediaStore 触发接口尚不确认（ADR-0002 需研究）。 | MEDIUM | ADR-0002 创建时研究，Week 1 真机设备测试以 30 秒标准验证 |
| OQ-5 | **Postcard.tscn 模板字体许可**：英文单词字体需支持全大写大字显示且适合商用/发布；当前游戏字体选择是否已涵盖 Postcard 用途？ | LOW | 美术资产阶段确认 |
