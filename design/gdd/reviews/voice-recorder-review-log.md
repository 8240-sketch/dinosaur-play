# Review Log: VoiceRecorder

---

## Review — 2026-05-07 — Verdict: NEEDS REVISION → Revised (RF-1~RF-8)

Scope signal: M
Specialists: game-designer, systems-designer, qa-lead, godot-gdscript-specialist, creative-director
Blocking items: 8 (RF-1~RF-8) | Recommended: 9
Summary: Architecture sound — 6-state machine correctly handles Android platform complexity (permission flows, phone call interrupts, profile switches, silent-disable). P3 pillar implementation is the strongest in the project. All 8 blockers were spec errors or API documentation mistakes, not design flaws: wrong permission signal signature (would silently disable entire feature on Android), synchronous WAV write causing 1.8–5.3s main thread freeze, non-recursive directory delete leaving orphan child voice recordings, undefined flag priority when profile switch and interrupt commit race in SAVING state. All 8 RF items applied in same session; GDD status updated to In Review.
Prior verdict resolved: N/A — first review

---

## Review — 2026-05-07 — Verdict: NEEDS REVISION → Revised (RF-NEW-1~RF-NEW-6)

Scope signal: M
Specialists: game-designer, systems-designer, qa-lead, godot-gdscript-specialist, creative-director
Blocking items: 6 (RF-NEW-1~RF-NEW-6) | Recommended: 1 (MIN_RECORDING_MS 300→150ms, advisory only)
Summary: Re-review after RF-1~RF-8 fixes confirmed all 8 prior blockers resolved. 6 new structural errors found: (RF-NEW-1) Core Rule 4 pseudocode set `_state = READY` unconditionally after `_init_microphone()` in both `_ready()` and `_on_permissions_result()` paths — contradicts EC-P4 which says failure → DISABLED; Core Rule 5 missing `-> bool` return semantics. Fixed: both paths now use `if _init_microphone(): _state = READY`. State diagram updated with UNINITIALIZED/PERMISSION_REQUESTING → DISABLED transitions on init failure. (RF-NEW-2) F5 formula and EC-RQ1 checked `capture_effect.get_frames_available()` at write time — AudioEffectCapture is continuously drained during recording in `_process()`, so at write time residual frames are near zero (≤735 at 60fps vs MIN_RECORDING_FRAMES=13,230) — every recording would be permanently discarded as "too_short". Fixed: `_pcm_buffer.size() / bytes_per_sample < MIN_RECORDING_FRAMES`. (RF-NEW-3) DirAccess API calls missing `_absolute` suffix — `make_dir_recursive` and `dir_exists` do not exist in Godot 4; correct names are `make_dir_recursive_absolute` and `dir_exists_absolute`. Fixed in 4 locations (EC-FS2, EC-PS4, Dependencies table, AC-22). (RF-NEW-4) AC-6 mixed automatable logic test with device hardware operation — split into AC-6a (auto: mock AudioEffectCapture) and AC-6b (manual: real Android device permission revoke). (RF-NEW-5) AC-27 pass condition "有可听见声音输出" unverifiable on silent devices. Fixed: "播放进度条开始移动，并在 [MIN_RECORDING_MS, MAX_RECORDING_SECONDS×1000+500ms] 范围内自然结束，无错误提示对话框。测试设备可静音——此AC仅验证格式可解码性，不评估音质。" (RF-NEW-6) AC-39/AC-52 grep specs missing file path and function boundary. Fixed with explicit extraction + `grep -c 'await'` on named function body. All 6 RF-NEW items applied in same session. Advisory: creative-director recommends lowering MIN_RECORDING_MS from 300→150ms for 4–6yo fast speech (single syllables ~200–250ms); deferred to implementation tuning. GDD status remains In Review pending final Approved verdict.
Prior verdict resolved: RF-1~RF-8 all confirmed present in reviewed GDD

---

## Review — 2026-05-08 — Verdict: APPROVED (post-revision, RF-3)

Scope signal: M
Specialists: game-designer, systems-designer, qa-lead, godot-gdscript-specialist, creative-director (CD advisory for MIN_RECORDING_MS)
Blocking items resolved: 4 (B1~B4) | Recommended items applied: 6 (R1~R6)
Summary: 第三轮审查，确认 RF-1~RF-8 + RF-NEW-1~RF-NEW-6 全部 14 项历史修复均已生效。本轮新发现 4 个阻断项：(B1) F2 表 BYTE_RATE 硬编码 88,200 B/s——EC-AD4 设备（48000 Hz）上为 96,000 B/s，实现者将错误硬编码；修复：改为公式展示 + 不得硬编码警告，并在 Dependencies FileAccess 行新增 `PackedByteArray.encode_u32()` 写入规范（R2 合并）。(B2) AC-34 竞态规格缺少 GUT 前置条件（需预填充 `_pcm_buffer`）和双顺序覆盖；修复：拆为 AC-34a（计时器先）+ AC-34b（stop 先），各含完整 GUT setup 指令。(B3) AC-39/AC-52 CI 规格写"签名行至对应闭括号"——GDScript 无闭括号，grep 永远提取空串，no-await 保证形同虚设；修复：改为"签名行起，至下一个相同或更小缩进级别的非空行止，awk/Python 按缩进边界切片"。(B4) AudioStreamPlayer process_mode 未声明——默认 PAUSABLE 下 SceneTree 暂停时回放静默停止，GDD 承诺的"不受游戏暂停影响"失效；修复：Core Rule 7 + Visual/Audio 表均增加 `process_mode = Node.PROCESS_MODE_ALWAYS` 强制要求。推荐项 6 项：(R1) MIN_RECORDING_MS 300→150ms（CD 先前建议，本轮正式采纳），F5 公式、EC-RQ1、AC-19/29/30 同步更新；(R2) 见 B1 合并；(R3) EC-PS2 `_discard_after_save` 同步路径不可达注解；(R4) AC-6a 增加可测性前置条件（需暴露 `_capture_effect` 注入接口）；(R5) AC-1 拆为 AC-1a（READY状态）+ AC-1b（试录音文件存在），preamble + AC-2 引用同步更新；(R6) 新增 AC-58（BYTE_RATE 字段二进制验证）+ AC-59（EC-PS2 双标志同时为 true 丢弃优先）。GDD 总 AC 数由 57 增至 59（+AC-34a/b 替换 AC-34 净 +1）。GDD 状态更新为 Approved RF-3 2026-05-08。
Prior verdict resolved: RF-1~RF-8 + RF-NEW-1~RF-NEW-6 全 14 项确认在 GDD 中。
Action taken: 写入 voice-recorder.md B1~B4 + R1~R6 共 10 类修复；review log 本条追加。
