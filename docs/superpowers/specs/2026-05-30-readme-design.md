# DraftBar README Design

Date: 2026-05-30

## Goal

Create a product-first README for opening DraftBar on GitHub. The primary reader is an ordinary macOS user who wants to understand what the app does and how to install it, not a developer looking for build instructions.

The README will be published in two synchronized files:

- `README.md`
- `README.zh-CN.md`

## Audience And Positioning

DraftBar should be introduced as a tiny menu bar scratchpad for quick drafts on macOS.

The first screen should make the core idea obvious:

- DraftBar lives in the macOS menu bar.
- It is ready for quick capture without switching into a full notes workspace.
- It is local-first and lightweight.

Markdown editing, draggable floating behavior, and local storage are supporting features, not the headline.

## Non-Goals

The README will not include a `Build`, `Build from source`, `Development`, or local Xcode build section.

The README will not include a `Known Limitations` section for the first open-source version.

The README will not include fake screenshots, placeholder images, or fake GIFs. Real demo assets can be added later.

## Information Architecture

Use this section order in both language versions:

1. Hero
2. Demo
3. Features
4. Install
5. Usage
6. Data and Privacy
7. Roadmap
8. Contributing
9. License

## Hero

English draft:

```md
# DraftBar

A tiny menu bar scratchpad for quick drafts on macOS.

DraftBar lives in your menu bar, ready when you need to jot something down without switching apps or opening a full notes workspace.
```

Chinese draft:

```md
# DraftBar

macOS 菜单栏里的随手草稿纸。

DraftBar 常驻菜单栏，在你需要临时记一段话、列一个待办、草拟一点 Markdown 时快速弹出，不打断当前工作流。
```

Include a small badge/link row:

- Language switch link
- `macOS`
- `MIT License`
- `Latest Release`
- `Download for macOS` link to GitHub Releases

Keep badges sparse. The top of the README should feel like a simple product entry, not a CI dashboard.

## Demo

Use a text-only demo section for now. Later, replace or augment it with a real screenshot and short GIF.

English draft:

```md
## Demo

Open DraftBar from the menu bar, capture a thought, then get back to what you were doing. You can also drag from the menu bar icon to place the note where it feels natural.
```

Chinese draft:

```md
## 演示

从菜单栏唤起 DraftBar，快速记下一段草稿，然后回到原来的工作。你也可以从菜单栏图标拖出草稿窗，把它放在更顺手的位置。
```

Do not write "coming soon" in the visible README.

## Features

Use a two-column table instead of a bullet list.

English draft:

```md
## Features

| Feature | What it means |
| --- | --- |
| Menu bar scratchpad | Keep a quick note one click away without opening a full notes app. |
| Floating note window | Drag it out from the menu bar, move it around, resize it, or pin it above other windows. |
| Markdown-friendly editing | Write headings, lists, task checkboxes, links, code blocks, and formulas with lightweight inline styling. |
| Local Markdown file | Your draft is saved as a plain `note.md` file on your Mac. |
| Native macOS feel | A small accessory app with a translucent floating panel and status icon states. |
```

Chinese draft:

```md
## 功能

| 功能 | 说明 |
| --- | --- |
| 菜单栏草稿纸 | 常驻菜单栏，一次点击就能开始记录，不需要打开完整笔记应用。 |
| 浮动草稿窗 | 可以从菜单栏拖出、移动、调整大小，也可以固定在其他窗口上方。 |
| Markdown 友好编辑 | 支持标题、列表、任务复选框、链接、代码块和公式的轻量内联样式。 |
| 本地 Markdown 文件 | 草稿以普通 `note.md` 文件保存在你的 Mac 上。 |
| 原生 macOS 体验 | 小型 accessory app，半透明浮动面板，并有状态栏图标状态。 |
```

Avoid claiming full Markdown rendering support. The app provides lightweight inline styling and editing support.

## Install

The only install path in the README is the packaged DMG from GitHub Releases.

English draft:

```md
## Install

1. Download the latest `.dmg` from GitHub Releases.
2. Open the DMG and drag DraftBar into Applications.
3. Launch DraftBar. It will appear in the macOS menu bar.
```

Chinese draft:

```md
## 安装

1. 从 GitHub Releases 下载最新 `.dmg`。
2. 打开 DMG，把 DraftBar 拖入 Applications。
3. 启动 DraftBar，它会出现在 macOS 菜单栏。
```

Do not include source build instructions.

## Usage

English draft:

```md
## Usage

- Click the menu bar icon to open your draft.
- Drag from the menu bar icon to place the floating note window.
- Use the pin button to keep the note above other windows.
- Right-click the menu bar icon to open the note file or quit DraftBar.
```

Chinese draft:

```md
## 使用

- 点击菜单栏图标打开草稿。
- 从菜单栏图标拖出浮动草稿窗，并放到顺手的位置。
- 使用 pin 按钮让草稿窗保持在其他窗口上方。
- 右键点击菜单栏图标，可以打开本地草稿文件或退出 DraftBar。
```

## Data And Privacy

English draft:

```md
## Data & Privacy

DraftBar stores your draft locally as a Markdown file:

`~/Library/Application Support/DraftBar/note.md`

There is no account, no cloud sync, and no tracking.
```

Chinese draft:

```md
## 数据与隐私

DraftBar 会把草稿作为 Markdown 文件保存在本地：

`~/Library/Application Support/DraftBar/note.md`

不需要账号，没有云同步，也没有追踪。
```

## Roadmap

Keep the roadmap short and user-facing.

English draft:

```md
## Roadmap

- Real demo assets for the README
- Release packaging polish, such as signing and notarization, if needed
- More editor polish around Markdown workflows
```

Chinese draft:

```md
## 路线图

- 为 README 补充真实截图和短 GIF
- 按需要完善签名、公证等 release 打包细节
- 继续打磨 Markdown 编辑体验
```

Only mention signed DMG releases if the release process is ready for signing and notarization.

## Contributing

Keep this lightweight. Do not add build instructions here.

English draft:

```md
## Contributing

Issues and suggestions are welcome. Please open an issue if DraftBar does not fit your workflow yet, or if you find a rough edge worth improving.
```

Chinese draft:

```md
## 参与贡献

欢迎通过 issue 反馈想法和问题。如果 DraftBar 还没有贴合你的工作流，或者你遇到了值得改进的细节，可以直接开 issue。
```

## License

Use a minimal MIT license section.

English:

```md
## License

MIT
```

Chinese:

```md
## 许可证

MIT
```

## Synchronization Rules

Keep `README.md` and `README.zh-CN.md` structurally synchronized.

Use the English README as the GitHub-facing primary entry and the Chinese README as a natural Chinese version, not a rigid literal translation. Future updates to demo assets, installation, feature wording, or roadmap content should update both files together.
