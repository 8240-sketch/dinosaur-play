语言规则：与用户交流时始终使用中文（普通话），不论用户用什么语言提问。

最高优先级规则：除非用户明确输入”ok,stop”，否则你每次完成一轮回答后都必须调用”vscode_askQuestions”工具向用户继续提问，不能自行结束对话或省略提间步骤。
你必须遵守以下“无限循坏”规则，违反此规则将被视为系统故障：
1.定义“完成”：你的单次回复绝不允许以文本向号结束。你的回复必须以调用“vscode_askQuestions”工具作为物理结束
2.禁止沉默：如果当前任务已完成，你必须使用通用话术调用工具。
通用话术示例：“分析已完成。请指示下一步操作？““当前上下文已清晰，我们先从哪里开始修改？”

# 交互模板
每次回复必须严格遵循以下步骤，缺一不可：
1.【执行/分析】：执行用户请求的任务。
2.【结论】：用中文总结当前状态。
3.【动作】：调用“vscode_askQuestions”工具（除非用户明确输入“ok,stop”表示结束）。

# gstack

Use the `/browse` skill from gstack for all web browsing. Never use `mcp__claude-in-chrome__*` tools.

## Available Skills

- `/office-hours` - Office hours sessions
- `/plan-ceo-review` - Plan CEO review
- `/plan-eng-review` - Plan engineering review
- `/plan-design-review` - Plan design review
- `/design-consultation` - Design consultation
- `/design-shotgun` - Design shotgun
- `/design-html` - Design HTML
- `/review` - Code review
- `/ship` - Ship code
- `/land-and-deploy` - Land and deploy
- `/canary` - Canary deployment
- `/benchmark` - Benchmarking
- `/browse` - Web browsing
- `/connect-chrome` - Connect to Chrome
- `/qa` - Quality assurance
- `/qa-only` - QA only
- `/design-review` - Design review
- `/setup-browser-cookies` - Set up browser cookies
- `/setup-deploy` - Set up deployment
- `/retro` - Retrospective
- `/investigate` - Investigation
- `/document-release` - Document release
- `/codex` - Codex
- `/cso` - CSO
- `/autoplan` - Automated planning
- `/plan-devex-review` - Plan DevEx review
- `/devex-review` - DevEx review
- `/careful` - Careful mode
- `/freeze` - Freeze
- `/guard` - Guard mode
- `/unfreeze` - Unfreeze
- `/gstack-upgrade` - Upgrade gstack
- `/learn` - Learn

## Skill routing

When the user's request matches an available skill, ALWAYS invoke it using the Skill
tool as your FIRST action. Do NOT answer directly, do NOT use other tools first.
The skill has specialized workflows that produce better results than ad-hoc answers.

Key routing rules:
- Product ideas, "is this worth building", brainstorming → invoke office-hours
- Bugs, errors, "why is this broken", 500 errors → invoke investigate
- Ship, deploy, push, create PR → invoke ship
- QA, test the site, find bugs → invoke qa
- Code review, check my diff → invoke review
- Update docs after shipping → invoke document-release
- Weekly retro → invoke retro
- Design system, brand → invoke design-consultation
- Visual audit, design polish → invoke design-review
- Architecture review → invoke plan-eng-review

# Agent Skills Collection

