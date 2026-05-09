# ADR-0003: Android 图库保存策略（PostcardGenerator）

## Status
Accepted (2026-05-09)

## Date
2026-05-08

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Platform / File I/O |
| **Knowledge Risk** | HIGH — Android Scoped Storage（API 29+）行为和 Godot 4.6 的 `OS.get_system_dir` 实现均在 LLM 知识截止日期（2025-05 附近）之后仍在演进；需真机验证 |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`；Android Developers — Scoped Storage (API 29+)；`PostcardGenerator GDD OQ-2~OQ-4` |
| **Post-Cutoff APIs Used** | `OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)` — Godot 4.x 版本行为待验证；`DirAccess.make_dir_recursive_absolute()`；`FileAccess.open()` + `store_buffer()` |
| **Verification Required** | Week 1 真机验证：(1) 主路径写入成功；(2) Fallback 路径兜底；(3) MediaStore 扫描延迟 ≤ 30 秒 |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001（inkgd Runtime），PostcardGenerator GDD |
| **Enables** | PostcardGenerator 实现 |
| **Blocks** | PostcardGenerator 实现（等待存储方案确认） |
| **Ordering Note** | 本 ADR 应在 PostcardGenerator 编码开始前转为 Accepted。Week 1 真机验证是 Accepted 的触发条件。 |

## Context

PostcardGenerator 需将 1080×1080 PNG 写入 Android 系统相册，使家长能在系统相册中偶然发现明信片（设计柱 P4）。

核心技术问题：

1. **Android Scoped Storage（API 29+）**：Android 10（API 29）起引入 Scoped Storage，限制第三方 App 直接访问 `Pictures/` 目录。`WRITE_EXTERNAL_STORAGE` 权限在 API 33+ 已弃用；访问共享存储的标准路径是 `MediaStore` API（通过 Java/Kotlin，Godot 无直接 GDScript 封装）。

2. **`OS.get_system_dir` 行为差异**：
   - API 24–28：`OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)` 返回 `/sdcard/Pictures/`，`FileAccess` 可直接写入（前提是 `WRITE_EXTERNAL_STORAGE` 权限已声明）
   - API 29–32：行为不一致——部分设备仍允许直接写入（`requestLegacyExternalStorage` 标记），部分设备拒绝
   - API 33+：直接写入被拒绝；规范路径是 `MediaStore.Images.Media.insertImage()` Java API

3. **MediaStore 扫描延迟**：文件写入文件系统后，Android 媒体库（`MediaStore`）不会立即扫描到新文件。旧设备可能需要重启或手动触发 `MediaScannerConnection` 才能在系统相册看到新 PNG。这直接影响 P4「家长在相册偶然发现」场景的成立时效。

4. **`WRITE_EXTERNAL_STORAGE` 权限**：
   - API 28 及以下：AndroidManifest.xml 必须声明此权限
   - Godot 4.6 项目设置 → Android → Permissions 中是否默认包含此权限，需确认

## Decision

**MVP 采用分层存储策略（主路径 + Fallback）：**

### Tier 1：主路径（目标 API 24–28 设备）

```gdscript
var dir = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES) + "/TRexJourney/"
```

- 在 AndroidManifest.xml 中声明 `WRITE_EXTERNAL_STORAGE`（Godot 4.6 项目设置中手动勾选）
- 若 `dir` 非空且 `FileAccess.open()` 成功 → 写入

### Tier 2：Fallback 路径（API 29+ Scoped Storage 设备，Tier 1 失败时）

```gdscript
var dir = OS.get_user_data_dir() + "/postcards/"
```

- `user_data_dir` 是 App 沙盒私有目录，始终可写，无需权限
- 缺点：家长无法通过系统相册看到（需通过文件管理器手动访问）
- 这是 MVP 降级方案——P4 体验降级，但 App 不崩溃、不报错

### Tier 3（Post-MVP，v1.1）：MediaStore API

通过 GDExtension 插件调用 `android.provider.MediaStore.Images.Media.insertImage()` 实现 API 29+ 标准写入。此方案在 MVP 范围外，不在本 ADR 承诺范围内。

### 验收标准（OQ-3 解决）

Week 1 真机测试必须覆盖以下场景：

| 测试场景 | Pass 条件 |
|---------|---------|
| API 24–28 设备：`OS.get_system_dir` 主路径写入 | PNG 出现在系统相册 `Pictures/TRexJourney/`，`FileAccess.open()` 返回非 null |
| API 29–32 设备：`OS.get_system_dir` 主路径写入 | 成功（使用 `requestLegacyExternalStorage`）或自动 Fallback 到 Tier 2 不报错 |
| API 33+ 设备：主路径被拒绝，Fallback 触发 | `push_warning` 发出，`user_data_dir/postcards/` 内有 PNG，App 无报错 |
| MediaStore 扫描延迟（任意 API 级别） | **家长通关后 30 秒内翻开系统相册，卡片已可见** 为 PASS；超过 30 秒为 FAIL（需研究触发 `MediaScannerConnection` 方案） |

## Consequences

**接受以上决策的代价：**

- API 29+ 设备上，Tier 2 Fallback 使「家长在系统相册偶然发现」场景**降级为不可实现**——家长必须通过文件管理器才能找到卡片，P4 效果大幅削弱
- MVP 目标设备（家长购买的典型中端安卓）多处于 API 28–31 范围，真实降级频率需 Week 1 测试数据评估
- Tier 3（MediaStore GDExtension）若 Week 1 数据显示降级频率高，应提前进入 v1.0 范围

**不接受以上决策的替代方案：**

若 Tier 1 在 MVP 目标设备上失败率过高，可在 Week 1 结束前升级至直接实现 Tier 3，代价为额外 1–2 天 GDExtension 开发工作（引入 Android Java 插件，需 .aar 构建）。

## GDD Requirements Addressed

| 需求 | 来源 |
|------|------|
| 明信片 PNG 保存至 Android 系统图库 | PostcardGenerator GDD Core Rule 4 + Rule 6 |
| 静默失败策略（生成失败不打断孩子体验） | PostcardGenerator GDD Core Rule 5 |
| OQ-2：ADR-0003 创建（Android 图库方案） | PostcardGenerator GDD Open Questions |
| OQ-3：`WRITE_EXTERNAL_STORAGE` 权限声明确认 | PostcardGenerator GDD Open Questions |
| OQ-4：MediaStore 扫描延迟 ≤ 30 秒 Pass/Fail 标准 | PostcardGenerator GDD Open Questions |
