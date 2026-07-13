# DraftBar 原生 Markdown 编辑器候选调研

调研日期：2026-07-13  
范围：可作为 Swift Package 嵌入 macOS / SwiftUI / AppKit 应用的原生组件；只采用项目官方仓库、源码、Package.swift、release 与 issue 作为依据。

## 结论

**有可以直接试用的现成组件，但目前只有 `swift-markdown-engine` 与 DraftBar 的“同一个编辑区内边输入边渲染”模型基本匹配。**

建议：用固定版本 `0.8.0` 做一个隔离 POC，通过中文输入法、撤销、自动保存、焦点恢复、任务框、表格、图片、公式和长文本测试后再决定是否替换。不要现在就直接删除 DraftBar 的现有实现：这个库仍是 pre-1.0，而且已有公开的内存泄漏、列表退出、换行和表格问题。

`MarkdownUI`、`Textual` 和 `Down` 都是渲染器，不是编辑器；`Runestone` 是 iOS 源码编辑器；`STTextView` 只是通用 TextKit 2 编辑控件。`SwiftDown` 曾经非常接近需求，但现已归档。它们都不应成为 DraftBar 当前的新编辑器核心。

## 快速对比

| 候选 | 当前状态（2026-07-13） | 许可证 / 平台 | 编辑与渲染模型 | Markdown 覆盖 | 对 DraftBar 的判断 |
|---|---|---|---|---|---|
| [SwiftMarkdownEngine](https://github.com/nodes-app/swift-markdown-engine) | `0.8.0`，2026-06-28 发布；仓库 2026-07-12 仍有提交；约 728 stars；pre-1.0 | Apache-2.0；macOS 14+；Swift 5.9 / Xcode 15+ | TextKit 2 `NSTextView`；Markdown 源文保持为存储真值，非活动标记缩小隐藏；提供可切换 raw source mode。属于 Typora 式 live-styled source / WYSIWYM，不是真正结构化 WYSIWYG | 标题、强调、删除线、highlight、列表、引用、链接、代码、GFM 表格、任务框、图片、LaTeX、wiki link；**未声明 CommonMark/GFM 规范一致性** | **唯一值得优先 POC 的原生整合型候选**；功能很贴合，但成熟度风险中高 |
| [Textual](https://github.com/gonzalezreal/textual) | `0.5.0`，2026-06-15；约 796 stars；活跃 | MIT；macOS 15+；Swift 6 | SwiftUI 富文本**只读渲染**，基于 Foundation `AttributedString` Markdown parser；支持选择复制，不支持编辑 | 标题、列表、表格、链接、代码高亮、图片/附件、内联与块数学；README 未声明完整 CommonMark/GFM 一致性，任务框未明确列为能力 | 适合独立预览页，不可替换编辑器 |
| [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) | `2.4.1`，2024-10-13；约 3.9k stars；官方已标为 maintenance mode，新开发转向 Textual | MIT；macOS 12+；表格等部分能力需 macOS 13+ | SwiftUI **只读渲染** | 官方明确兼容 GFM；图片、标题、列表/任务列表、引用、代码块、表格；未记录数学公式支持 | 预览能力成熟，但不解决输入体验和自研编辑逻辑；不建议作为新主线 |
| [Runestone](https://github.com/simonbs/Runestone) | `0.5.2`，2026-03-25；约 3.2k stars；活跃 | MIT；Package.swift **仅 iOS 14+** | 基于 Tree-sitter 的高性能纯文本/代码编辑器，源码模式、语法高亮 | 不提供 Markdown 语义渲染；图片、表格、任务框、数学不渲染 | 不适用。官方称 Catalyst “mostly work”但未完成、未充分测试；不是原生 AppKit 方案 |
| [Down](https://github.com/johnxnguyen/Down) | 最新 tag `v0.11.0` 对应 2021-05-04；最后 push 2023-07-15；约 2.5k stars | MIT（并保留所含 cmark 等第三方许可证）；macOS 10.11+ | CommonMark parser / renderer；可输出 HTML、AST、`NSAttributedString`，`DownView` 是 WebView；**无编辑器** | 基于 cmark 0.29.0 的 CommonMark；不是 GFM，因此表格/任务框不是其标准能力；无数学扩展 | 维护与架构都不适合成为新编辑器核心；WebView 路线还违背 DraftBar 最初的原生输入约束 |
| [SwiftDown](https://github.com/qeude/SwiftDown) | `0.4.1`，2024-02-19；约 570 stars；仓库已归档 | MIT；macOS 12+ / iOS 14+ | 原生同区 live preview，基于 Down/cmark，纯 Markdown 存储 | CommonMark 范围；未记录 GFM 表格、任务框或数学支持 | 功能形态接近，但归档且依赖停滞的 Down；不应新采用 |
| [STTextView](https://github.com/krzyzanowskim/STTextView) | `2.3.10`，2026-04-29；约 1.6k stars；活跃 | GPLv3 或商业许可证；macOS 14+ / iOS 16+；Swift 5.9 | TextKit 2 `NSTextView` 替代品，支持 SwiftUI、插件、源码高亮 | **没有 Markdown parser/rendering**；图片、表格、任务框、数学均需另做 | 能替换底层文本控件，不能删除 DraftBar 的 Markdown 自研逻辑；许可证也增加整合成本 |

维护数据来自各仓库的 [GitHub API 元数据](https://api.github.com/repos/nodes-app/swift-markdown-engine)、[Textual releases](https://github.com/gonzalezreal/textual/releases)、[MarkdownUI releases](https://github.com/gonzalezreal/swift-markdown-ui/releases)、[Runestone releases](https://github.com/simonbs/Runestone/releases) 和 [Down tags](https://github.com/johnxnguyen/Down/tags)。stars 是调研当日快照，不用于决定技术选型。

## 1. SwiftMarkdownEngine：最匹配，但先 POC

### 为什么匹配

- 官方定位就是“native AppKit Markdown editor for macOS, built on TextKit 2 and bridged to SwiftUI”，并直接提供 `NativeTextViewWrapper(text:)`。[README](https://github.com/nodes-app/swift-markdown-engine#quick-start)
- 核心 `MarkdownEngine` product 无外部依赖；代码高亮与 LaTeX 作为可选 products 提供。[Package.swift](https://github.com/nodes-app/swift-markdown-engine/blob/main/Package.swift)
- DraftBar 已使用 `SwiftMath 1.7.3`；该库的 `MarkdownEngineLatex` 依赖 `SwiftMath >= 1.7.0`，SwiftPM 理论上可以复用同一版本，而不是引入第二套数学渲染库。
- 它使用原生 `NSTextView` / TextKit 2，天然比 WebView 编辑器更接近 DraftBar 对中文 IME 和 macOS 文本系统的要求。
- 支持普通 Markdown 图片与 Obsidian 图片、点击任务框、GFM 表格、代码块高亮、内联/块 LaTeX；这些正是 DraftBar 当前自研逻辑容易出错的部分。[功能列表](https://github.com/nodes-app/swift-markdown-engine#features)
- 除实时样式模式外，`rawSourceMode` 可在运行时切换为完全原文；官方测试说明切换会清空当前文档的 undo stack，以免旧范围失效。[源码模式配置](https://github.com/nodes-app/swift-markdown-engine/blob/main/Sources/MarkdownEngine/Configuration/MarkdownEditorConfiguration.swift)

### 不是“零风险替换”

1. **没有规范一致性承诺。** README 只列出支持的 Markdown 功能，没有声明通过 CommonMark 或 GFM conformance suite。其 parser 是项目自己的 block parser + inline AST；因此它能减少 DraftBar 自己维护语法的工作，但并不等于把规范一致性问题彻底交给成熟标准实现。
2. **项目仍很新。** 仓库 2026-04-28 创建，目前明确标记 pre-1.0；README 建议生产环境 pin 具体 `0.x.y` 版本。[Requirements & Status](https://github.com/nodes-app/swift-markdown-engine#requirements--status)
3. **有与 DraftBar 直接相关的公开缺陷：**
   - [`#63`](https://github.com/nodes-app/swift-markdown-engine/issues/63)：`makeNSView` 注册的 observer token 未移除，关闭编辑器后整套 scroll/TextKit/coordinator 会泄漏。
   - [`#68`](https://github.com/nodes-app/swift-markdown-engine/issues/68)：空无序列表按 Enter 退出后，Text Services Manager 的后续插入可能把列表标记恢复。这个问题与输入法/文本服务路径高度相关。
   - [`#56`](https://github.com/nodes-app/swift-markdown-engine/issues/56)：普通换行、段落换行的渲染存在问题。
   - [`#40`](https://github.com/nodes-app/swift-markdown-engine/issues/40)：表格缩放仍有问题。
   - [`#58`](https://github.com/nodes-app/swift-markdown-engine/issues/58)：自定义 TextKit 2 layout fragment 导致拼写下划线不显示。
4. **DraftBar 的焦点入口需要额外验证。** `NativeTextViewWrapper` 当前公开 API 有文本、文档 id、可编辑状态及若干回调，但没有显式的 `FocusState` / focus request binding。DraftBar 每次弹出窗口都要求自动把 `NSTextView` 设为 first responder，这一点可能需要一个很小的本地 wrapper 或上游 API。
5. **部分默认行为与 DraftBar 不同。** 例如库默认打开拼写/语法/自动纠错和智能引号；DraftBar 当前明确关闭这些行为。拼写相关行为有 configuration；智能引号在当前 wrapper 源码中直接设为开启，可能需要上游支持或一个极小的本地补丁。POC 必须核对，不应默认接受。

### 集成风险判断

**中高风险，但明显低于继续扩展当前自研 parser/styler 的长期风险。**

最省事的验证方式不是立刻迁移全部代码，而是仅用它替换 `MarkdownTextView` 的可视编辑区域，保留 DraftBar 的 `DraftStore`、自动保存、窗口与焦点控制。POC 失败时可以完整撤回，不影响数据格式，因为存储仍是 Markdown 字符串。

## 2. Textual：很好的渲染器，不是编辑器

Textual 是 MarkdownUI 的后继项目，但官方定义是 SwiftUI text rendering engine。`InlineText` 和 `StructuredText` 都把 markup 变成 SwiftUI 可选择文本；README 没有任何编辑 API。其优势是：

- 原生 SwiftUI 渲染，不是 WebView；
- 图片/动画附件、代码高亮、表格和数学公式支持好；
- 当前仍在开发，最新 release 为 `0.5.0`；
- MIT，macOS 15+，与 DraftBar 的 macOS 26 target 兼容。[README](https://github.com/gonzalezreal/textual) · [Package.swift](https://github.com/gonzalezreal/textual/blob/main/Package.swift) · [0.5.0](https://github.com/gonzalezreal/textual/releases/tag/0.5.0)

它只适合以下产品变化：DraftBar 改成“普通 Markdown 源码编辑器 + 单独预览页/分屏预览”。如果目标仍是当前这种在同一编辑区隐藏标记并显示格式，Textual 不能替换自研编辑逻辑。

## 3. MarkdownUI：GFM 渲染成熟，但已经进入维护模式

MarkdownUI 明确兼容 GFM，并支持图片、任务列表、代码块和表格，是这些候选中 Markdown 渲染契约最清楚的。但它只有 `Markdown` 显示 view，没有编辑器；而且官方已在 README 顶部声明 maintenance mode，新开发转到 Textual。[README](https://github.com/gonzalezreal/swift-markdown-ui)

所以即使 DraftBar 采用分屏预览，新项目也更应先评估 Textual；只有在必须依赖 MarkdownUI 已有 GFM 行为时，才值得选 MarkdownUI。

## 4. Runestone：技术成熟，但平台与任务都不匹配

Runestone 是优秀的 iOS 纯文本/代码编辑器，依靠 Tree-sitter 做增量语法高亮，适合大文件和源码编辑。但官方 `Package.swift` 只声明 iOS 14；README 说明 Catalyst 虽“mostly work”，但未充分测试且实现未完成。[README](https://github.com/simonbs/Runestone) · [Package.swift](https://github.com/simonbs/Runestone/blob/main/Package.swift)

更关键的是，它不会把 Markdown 表格、图片、任务框和数学渲染成 DraftBar 现在的视觉效果。即使移植到 macOS，也还要另外实现渲染与编辑映射，因此不应选。

## 5. Down：标准 CommonMark 渲染，不提供编辑器

Down 是 cmark 0.29.0 的 Swift wrapper，CommonMark parser 很成熟，支持 HTML、AST、`NSAttributedString` 等输出。但它没有 Markdown 编辑器；`DownView` 明确是 WebView。[README](https://github.com/johnxnguyen/Down) · [Package.swift](https://github.com/johnxnguyen/Down/blob/master/Package.swift)

它也不是 GFM parser，因此不能直接承担 DraftBar 所需的表格和任务框；最新 tag `v0.11.0` 对应 2021-05-04，维护活跃度明显落后。它最多适合离线 CommonMark 转换，不适合作为 DraftBar 新编辑核心。

## 6. SwiftDown 与 STTextView：一个已归档，一个层级太低

[SwiftDown](https://github.com/qeude/SwiftDown) 的产品形态其实很接近 DraftBar：同一编辑区内 live preview、纯 Markdown 存储、原生 macOS/iOS，并复用 Down/cmark。但最新版本 `0.4.1` 发布于 2024-02-19，仓库已经归档；它还继承 Down 只有 CommonMark、缺少明确 GFM 表格/任务框和数学支持的边界。因此不应把一个无人维护的组件引入编辑器核心。

[STTextView](https://github.com/krzyzanowskim/STTextView) 是活跃、性能导向的 TextKit 2 `NSTextView` 替代品，最新 `2.3.10` 支持 macOS 14+ 和 SwiftUI，也有源码高亮插件。但它完全不提供 Markdown parser 或语义渲染；采用后仍需 DraftBar 自己实现 Markdown spans、标记隐藏、表格、图片和数学，不能解决本次根因。[README](https://github.com/krzyzanowskim/STTextView) · [Package.swift](https://github.com/krzyzanowskim/STTextView/blob/main/Package.swift)

此外，STTextView 采用 GPLv3 / 商业双许可，而 DraftBar 当前为 MIT。若不购买商业许可，就需要单独评估整个应用的分发许可义务；这进一步降低了它仅作为底层控件的吸引力。[LICENSE.md](https://github.com/krzyzanowskim/STTextView/blob/main/LICENSE.md)

## 7. 一个容易误判的新包

[1amageek/swift-markdown-ui](https://github.com/1amageek/swift-markdown-ui) 在 README 中称可“rendering and editing”，并且正好要求 macOS 26。但源码中的 `MarkdownEditor` 只是普通 `NSTextView` 的薄 wrapper，编辑时没有 Markdown 实时样式；渲染要另放一个 `MarkdownView`。截至调研日：

- 约 1 star，无 GitHub release；
- README 写 MIT，但仓库没有 `LICENSE` 文件，GitHub API 也无法识别许可证；
- 2026-04-19 后无提交。

因此不把它列为正式候选。它比 DraftBar 的原始 `NSTextView` 方案提供得更少，并不能解决问题。

## 建议的 POC 验收门槛

POC 只需要回答“能不能可靠替代当前编辑区”，不要顺带重构存储、窗口或视觉系统。

必须通过：

1. macOS 系统拼音连续长句、候选选词、中英与 Markdown 标记混输，marked text 期间不丢字、不跳光标。
2. `Cmd+Z` / `Cmd+Shift+Z`、复制粘贴、查找，以及窗口收起再打开后的自动聚焦和选区恢复。
3. DraftBar 的 debounce 自动保存期间不破坏组合态，磁盘内容始终是纯 Markdown 源文。
4. 标题、粗体/斜体/删除线、链接、列表、任务框、引用、代码块、表格、图片、内联与块公式的输入、删除、跨行选择。
5. 专门复现上游 `#68` 的空列表退出，并检查 Enter、Shift+Enter、中文输入法确认键之间的交互。
6. 连续显示/销毁编辑器后没有 `#63` 描述的持续内存增长。
7. 现有 macOS 26 Liquid Glass 外壳、透明背景、内边距、滚动条和菜单栏弹窗行为不退化。

通过上述门槛后，才值得删除 DraftBar 目前 `ContentView.swift` 中的 `MarkdownStyleResolver`、`MarkdownTextStyler`、`MarkdownLayoutManager`、公式 overlay 与代码块输入辅助。若失败，保留现有编辑器，最多把“只读预览”交给 Textual；不要同时引入两个新渲染系统。

## 最终排序

1. **SwiftMarkdownEngine 0.8.0：做 POC，当前唯一仍在维护且形态贴合的候选。**
2. **Textual 0.5.0：仅当接受源码编辑 + 独立预览时使用。**
3. **MarkdownUI 2.4.1：已有项目可继续用，新主线不优先。**
4. **SwiftDown 0.4.1：形态匹配但已归档，排除。**
5. **STTextView：只提供文本控件且有 GPL/商业许可成本，排除。**
6. **Down：只适合 CommonMark 转换/只读输出。**
7. **Runestone：不适用于原生 macOS Markdown 渲染编辑。**
