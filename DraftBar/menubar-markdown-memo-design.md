# 菜单栏 Markdown 备忘录 App 初版设计方案

日期：2026-05-27

## 1. 产品定位

做一个 macOS 菜单栏备忘录 app，目标不是替代 Obsidian、Apple Notes 或完整待办软件，而是提供一个随手打开、立刻输入、自动保存的极简 Markdown 草稿区。

核心感觉参考 SlashNote 的“从菜单栏出现一张便签”，但功能范围更小，优先保证中文输入稳定、Markdown 输入顺手、视觉符合 Apple 最新 Liquid Glass 设计语言。

## 2. 一句话目标

点击菜单栏图标，弹出一个空白 Markdown 备忘录；用户可以稳定输入中文和 Markdown，内容自动保存，再次打开时继续编辑。

## 3. 目标用户

- 经常在 Mac 上临时记录想法、链接、待办片段、会议中的一句话。
- 需要比便签更轻、比完整笔记软件更快的入口。
- 偏好 Markdown 原文输入，而不是复杂富文本工具栏。
- 对中文输入法兼容性敏感。

## 4. MVP 范围

只做一个 note。

必须包含：

1. 菜单栏图标。
2. 点击图标后弹出一个编辑窗口。
3. 编辑区支持 Markdown 原文输入。
4. 中文输入法稳定：拼音候选、选词、组合态、撤销、复制粘贴都不能丢字。
5. 内容自动保存到本地。
6. app 默认不显示 Dock 图标。
7. 支持浅色、深色、跟随系统外观。

暂不包含：

- 多便签。
- 云同步。
- AI。
- 提醒事项。
- Markdown 分屏预览。
- 富文本编辑工具栏。
- 标签、搜索、文件夹。
- 协作或账号系统。

## 5. 用户体验流程

### 5.1 首次启动

- app 启动后只在菜单栏显示一个图标。
- 不弹 onboarding。
- 第一次点击菜单栏图标，出现空白编辑窗口。
- 光标自动聚焦到编辑区。

### 5.2 日常记录

1. 用户点击菜单栏图标。
2. 窗口从菜单栏下方弹出。
3. 用户直接输入中文或 Markdown。
4. app 在后台自动保存。
5. 用户点击窗口外部或按 `Esc`，窗口收起。
6. 下次打开时，内容保持原样，光标位置尽量恢复。

### 5.3 退出

- 菜单栏右键或窗口内更多菜单提供 `Quit`。
- MVP 可先不做设置面板。

## 6. UI 设计方向

### 6.1 总体原则

采用 Apple Liquid Glass 设计语言，但保持克制。这个 app 的主角是文字，不是视觉特效。

根据 Apple 官方设计资料，Liquid Glass 更适合表达浮在内容上方的控件层、导航层和临时操作层；编辑正文需要保持清晰、稳定和高对比度。因此本 app 不把整个文字编辑区做成强玻璃效果，而是：

- 窗口外层使用系统 material / Liquid Glass 风格。
- 编辑纸面保持安静、清晰、近似原生文本区域。
- 顶部极少量控件使用 Liquid Glass 风格。
- 不使用大面积渐变、装饰光斑或复杂背景。

### 6.2 窗口形态

建议尺寸：

- 默认宽度：420 px。
- 默认高度：520 px。
- 最小宽度：320 px。
- 最小高度：260 px。

窗口行为：

- 从菜单栏图标锚定弹出。
- 圆角使用系统推荐的自然圆角，不做夸张卡片圆角。
- 有轻微阴影，表达浮层关系。
- 点击外部默认收起。
- 用户可选是否 pin 住窗口，这个功能不进 MVP，后续再考虑。

### 6.3 布局

结构：

```text
┌──────────────────────────────┐
│ 顶部轻量工具行                │
│  - 左侧：状态/字数，可选       │
│  - 右侧：更多菜单，可选       │
├──────────────────────────────┤
│                              │
│ Markdown 编辑区               │
│                              │
└──────────────────────────────┘
```

MVP 可以进一步简化为只有编辑区，不显示顶部工具行。若保留工具行，必须非常轻，不要挤占输入空间。

