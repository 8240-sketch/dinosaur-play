# Godot Engine — Version Reference

| Field | Value |
|-------|-------|
| **Engine Version** | Godot 4.6 |
| **Release Date** | January 2026 |
| **Project Pinned** | 2026-02-12 |
| **Last Docs Verified** | 2026-02-12 |
| **LLM Knowledge Cutoff** | May 2025 |

## Knowledge Gap Warning

The LLM's training data likely covers Godot up to ~4.3. Versions 4.4, 4.5,
and 4.6 introduced significant changes that the model does NOT know about.
Always cross-reference this directory before suggesting Godot API calls.

## Post-Cutoff Version Timeline

| Version | Release | Risk Level | Key Theme |
|---------|---------|------------|-----------|
| 4.4 | ~Mid 2025 | MEDIUM | Jolt physics option, FileAccess return types, shader texture type changes |
| 4.5 | ~Late 2025 | HIGH | Accessibility (AccessKit), variadic args, @abstract, shader baker, SMAA |
| 4.6 | Jan 2026 | HIGH | Jolt default, glow rework, D3D12 default on Windows, IK restored |

## Verified Sources

- Official docs: https://docs.godotengine.org/en/stable/
- 4.5→4.6 migration: https://docs.godotengine.org/en/stable/tutorials/migrating/upgrading_to_godot_4.6.html
- 4.4→4.5 migration: https://docs.godotengine.org/en/stable/tutorials/migrating/upgrading_to_godot_4.5.html
- Changelog: https://github.com/godotengine/godot/blob/master/CHANGELOG.md
- Release notes: https://godotengine.org/releases/4.6/

## Dev Environment Setup (2026-05-05)

本地开发环境配置记录，供新成员或重新安装时参考。

| 组件 | 版本 | 安装位置 | 注意事项 |
|------|------|---------|---------|
| Godot Standard | 4.6-stable | `C:\software\Godot\Godot_v4.6-stable_win64.exe` | 非 .NET 版本 |
| inklecate | v1.2.0 | `C:\software\inklecate\inklecate.exe` | inkgd 编辑器编译器 |
| inkgd | v0.6.0 (godot4 分支) | `addons/inkgd/` | ⚠️ 主分支是 Godot 3！必须用 `godot4` 分支 |
| GUT | v9.6.0 | `addons/gut/` | ⚠️ v7.x 是 Godot 3！必须用 v9.x |
| JDK | 21.0.10 (Eclipse Adoptium) | `C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot` | 满足 JDK 17+ 要求 |
| Android SDK | API 34/35 | `C:\Users\zhang\AppData\Local\Android\Sdk` | Build Tools 35-37 |
| godot-mcp | 0.1.1 | `C:\code\github-project\godot-mcp\build\index.js` | 需重启 Claude Code 激活 |

### Godot 编辑器内需手动配置

1. Project Settings → Plugins → 启用 InkGD + Gut
2. Editor Settings → Export → Android → SDK 路径 + JDK 路径
3. Editor Settings → Ink → inklecate 路径：`C:\software\inklecate\inklecate.exe`
