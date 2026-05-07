## Review — 2026-05-07 — Verdict: NEEDS REVISION → Revised

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