### 6.4 Liquid Glass 应用点

推荐：

- 窗口背景：使用 `NSVisualEffectView` 或 SwiftUI material。
- 顶部工具行：使用系统 material，和正文之间用 subtle scroll edge / 轻边界区分。
- 图标按钮：使用 SF Symbols，透明或 glass-like 背景。
- 菜单：使用系统菜单，不自绘。

避免：

- 在正文底下放复杂照片或彩色背景。
- 把编辑器文本直接铺在透明玻璃上导致可读性下降。
- 手工模拟过度玻璃反光。
- 自定义键盘事件来实现 Markdown 快捷输入，容易影响中文输入。

## 7. Markdown 输入设计

MVP 是 Markdown 原文编辑器，不做实时渲染。

支持的输入内容包括：

- 标题：`# Heading`
- 列表：`- item`
- 任务框：`- [ ] task`
- 加粗：`**text**`
- 链接：`[title](url)`
- 代码：`` `code` ``
- 代码块：triple backticks

MVP 不需要 Markdown 语法高亮。原因：

- 语法高亮会引入编辑器复杂度。
- 如果实现不谨慎，容易影响中文输入法组合态。
- 第一版目标是稳定输入，而不是编辑器功能丰富。

后续增强可以考虑：

- Markdown 语法高亮。
- 自动补全列表项。
- `Cmd+B` 插入加粗标记。
- `Cmd+K` 插入链接标记。
- 只读预览模式。

## 8. 中文输入法要求

这是核心质量门槛。

实现约束：

1. 不使用 WebView、Canvas、自绘文本控件作为第一版编辑器。
2. 不拦截普通字符输入事件。
3. 不在 `keyDown` 里主动改写正在输入的 marked text。
4. 优先使用原生 `NSTextView`。
5. SwiftUI 可用 `NSViewRepresentable` 包装 `NSTextView`，而不是直接依赖 `TextEditor`。

必须测试：

- macOS 自带拼音输入法。
- 搜狗/微信输入法等第三方中文输入法，如机器上已安装。
- 连续输入长句。
- 选词后是否丢第一个字或最后一个字。
- 输入期间自动保存是否打断组合态。
- Markdown 符号和中文混输，例如：`- 今天要做：整理设计稿`。
- 撤销/重做。
- 复制粘贴中文段落。

## 9. 技术方案

推荐使用原生 macOS。

### 9.1 技术栈

- 语言：Swift。
- App 生命周期：SwiftUI App 或 AppKit App 均可。
- 菜单栏：`NSStatusItem`。
- 弹出窗口：优先 `NSPopover`；如果需要更强控制，改用 `NSPanel`。
- 编辑器：`NSTextView`。
- 存储：本地 Markdown 文件。

### 9.2 为什么不用 Electron / Tauri

这个 app 的功能非常小，原生方案更适合：

- 包体小。
- 启动快。
- 更贴近 macOS 菜单栏行为。
- 中文输入法兼容性更可控。
- Liquid Glass / system material 更自然。

### 9.3 存储方案

MVP 建议保存为一个本地 Markdown 文件：

```text
~/Library/Application Support/DraftBar/note.md
```

自动保存策略：

- 文本变化后 debounce 300-500 ms 保存。
- app 退出、窗口关闭、失焦时强制保存一次。
- 保存失败时不弹阻塞弹窗，可在顶部状态处显示简短错误。

后续可选：

- 用户自定义保存路径。
- 保存到 iCloud Drive。
- 与 Obsidian vault 中的某个 inbox 文件绑定。

## 10. 菜单栏与窗口行为

菜单栏图标：

- 使用 template image，适配浅色/深色菜单栏。
- 图标语义：note、text bubble、square.and.pencil 等 SF Symbols 方向。

点击行为：

- 左键：显示/隐藏备忘录窗口。
- 右键或 `Control + Click`：打开菜单，包含 `Show Note`、`Open Note File`、`Quit`。

窗口焦点：

- 打开时自动 focus 编辑器。
- 收起再打开时保留光标位置。
- 点击外部收起，但如果用户正在中文输入法候选态中，不应误关闭。

快捷键：

