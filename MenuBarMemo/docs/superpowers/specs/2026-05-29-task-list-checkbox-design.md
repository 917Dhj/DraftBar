# MenuBarMemo Task List Checkbox 设计规格

日期：2026-05-29

## 1. 背景

MenuBarMemo 当前是一个 macOS 菜单栏 Markdown 备忘录 app，编辑器基于原生 `NSTextView`，并已经有同区 Markdown 渲染逻辑。用户希望加入 Typora、GitHub Markdown 等编辑器中常见的 task list 语法，让 `- [ ]` / `- [x]` 这类列表项显示为可点击的 checkbox。

这个功能必须兼容普通无序列表。`-` 本身已经是 Markdown 列表 marker，因此 task list 应作为无序列表的更具体子语法处理，而不是改变所有 `- item` 行的交互。

## 2. 目标

实现点击 checkbox 切换 Markdown 原文状态：

```markdown
- [ ] 未完成
- [x] 已完成
```

用户看到的是 checkbox，文件保存的仍然是标准 Markdown 原文。点击 checkbox 后，底层文本在 `[ ]` 和 `[x]` 之间切换。

## 3. 非目标

本阶段不做以下能力：

- Enter 自动续写 task list。
- Backspace 智能退回普通列表。
- 拖拽排序、缩进调整或待办管理功能。
- 真实富文本 checkbox 控件。
- 任务完成统计、提醒、筛选或专门的 todo 面板。

## 4. 语法规则

Task list 只在行首列表语法完整成立时生效。支持以下形式：

```markdown
- [ ] item
- [x] item
- [X] item
* [ ] item
+ [ ] item
  - [ ] nested item
```

识别要求：

1. 允许行首缩进。
2. 列表 marker 支持 `-`、`*`、`+`。
3. marker 后必须有至少一个空白字符。
4. 方括号中只接受空格、`x`、`X`。
5. 右方括号后必须有至少一个空白字符。
6. 只有完整匹配 task list 前缀时才显示 checkbox。

这些输入不触发 task list：

```markdown
- item
- [] item
- [ ]item
- [y] item
-[ ] item
```

普通无序列表继续保留现有 bullet 渲染。识别优先级为 task list 优先，普通 unordered list 其次。

## 5. 交互设计

Task list 的视觉渲染沿用当前同区 Markdown 模型：

- 把列表 marker 位置显示为 checkbox。
- 隐藏后续 Markdown 标记片段，例如 ` [ ] ` 或 ` [x] `。
- 不改变底层 `NSTextView` 的纯文本存储。

点击行为：

1. 点击普通文本区域时，保持 `NSTextView` 默认光标和选区行为。
2. 点击 task list checkbox 显示区域时，切换该行的完成状态。
3. `- [ ] item` 切换为 `- [x] item`。
4. `- [x] item` 或 `- [X] item` 切换为 `- [ ] item`。
5. 切换时不修改缩进、列表 marker、任务正文或换行。

如果用户正在使用中文输入法 marked text，点击切换不应打断组合态。实现应避免在 marked text 存在时改写文本。

## 6. 技术设计

### 6.1 解析层

`MarkdownStyleResolver` 继续负责识别 Markdown 样式。现有 `listSpans` 的方向保持不变：先识别 task list，再退回普通 ordered / unordered list。

为支持点击切换，需要有一个小范围的 task list 元数据能力，能从文本中确定：

- checkbox 视觉所在的字符范围。
- 状态字符所在位置。
- 当前状态是否完成。

这部分逻辑应只服务 task list，不影响 heading、blockquote、code block、formula block 或普通列表。

### 6.2 切换层

新增一个小型 helper，输入当前文本和点击命中的字符位置，输出可选的编辑结果：

- 未命中 task checkbox：返回 `nil`。
- 命中未完成 task：返回把状态字符替换为 `x` 后的文本。
- 命中已完成 task：返回把状态字符替换为空格后的文本。

这个 helper 只替换方括号中间的一个字符，不重新格式化整行。

### 6.3 编辑器层

`MarkdownTextView.Coordinator` 只在鼠标点击时做 task checkbox 命中判断。

命中时：

1. 生成新的 Markdown 文本。
2. 更新 SwiftUI binding。
3. 设置合理选区，通常保持在 checkbox 附近或原点击位置附近。
4. 调用现有 Markdown refresh。

未命中时，不拦截事件，让 `NSTextView` 走默认行为。

### 6.4 渲染层

继续复用当前 `MarkdownTextStyler` 和 `MarkdownLayoutManager`：

- `taskListMarker(isChecked:)` 负责 checkbox 的视觉 glyph。
- `markdownDelimiter` 负责隐藏 ` [ ] ` / ` [x] ` 片段。
- 不引入 overlay `NSButton` 或 `NSTextAttachment`。

该方案避免把纯文本编辑器变成富文本控件，也避免维护滚动、换行、选区同步的复杂 overlay。

## 7. 代码块与公式块边界

Fenced code block 和 formula block 中的 `- [ ]` 不应被渲染为 checkbox，也不应可点击切换。

示例：

````markdown
```text
- [ ] this is code
```
````

这类内容必须保持代码文本语义。当前 resolver 已经跳过 fenced block，task list 功能应继续尊重这个边界。

## 8. 验收标准

功能验收：

1. `- item` 仍显示普通 bullet，不可勾选。
2. `- [ ] item` 显示未勾选 checkbox，点击后文本变成 `- [x] item`。
3. `- [x] item` 显示已勾选 checkbox，点击后文本变成 `- [ ] item`。
4. `- [X] item` 显示已勾选 checkbox，点击后文本变成 `- [ ] item`。
5. `  - [ ] nested` 支持缩进场景。
6. `* [ ] item` 和 `+ [ ] item` 也支持。
7. `- [] item`、`- [ ]item`、`- [y] item` 不触发 checkbox。
8. fenced code block / formula block 中的 `- [ ]` 不渲染也不可点击。
9. 点击普通文本仍能正常移动光标、选择文本。
10. 保存到 `note.md` 的内容仍是 Markdown 原文。

稳定性验收：

1. 中文输入法 marked text 期间不发生文本改写。
2. 切换 checkbox 后不触发 selection refresh 递归或崩溃。
3. 自动保存可以保存切换后的 Markdown 文本。
4. 深色和浅色模式下 checkbox 与普通 bullet 都清晰可见。

## 9. 验证方式

优先验证解析和切换逻辑：

- 用轻量单元级检查覆盖 task list 与普通 list 的边界。
- 覆盖 checked、unchecked、uppercase checked、缩进、不同 marker、非法格式、代码块边界。

工程验证：

- 跑 macOS app build。
- 手动启动 app，输入 task list，点击 checkbox，确认视觉和 `note.md` 原文都正确。
- 手动确认普通 `- item` 没有被误识别。

如果当前工程没有 XCTest target，不为这个功能做大规模测试结构重构；可以先用最小验证路径覆盖纯逻辑，再用 Xcode build 和手动运行确认集成效果。

