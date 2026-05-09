# Risk Register: 恐龙叙事英语启蒙游戏

> **Last Updated**: 2026-05-09
> **Owner**: producer
> **Status**: Active

---

## RISK-0001: inkgd Android 导出失败

| Field | Value |
|-------|-------|
| **ID** | RISK-0001 |
| **Identified By** | game-concept.md |
| **Date** | 2026-05-05 |
| **Category** | Technical |
| **Probability** | Low |
| **Impact** | Critical |
| **Risk Score** | High |

**Description**: inkgd (Godot 4 分支 v0.6.0) 可能在 Android APK 导出后无法正常推进 ink 对话、选项和 tag 解析。

**Trigger Conditions**:
- APK 安装后 ink 对话无法推进
- InkRuntime singleton 初始化失败
- 选项选择后无响应

**Impact**:
- Schedule: +1-2 天（切换到自建 JSON 状态机）
- Quality: 自建方案功能更简单，叙事表现力降低
- Scope: StoryManager + TagDispatcher 全部受影响

**Mitigation**:
- Prevention: **第 1 周末**真机验证 inkgd 基础功能
- Contingency: 自建轻量 JSON 叙事状态机（~150 行 GDScript）

**Status**: Open | **Last Reviewed**: 2026-05-09 | **Trend**: Stable

---

## RISK-0002: DirAccess.rename() Android 兼容性

| Field | Value |
|-------|-------|
| **ID** | RISK-0002 |
| **Identified By** | ADR-0004, architecture.md OQ#3 |
| **Date** | 2026-05-08 |
| **Category** | Technical |
| **Probability** | Medium |
| **Impact** | Major |
| **Risk Score** | High |

**Description**: `DirAccess.rename()` 在 Android API 29+ (Scoped Storage) 设备上可能不是原子操作。

**Trigger Conditions**:
- rename() 返回 OK 但文件内容不完整
- 特定 OEM 设备上 rename() 返回非 OK 错误

**Mitigation**:
- Prevention: **S1-08 设备验证 Spike**
- Contingency: ADR-0004 fallback——rename 失败则读回 .tmp 直写 .json

**Status**: Open | **Last Reviewed**: 2026-05-09 | **Trend**: Stable

---

## RISK-0003: 声音录制 API 不可用

| Field | Value |
|-------|-------|
| **ID** | RISK-0003 |
| **Category** | Technical |
| **Probability** | Medium |
| **Impact** | Minor |
| **Risk Score** | Medium |

**Description**: `AudioStreamMicrophone` + `AudioEffectCapture` 在某些设备上可能静默或崩溃。

**Mitigation**:
- Prevention: **第 3 周第 2 天**真机验证
- Contingency: 移除录音功能，不影响其余游戏流程

**Status**: Open | **Last Reviewed**: 2026-05-09

---

## RISK-0004: TTS 无英文引擎

| Field | Value |
|-------|-------|
| **ID** | RISK-0004 |
| **Category** | Technical |
| **Probability** | Medium |
| **Impact** | Minor |
| **Risk Score** | Medium |

**Description**: `DisplayServer.tts_get_voices_for_language("en")` 可能返回空数组。

**Mitigation**:
- Contingency: ADR-0002 降级——文字黄色高亮

**Status**: Open | **Last Reviewed**: 2026-05-09

---

## RISK-0005: 美术资产延迟

| Field | Value |
|-------|-------|
| **ID** | RISK-0005 |
| **Category** | Schedule |
| **Probability** | Medium |
| **Impact** | Moderate |
| **Risk Score** | Medium |

**Description**: AI 生成恐龙 sprites 可能风格不一致或超时。

**Mitigation**:
- Contingency: 切换到 Kenney.nl 恐龙素材包

**Status**: Open | **Last Reviewed**: 2026-05-09

---

## RISK-0006: schema v2 迁移数据丢失

| Field | Value |
|-------|-------|
| **ID** | RISK-0006 |
| **Category** | Technical |
| **Probability** | Low |
| **Impact** | Moderate |
| **Risk Score** | Low |

**Description**: v1→v2 迁移可能清空旧存档数据。

**Mitigation**:
- Prevention: 迁移逻辑已实现（additive-only, idempotent），18 个单元测试覆盖

**Status**: Mitigating | **Last Reviewed**: 2026-05-09 | **Trend**: Decreasing

---

## RISK-0007: OS.get_system_dir() 兼容性

| Field | Value |
|-------|-------|
| **ID** | RISK-0007 |
| **Category** | Technical |
| **Probability** | Low |
| **Impact** | Minor |
| **Risk Score** | Low |

**Description**: `OS.get_system_dir(SYSTEM_DIR_PICTURES)` 在 API 29+ 设备上可能不可写。

**Mitigation**:
- Contingency: 保存到 `user://postcards/` + Android Share Intent

**Status**: Open | **Last Reviewed**: 2026-05-09

---

## Summary

| Risk | Score | Status | Trend |
|------|-------|--------|-------|
| RISK-0001 inkgd Android | High | Open | Stable |
| RISK-0002 rename() 兼容性 | High | Open | Stable |
| RISK-0003 录音 API | Medium | Open | Stable |
| RISK-0004 TTS 无引擎 | Medium | Open | Stable |
| RISK-0005 美术资产延迟 | Medium | Open | Stable |
| RISK-0006 schema 迁移 | Low | Mitigating | Decreasing |
| RISK-0007 get_system_dir | Low | Open | Stable |
