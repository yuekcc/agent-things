# Skill 精选

**来源**：

- [mattpocock/skills](https://github.com/mattpocock/skills/releases/tag/v1.0.1)
- [playwright-cli](https://github.com/microsoft/playwright-cli/releases/tag/v0.1.15)
- [code-simplifier](https://github.com/euxx/claude-skills-for-copilot/blob/main/skills/code-simplifier/SKILL.md)
- [claude-plugins-official](https://github.com/anthropics/claude-plugins-official)

## 索引

47 个 skill，按用途分组。「手动」表示 `disable-model-invocation: true`，只能由用户显式调用（如 `/recap`），不会自动触发。

### 需求与规划

| Skill | 说明 | |
| --- | --- | --- |
| [readback](skills/readback/SKILL.md) | 复述需求以确认理解，适合长、口述、含糊的提示 | 手动 |
| [sharpen](skills/sharpen/SKILL.md) | 开工前打磨任务：专家做法、真实意图、合适的规格粒度 | 手动 |
| [grilling](skills/grilling/SKILL.md) | 围绕计划或想法高强度提问，压力测试思路 | |
| [grill-me](skills/grill-me/SKILL.md) | 高强度面试式追问，打磨计划或设计 | 手动 |
| [grill-with-docs](skills/grill-with-docs/SKILL.md) | 同上，并在过程中产出 ADR 与术语表 | 手动 |
| [clean-room](skills/clean-room/SKILL.md) | 交给全新 agent 一份中性简报，在无对话上下文中独立判断 | 手动 |
| [facts](skills/facts/SKILL.md) | 用平实语言向工程师交代一件事的关键事实与影响 | 手动 |
| [create-prd](skills/create-prd/SKILL.md) | 用用户故事地图分析需求并生成 PRD | |
| [to-spec](skills/to-spec/SKILL.md) | 把当前对话综合成 spec，发布到 issue tracker | 手动 |
| [to-tickets](skills/to-tickets/SKILL.md) | 把计划/spec 拆成带阻塞关系的 tracer-bullet 任务单 | 手动 |
| [implement](skills/implement/SKILL.md) | 按 spec 或任务单实现 | 手动 |
| [implement-spec](skills/implement-spec/SKILL.md) | 实现 `/to-spec` 与 `/to-tickets` 的产物 | 手动 |
| [prototype](skills/prototype/SKILL.md) | 写一次性原型，验证状态模型、逻辑或 UI 方向 | |
| [take-it-easy](skills/take-it-easy/SKILL.md) | YAGNI，想明白再动手 | |

### 代码质量

| Skill | 说明 | |
| --- | --- | --- |
| [code-review](skills/code-review/SKILL.md) | 从固定点起审查改动：一边对规范，一边对 spec，并行跑后并列汇报 | |
| [codebase-design](skills/codebase-design/SKILL.md) | 深模块设计与接口改进的共同词汇 | |
| [improve-codebase-architecture](skills/improve-codebase-architecture/SKILL.md) | 扫描代码库的深化机会，出一份 HTML 报告再逐个追问 | 手动 |
| [diagnosing-bugs](skills/diagnosing-bugs/SKILL.md) | 疑难 bug 与性能回归的诊断回路 | |
| [tdd](skills/tdd/SKILL.md) | 测试先行，红-绿-重构，含集成测试 | |
| [simplify](skills/simplify/SKILL.md) | 不改变行为的前提下简化代码 | |
| [domain-modeling](skills/domain-modeling/SKILL.md) | 建立并打磨领域模型、GLOSSARY.md、ADR | |

### 开发流程

| Skill | 说明 | |
| --- | --- | --- |
| [pr](skills/pr/SKILL.md) | 撰写 PR 描述 | |
| [qtm-commit-code](skills/qtm-commit-code/SKILL.md) | 分批提交代码，需用户指定 | 手动 |
| [retro](skills/retro/SKILL.md) | 对一次编码会话做复盘 | 手动 |
| [handoff](skills/handoff/SKILL.md) | 把对话压缩成交接文档，供另一个 agent 接手 | 手动 |
| [recap](skills/recap/SKILL.md) | 用两三句话总结本次会话的最新进展 | 手动 |
| [status](skills/status/SKILL.md) | 用 ASCII 状态板在终端呈现手头工作，而不是一段文字 | 手动 |
| [ladder](skills/ladder/SKILL.md) | 用纵向进度梯在终端呈现一条工作线，完成在上、待办在下 | 手动 |
| [research](skills/research/SKILL.md) | 基于高可信一手资料调研，并把结论写成仓库里的 Markdown | |
| [teach](skills/teach/SKILL.md) | 在当前工作区内教用户一个新技能或概念 | 手动 |

### 表达与呈现

| Skill | 说明 | |
| --- | --- | --- |
| [bro](skills/bro/SKILL.md) | 用大白话重述上一条消息，去掉术语 | 手动 |
| [one-pager](skills/one-pager/SKILL.md) | 做一页 HTML：多图少字，早分享或复盘皆可 | 手动 |
| [big-pics-little-words](skills/big-pics-little-words/SKILL.md) | 用大图少字的 HTML 讲清当前主题，同时保留关键细节 | 手动 |
| [show-me](skills/show-me/SKILL.md) | 像给 15 岁的人讲解一样，用一个极简图讲清原理 | |

### 写作与文档

| Skill | 说明 | |
| --- | --- | --- |
| [technical-writing](skills/technical-writing/SKILL.md) | 分层写作标准：Diátaxis 结构、Google 风格、STE 指令规则、Global English | 手动 |
| [writing-for-agents](skills/writing-for-agents/SKILL.md) | 写给 agent 看的文档：skill、AGENTS.md、CLAUDE.md | |
| [docx](skills/docx/SKILL.md) | 读写、编辑 Word 文档，含目录、页码、批注、修订 | |
| [pdf](skills/pdf/SKILL.md) | PDF 读取抽取、合并拆分、旋转、水印、表单、加解密、OCR | |
| [pptx](skills/pptx/SKILL.md) | 幻灯片/演示文稿的读取、创建与编辑 | |
| [xlsx](skills/xlsx/SKILL.md) | 表格文件为主要输入或输出时使用：编辑、公式、图表、清洗 | |

### 语言规范

| Skill | 说明 | |
| --- | --- | --- |
| [go-modern](skills/go-modern/SKILL.md) | Go 1.23–1.26 新特性、迁移与现代化写法 | |
| [write-c3](skills/write-c3/SKILL.md) | C3 语言编程指导 | |
| [write-odin](skills/write-odin/SKILL.md) | Odin 语言编程指导 | |
| [write-zig](skills/write-zig/SKILL.md) | Zig 语言编程指导 | |
| [zig-tiger-style](skills/zig-tiger-style/SKILL.md) | TigerBeetle 出品的 Zig 风格与断言、内存布局、命名约定 | |

### 前端

| Skill | 说明 | |
| --- | --- | --- |
| [web-design-guidelines](skills/web-design-guidelines/SKILL.md) | 按 Web Interface Guidelines 审查 UI，含可访问性与 UX | |
| [playwright-cli](skills/playwright-cli/SKILL.md) | 浏览器自动化、页面测试与 Playwright 测试 | |

## 备注

- `skills/user-story-mapping/` 是空目录，没有 `SKILL.md`，未计入索引。
- 总目录数 48，有效 skill 47。