- MVP 可不做全局快捷键。
- 后续建议 `Option + Space` 或用户自定义快捷键。

## 11. 视觉规格

颜色：

- 跟随系统语义色，不手写大面积品牌色。
- 文本使用系统 label color。
- 背景使用 system material。
- 编辑区使用接近 `textBackgroundColor` 的稳定底色。

字体：

- 正文字体：系统字体或 `SF Pro` 语义字体。
- 默认字号：14-15 pt。
- 行高：略宽松，适合中文段落。
- 不使用负字距。

控件：

- 使用系统小尺寸控件。
- 按钮尽量 icon-only + tooltip。
- 不在紧凑工具栏里塞文字按钮。

空状态：

- 空白编辑器即可。
- 可以用 placeholder：`Start writing...` 或 `写点什么...`。
- placeholder 不要像 onboarding 文案，不要解释功能。

## 12. App 名称候选

临时内部名：

- DraftBar
- GlassMemo
- QuickLeaf
- Memospace

建议第一版工程名用 `DraftBar`，避免过早品牌化。

## 13. 验收标准

第一版可用标准：

1. 启动 app 后菜单栏出现图标。
2. 点击图标弹出编辑窗口。
3. 可以稳定输入中文，不丢字。
4. 可以输入 Markdown 原文。
5. 关闭再打开窗口，内容仍在。
6. 重启 app 后，内容仍在。
7. 浅色/深色模式下文字可读。
8. app 不显示 Dock 图标。
9. 不需要联网。
10. 没有账号、同步、AI 等额外复杂功能。

## 14. 开发拆分

### Milestone 1：可输入原型

- 创建 macOS app 工程。
- 添加 `NSStatusItem`。
- 点击菜单栏图标弹出窗口。
- 放入 `NSTextView`。
- 支持输入和关闭。

验证：中文输入稳定，无明显丢字。

### Milestone 2：自动保存

- 建立 application support 目录。
- 读写 `note.md`。
- 文本变化自动保存。
- app 启动时恢复内容。

验证：重启 app 后内容存在。

### Milestone 3：视觉打磨

- 加入 system material / Liquid Glass 风格背景。
- 调整窗口圆角、阴影、边距、字号。
- 适配浅色/深色模式。

验证：截图检查可读性，不让视觉效果压过文字。

### Milestone 4：基础菜单

- 右键菜单添加 `Open Note File` 和 `Quit`。
- 处理保存错误状态。

验证：菜单项可用，退出前保存。

## 15. 主要风险

### 风险 1：中文输入法丢字

规避：

- 使用 `NSTextView`。
- 不自绘编辑器。
- 不在输入过程中重建编辑视图。
- 自动保存读取 text storage，但不要反向覆盖正在编辑的文本。

### 风险 2：Liquid Glass 做得过度影响可读性

规避：

- 玻璃效果只用于窗口外层和控件层。
- 正文区域保持稳定背景和足够对比度。
- 遵循系统 material，不自造复杂透明背景。

### 风险 3：popover 行为限制

规避：

- MVP 先用 `NSPopover`。
- 如果需要可调整大小、pin 住、复杂焦点行为，再切换到 `NSPanel`。

### 风险 4：功能膨胀

规避：

- 第一版只做一个 note。
- 不做多便签、不做同步、不做预览。
- 任何新增功能必须先证明不会影响中文输入稳定性。

## 16. 给接手 agent 的实施提示

优先级顺序：

1. 先保证原生文本输入稳定。
2. 再做菜单栏窗口行为。
3. 再做自动保存。
4. 最后做 Liquid Glass 视觉。

不要一开始写复杂 Markdown 编辑器。第一版 Markdown 支持的含义是“允许用户输入 Markdown 文本并保存为 `.md`”，不是“实现完整 Markdown IDE”。

如果 SwiftUI `TextEditor` 出现中文输入问题，立刻换成 AppKit `NSTextView` 包装，不要继续在 SwiftUI 层面补丁式修。

## 17. 官方设计参考

- Apple Developer: [Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/liquid-glass)
- Apple Developer: [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- WWDC25: [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)
- WWDC25: [Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356)
- WWDC25: [Build an AppKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/310/)