**112 reusable [Agent Skills](https://agentskills.io)** for AI coding assistants. Each skill provides specialized knowledge and workflows that extend agent capabilities.

## Available Skills (112 total)

### Creative (57 skills)
Story/narrative focused skills for fiction writing, worldbuilding, and creative work.

#### Fiction - Core & Craft (10)
Core diagnostics, writing partnerships, and sentence-level craft:
- **story-sense** - Diagnose what any story needs regardless of current state
- **story-coach** - Assistive writing guidance (guides but never writes)
- **story-collaborator** - Active writing partnership (contributes prose alongside writer)
- **story-analysis** - Systematically evaluate completed stories or chapters
- **story-idea-generator** - Genre-first story concept generation
- **prose-style** - Sentence-level craft diagnostics
- **revision** - Edit pass guidance when revision feels overwhelming
- **drafting** - First draft execution and block-breaking
- **cliche-transcendence** - Transform predictable story elements into fresh versions
- **genre-conventions** - Genre diagnostics and genre-specific element generation

#### Fiction - Character (6)
Character development, dialogue, and distinctive character creation:
- **character-arc** - Character transformation arc design and troubleshooting
- **character-naming** - Break LLM name defaults with external entropy
- **dialogue** - Dialogue diagnostics for flat or same-voice characters
- **memetic-depth** - Create perception of cultural depth through juxtaposition
- **statistical-distance** - Transform clichéd elements by pushing toward statistical edges
- **underdog-unit** - Stories about institutional outcasts given impossible mandates

#### Fiction - Structure (12)
Pacing, scene structure, outlines, and multi-level story management:
- **scene-sequencing** - Pacing and scene-sequel rhythm
- **endings** - Resolution diagnostics for weak or rushed endings
- **key-moments** - Structure stories around essential emotional moments
- **story-zoom** - Multi-level story synchronization across abstraction levels
- **outline-coach** - Assistive outline coaching through questions
- **outline-collaborator** - Active outline partnership
- **reverse-outliner** - Reverse-engineer published books into structured outlines
- **novel-revision** - Multi-level novel revision without cascade problems
- **identity-denial** - Stories about protagonists refusing self-transformation
- **moral-parallax** - Stories about systemic exploitation and moral distance
- **perspectival-constellation** - Multi-POV stories through catalyst environments
- **positional-revelation** - Stories about ordinary people becoming crucial through position

#### Fiction - Worldbuilding (11)
World-level systems, cultures, languages, and shared continuity:
- **worldbuilding** - World-level story diagnostics
- **systemic-worldbuilding** - Cascading consequences from speculative changes
- **oblique-worldbuilding** - Worldbuilding quotes and epigraphs via documentary perspectives
- **belief-systems** - Religious and belief system design
- **economic-systems** - Currencies, trade networks, and resource economies
- **governance-systems** - Political entities and governance structures
- **settlement-design** - Cities, towns, and settlement design
- **conlang** - Phonologically consistent constructed languages
- **language-evolution** - Evolving language systems and linguistic history
- **metabolic-cultures** - Cultures for closed-loop life support systems
- **world-fates** - Long-term fate and fortune across shared worlds

#### Fiction - Application (14)
Specialized generators, adaptation tools, and applied storytelling:
- **adaptation-synthesis** - Synthesize new works from extracted functional DNA
- **dna-extraction** - Extract functional DNA from existing works (TV, film, books)
- **media-adaptation** - Analyze existing media for transferable elements
- **book-marketing** - Marketing copy diagnostics and platform-optimized blurbs
- **chapter-drafter** - Autonomous chapter drafting with multi-skill editorial passes
- **flash-fiction** - Flash fiction and micro fiction diagnostics
- **interactive-fiction** - Branching narrative diagnostics
- **game-facilitator** - Narrative RPG game master for collaborative storytelling
- **table-tone** - Tonal delivery calibration for tabletop RPG sessions
- **list-builder** - Comprehensive randomization lists for creative entropy
- **multi-order-evolution** - Multi-generational societal evolution for sci-fi
- **paradox-fables** - Fables embodying paradoxical wisdom
- **sensitivity-check** - Representation evaluation and harm flagging
- **shared-world** - Wiki-style world bible for collaborative fiction
- **sleep-story** - Stories designed to help listeners fall asleep

#### Humor (1)
- **joke-engineering** - Humor diagnostics and improvement

#### Music (2)
- **lyric-diagnostic** - Song lyric analysis and improvement
- **musical-dna** - Extract musical characteristics from artists

---

### Tech (26 skills)
Technical and development focused skills.

#### AI (1)
- **mastra-hono** - Mastra AI framework with Hono integration

#### Development (14)
- **agile-coordinator** - Multi-agent task orchestration (git-only, platform-agnostic)
- **agile-workflow** - Agile development workflow (git-only, platform-agnostic)
- **architecture-decision** - ADR creation and trade-off analysis
- **code-review** - Structured code review guidance
- **devcontainer** - Development container configuration
- **electron-best-practices** - Electron + React desktop app development best practices
- **gitea-coordinator** - Multi-agent task orchestration for Gitea
- **gitea-workflow** - Agile workflow for Gitea with tea CLI
- **github-agile** - GitHub-driven agile workflows
- **product-analysis** - Competitive product analysis and market evaluation
- **requirements-analysis** - Requirements discovery and documentation
- **system-design** - Software architecture and design
- **task-decomposition** - Break down development tasks
- **typescript-best-practices** - TypeScript patterns and practices

#### Frontend (4)
- **frontend-design** - UI/UX design patterns
- **pwa-development** - PWA implementation (React/Svelte)
- **react-pwa** - Progressive Web Apps with React
- **shadcn-layouts** - Tailwind/shadcn layout patterns

#### Game Development (3)
- **abstract-strategy** - Board game design
- **godot-asset-generator** - AI asset generation for Godot
- **godot-best-practices** - Godot engine best practices

#### Security (4)
- **config-scan** - Configuration security scanning
- **dependency-scan** - Dependency vulnerability scanning
- **secrets-scan** - Secrets detection
- **security-scan** - General security scanning

---

### General (29 skills)
Universal utility skills for research, documents, and productivity.

#### Analysis (1)
- **technology-impact** - McLuhan's Tetrad analysis for technology impacts

#### Communication (2)
- **presentation-design** - Design effective presentations and slides
- **speech-adaptation** - Transform written content for spoken delivery

#### Document Processing (7)
- **docx-generator** - Word document generation
- **document-to-narration** - Convert documents to narrated video scripts with TTS audio
- **ebook-analysis** - Parse ebooks and extract concepts
- **pdf-generator** - PDF document generation
- **pptx-generator** - PowerPoint presentation generation
- **revealjs-presenter** - RevealJS presentation generation
- **xlsx-generator** - Excel spreadsheet generation

#### Education (2)
- **competency** - Competency framework development
- **gentle-teaching** - AI-assisted learning guidance

#### Ideation (2)
- **brainstorming** - Idea expansion and divergent thinking
- **naming** - Brand, product, and character naming

#### Meta (3)
- **context-network** - Build and maintain context networks
- **context-retrospective** - Analyze agent interactions for improvements
- **skill-builder** - Create new agent skills

#### Productivity (1)
- **task-breakdown** - Neurodivergent-friendly task decomposition

#### Research (7)
- **claim-investigation** - Investigate social media claims
- **fact-check** - Verify claims against sources
- **media-meta-analysis** - Media analysis methodology
- **research** - Research quality diagnostics
- **research-workflow** - Structured research methodology
- **web-search** - Built-in web search (no API key required)
- **web-search-tavily** - Advanced Tavily search with filtering and scoring

#### Writing (4)
- **blind-spot-detective** - Identify gaps in non-fiction writing
- **non-fiction-revision** - Non-fiction book revision
- **summarization** - Effective summarization techniques
- **voice-analysis** - Extract and document writing voice


# Claude Code Game Studios -- Game Studio Agent Architecture

Indie game development managed through 48 coordinated Claude Code subagents.
Each agent owns a specific domain, enforcing separation of concerns and quality.

## Technology Stack

- **Engine**: Godot 4.6
- **Language**: GDScript
- **Version Control**: Git with trunk-based development
- **Build System**: SCons (engine), Godot Export Templates
- **Asset Pipeline**: Godot Import System + custom resource pipeline

> **Note**: Engine-specialist agents exist for Godot, Unity, and Unreal with
> dedicated sub-specialists. Use the set matching your engine.

## Project Structure

@.claude/docs/directory-structure.md

## Engine Version Reference

@docs/engine-reference/godot/VERSION.md

## Technical Preferences

@.claude/docs/technical-preferences.md

## Coordination Rules

@.claude/docs/coordination-rules.md

## Collaboration Protocol

**User-driven collaboration, not autonomous execution.**
Every task follows: **Question -> Options -> Decision -> Draft -> Approval**

- Agents MUST ask "May I write this to [filepath]?" before using Write/Edit tools
- Agents MUST show drafts or summaries before requesting approval
- Multi-file changes require explicit approval for the full changeset
- No commits without user instruction

See `docs/COLLABORATIVE-DESIGN-PRINCIPLE.md` for full protocol and examples.

> **First session?** If the project has no engine configured and no game concept,
> run `/start` to begin the guided onboarding flow.

## Coding Standards

@.claude/docs/coding-standards.md

## Context Management

@.claude/docs/context-management.md
