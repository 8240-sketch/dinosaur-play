<p align="center">
  <h1 align="center">🦕 Baby Play — 恐龙英语叙事启蒙游戏</h1>
  <p align="center">
    教恐龙说英文。孩子的第一声「T-Rex!」被悄悄录下来。
    <br />
    面向 4–6 岁中文母语孩子的 Android 叙事游戏，Godot 4 + inkgd 驱动。
  </p>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/platform-Android%20API%2024%2B-green" alt="Android API 24+">
  <img src="https://img.shields.io/badge/engine-Godot%204.x-blue?logo=godotengine" alt="Godot 4">
  <img src="https://img.shields.io/badge/narrative-inkgd-purple" alt="inkgd">
  <img src="https://img.shields.io/badge/stage-Pre--Production-orange" alt="Pre-Production">
  <img src="https://img.shields.io/badge/built%20with-Claude%20Code%20Game%20Studios-f5f5f5?logo=anthropic" alt="Built with Claude Code Game Studios">
</p>

---

## 这是什么

Baby Play 是一款面向 **4–6 岁中文母语孩子**的恐龙主题英语叙事游戏。孩子通过触屏选择英文单词图标来推进 T-Rex 的故事——不是背单词，不是做练习题，而是**教恐龙说话**。

**孩子的视角**：「我教恐龙说英文，恐龙听懂了我。」  
**家长看到的**：明信片发朋友圈，词汇地图里有金星，六个月后还能回放孩子当年那声稚嫩的「T-Rex!」。

> 孩子不会说「我在学英语」，她只会说「我还要玩」。

---

## 核心体验

**第一章：恐龙营地（5 词汇 · 5–10 分钟 · 2 种结局）**

| 目标词汇 | 在故事里的作用 |
|---------|-------------|
| T-Rex | 认识主角，开场关键词 |
| Triceratops | 遇见朋友，选择分支 |
| eat | 恐龙行为，剧情推进 |
| run | 逃跑 vs 留下，结局关键 |
| big | 最终 Boss 选择，结局 A/B 分叉 |

**核心循环：**

```
30秒触屏选英文图标（视觉二选一，无文字压力）
    ↓
T-Rex 即时反应：3种随机 happy 动画 + 设备TTS发音
    ↓
录音邀请（可选）：孩子说出单词，声音存入回忆本
    ↓
5分钟通关 → 词汇金星 + 可分享恐龙明信片 + 第2章预告
```

**失败是另一条好玩的路**：选错单词，T-Rex 做出滑稽的「听不懂」动作后友好挥手——无红色、无倒计时、无扣分，confused 动画是彩蛋而非惩罚。

---

## 功能特性

### 孩子侧
- **叙事驱动**：ink 剧本引擎（inkgd），3个分支点，结局 A（成为朋友）/ 结局 B（趣味逃跑 + T-Rex 远处挥手）
- **TTS 发音**：触选正确后设备内置 TTS 即时朗读英文单词；无 TTS 引擎时降级为词汇高亮，流程不中断
- **NPC 记忆**：第二次游玩时 T-Rex 认出孩子，专属欢迎动作
- **孵化彩蛋**：首次启动时恐龙蛋破壳动画（5秒），第一次握手的仪式感
- **词汇预热**：场景加载时词汇图标静默滑过，priming 效果零感知

### 家长侧
- **词汇地图**：每个单词的出现次数、正确率、金星（≥80% 正确率自动点亮）
- **声音回忆本**：孩子选对后可选择录音（3秒），家长随时回放；纯本地存储，明确无上传
- **恐龙明信片**：通关后生成 1080×1080px 明信片（含孩子昵称+日期+词汇），一键截图发朋友圈
- **多孩子档案**：同设备最多3个独立档案，词汇进度和录音分开存储

---

## 四根设计柱

| # | Pillar | 反面（明确不做） |
|---|--------|---------------|
| P1 | **看不见的学习** — 界面里没有「学英语」，只有「你看到了什么？」 | ❌ 测验界面、红对勾、计分板 |
| P2 | **失败是另一条好玩的路** — confused 动画要好笑，重试按钮要鼓励 | ❌ 计时压力、倒计时条、红色错误反馈 |
| P3 | **声音是成长的日记** — 孩子的第一声「T-Rex!」被悄悄录下 | ❌ 强制录音，拒绝权限后功能静默禁用 |
| P4 | **家长是骄傲见证者，不是监工** — 词汇金星不需要解释 | ❌ 强制家长登录、必须设置 PIN |

---

## 技术架构

```
ink 脚本层（assets/data/chapter1.ink）
  ├── 对话流 + 选项控制（#tts:WORD 触发发音）
  ├── 剧情分支（#animate:NAME_STATE 触发动画）
  ├── 词汇记录（ink变量 + VocabStore 写入）
  └── NPC 记忆（times_played 变量注入）
           ↓
inkgd 运行时（GDScript 原生插件，ephread/inkgd）
  └── 解析 ink 输出 → TagDispatcher 分发到各系统
           ↓
Godot 4.x Standard 引擎层
  ├── AnimationPlayer：16个状态（12词汇变体 + celebrate×2 + recognize + end_b_wave）
  ├── DisplayServer.tts_speak()：设备内置 TTS（无需外部 API）
  ├── AudioStreamMicrophone + AudioEffectCapture：本地录音（GDScript 原生，无 JNI）
  └── 明信片生成器（固定模板叠加，无 Viewport 截图，无存储权限需求）
           ↓
本地持久化（Godot SaveGame，schema v2 多档案）
  ├── profiles/{id}/vocab：词汇 seen/correct 计数
  ├── profiles/{id}/recordings：声音回忆本路径
  └── profiles/{id}/times_played：NPC 记忆驱动
```

