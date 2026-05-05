# Technical Preferences

<!-- Populated by /setup-engine. Updated as the user makes decisions throughout development. -->
<!-- All agents reference this file for project-specific standards and conventions. -->

## Engine & Language

- **Engine**: Godot 4.6
- **Language**: GDScript (static typing)
- **Rendering**: Compatibility (Android 2D — lowest driver overhead)
- **Physics**: Godot Physics 2D (Jolt not required for tap-only 2D game)

## Input & Platform

<!-- Written by /setup-engine. Read by /ux-design, /ux-review, /test-setup, /team-ui, and /dev-story -->
<!-- to scope interaction specs, test helpers, and implementation to the correct input methods. -->

- **Target Platforms**: Android (API 24+)
- **Input Methods**: Touch（触屏：点击、长按、持续按下）
- **Primary Input**: Touch（点击为主 — 词汇选择；长按 — 家长入口 5 秒；持续按下 — 录音按钮保持）
- **Gamepad Support**: None
- **Touch Support**: Full
- **Platform Notes**: 仅竖屏方向。所有交互元素最小 80dp。禁止 hover-only 交互。所有 UI 适配 360×800dp 并可缩放至平板。

## Naming Conventions

- **Classes**: PascalCase (e.g., `StoryManager`, `VocabTracker`)
- **Variables**: snake_case (e.g., `move_speed`, `word_count`)
- **Signals/Events**: snake_case 过去式 (e.g., `word_selected`, `health_changed`, `chapter_completed`)
- **Files**: snake_case 匹配类名 (e.g., `story_manager.gd`, `vocab_tracker.gd`)
- **Scenes/Prefabs**: PascalCase 匹配根节点 (e.g., `HatchScene.tscn`, `MainMenu.tscn`)
- **Constants**: UPPER_SNAKE_CASE (e.g., `MAX_RECORDING_SECONDS`, `TTS_RATE`)

## Performance Budgets

- **Target Framerate**: 60fps
- **Frame Budget**: 16.6ms
- **Draw Calls**: <100（Android 低配基准，可随目标机型调整）
- **Memory Ceiling**: <256MB

## Testing

- **Framework**: GUT (Godot Unit Testing) — https://github.com/bitwes/Gut
- **Minimum Coverage**: [TO BE CONFIGURED]
- **Required Tests**: Ink 故事状态机、词汇追踪逻辑、存档/读档 schema v2、TTS 降级逻辑、录音权限拒绝后静默降级

## Forbidden Patterns

<!-- Add patterns that should never appear in this project's codebase -->
- [None configured yet — add as architectural decisions are made]

## Allowed Libraries / Addons

<!-- Add approved third-party dependencies here. Only add when actively integrating, not speculatively. -->
- **inkgd** v0.6.0 — GDScript 原生 Ink 运行时（P0 已确认依赖，github.com/ephread/inkgd，⚠️ 必须用 `godot4` 分支而非 main）
- **GUT** v9.6.0 — Godot 单元测试框架（github.com/bitwes/Gut，⚠️ 需 v9.x 以兼容 Godot 4）

## Architecture Decisions Log

<!-- Quick reference linking to full ADRs in docs/architecture/ -->
- [No ADRs yet — use /architecture-decision to create one]

## Engine Specialists

<!-- Written by /setup-engine when engine is configured. -->
<!-- Read by /code-review, /architecture-decision, /architecture-review, and team skills -->
<!-- to know which specialist to spawn for engine-specific validation. -->

- **Primary**: godot-specialist
- **Language/Code Specialist**: godot-gdscript-specialist (all .gd files)
- **Shader Specialist**: godot-shader-specialist (.gdshader files, VisualShader resources)
- **UI Specialist**: godot-specialist (no dedicated UI specialist — primary covers all UI)
- **Additional Specialists**: godot-gdextension-specialist (GDExtension / native C++ bindings only)
- **Routing Notes**: Invoke primary for architecture decisions, ADR validation, and cross-cutting code review. Invoke GDScript specialist for code quality, signal architecture, static typing enforcement, and GDScript idioms. Invoke shader specialist for material design and shader code. Invoke GDExtension specialist only when native extensions are involved.

### File Extension Routing

<!-- Skills use this table to select the right specialist per file type. -->
<!-- If a row says [TO BE CONFIGURED], fall back to Primary for that file type. -->

| File Extension / Type | Specialist to Spawn |
|-----------------------|---------------------|
| Game code (.gd files) | godot-gdscript-specialist |
| Shader / material files (.gdshader, VisualShader) | godot-shader-specialist |
| UI / screen files (Control nodes, CanvasLayer) | godot-specialist |
| Scene / prefab / level files (.tscn, .tres) | godot-specialist |
| Native extension / plugin files (.gdextension, C++) | godot-gdextension-specialist |
| General architecture review | godot-specialist |