**最低支持**：Android API 24（Android 7.0）

---

## 18 个系统，4 个依赖层

| 层 | 系统 | 状态 |
|----|------|------|
| **Foundation** | SaveSystem | ✅ 已实现（原子写 + schema迁移） |
| **Core** | ProfileManager, VocabStore, AnimationHandler, TtsBridge, VoiceRecorder, InterruptHandler, AudioManager | 设计完成，待实现 |
| **Narrative** | StoryManager, TagDispatcher | 设计完成，待实现 |
| **UI** | ChoiceUI, MainMenu, HatchScene, NameInputScreen, RecordingInviteUI, VocabPrimingLoader | 设计完成，待实现 |
| **Meta** | PostcardGenerator, ParentVocabMap, Chapter2Teaser | 设计完成，待实现 |

设计文档：[design/gdd/systems-index.md](design/gdd/systems-index.md) · 架构决策：[docs/architecture/](docs/architecture/)（ADR-0001 ~ ADR-0024）

---

## 项目结构

```
baby-play/
├── CLAUDE.md                     # AI 协作主配置（49 agents，72 skills）
├── assets/data/                  # ink 叙事脚本
├── src/
│   ├── autoload/                 # Godot AutoLoad 系统（SaveSystem 等）
│   ├── core/                     # TtsBridge, VoiceRecorder, AnimationHandler
│   ├── feature/                  # StoryManager, TagDispatcher, VocabStore
│   ├── foundation/               # ProfileManager, SaveSystem
│   └── presentation/             # UI 场景（ChoiceUI, MainMenu, PostcardGenerator…）
├── design/
│   ├── gdd/                      # 18 份游戏设计文档（已通过 /review-all-gdds 交叉审查）
│   ├── art/art-bible.md          # 视觉规范（温暖绘本风，色彩令牌系统）
│   └── ux/interaction-patterns.md
├── docs/architecture/            # ADR-0001~0024 + 控制手册 + TR 追溯矩阵
├── production/                   # 冲刺计划、里程碑、风险登记册
└── tests/                        # GUT 测试框架（单元 + 集成）
```

---

## AI 驱动的开发方式

本项目是用 **[Claude Code Game Studios](https://github.com/Donchitos/Claude-Code-Game-Studios)** 模板驱动开发的真实案例。该模板将单次 Claude Code 会话变成一个虚拟游戏工作室——49 个专业 AI 代理，72 个工作流技能，12 个自动化钩子。

**已完成的 AI 驱动工作流：**

| 工作流 | 产出物 | AI 代理 |
|--------|--------|--------|
| `/plan-ceo-review` (×2) | CEO 战略计划（v2 SCOPE EXPANSION） | CEO + 产品 |
| `/map-systems` | 18 个系统依赖图谱 | 技术总监 + 系统设计师 |
| `/design-system` (×18) | 18 份 GDD（每份 8 个必需章节） | 游戏设计师 + 叙事总监 |
| `/review-all-gdds` | 全文档交叉一致性检查（18/18 通过） | QA 主管 + 创意总监 |
| `/art-bible` | 色彩系统、字体规范、动画节奏规范 | 艺术总监 |
| `/create-architecture` | 主架构文档 + ADR-0001~0024 | 技术总监 + 引擎专家 |
| `/architecture-review` | 架构可追溯矩阵，PASS 评级 | 技术总监 |
| `/create-control-manifest` | 程序员控制手册（Forbidden/Required/Guardrails） | 首席程序员 |
| `/sprint-plan` | Sprint 1 计划 + 里程碑 + 风险登记册 | 制作人 |
| `dev-story` | SaveSystem 完整实现（原子写 + 迁移） | Godot GDScript 专家 |

---

## 当前状态

**阶段**：Pre-Production（设计完成，Sprint 1 进行中）

- ✅ 所有 18 份 GDD 已审查并批准
- ✅ 架构文档 + 24 条 ADR 已完成
- ✅ SaveSystem 已实现（原子写，schema v2 多档案）
- ✅ 艺术风格规范、色彩系统、可访问性需求已锁定
- ✅ Sprint 1 计划就绪（Godot + inkgd + Android APK 验证）
- 🚧 核心系统实现中（VocabStore, StoryManager, TtsBridge…）
- 📅 目标：4 周内 APK 可分发，侄女首轮测试

---

## License

[MIT](LICENSE)

- **[Buy Me a Coffee](https://www.buymeacoffee.com/donchitos3)** — one-time support
- **[GitHub Sponsors](https://github.com/sponsors/Donchitos)** — recurring support through GitHub

Sponsorships help fund time spent maintaining skills, adding new agents, keeping up with Claude Code and engine API changes, and responding to community issues.

---

*Built for Claude Code. Maintained and extended — contributions welcome via [GitHub Discussions](https://github.com/Donchitos/Claude-Code-Game-Studios/discussions).*

## License

MIT License. See [LICENSE](LICENSE) for details.
