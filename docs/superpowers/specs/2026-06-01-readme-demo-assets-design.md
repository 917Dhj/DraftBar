# DraftBar README Demo Assets Design

Date: 2026-06-01

## Goal

Add two README demo assets that make DraftBar's core promise obvious: quick capture from the macOS menu bar without interrupting the user's workflow.

The assets should support the existing product-first README structure in both:

- `README.md`
- `README.zh-CN.md`

## Audience And Positioning

The target reader is an ordinary macOS user. The demo assets should show what DraftBar feels like to use, not how it is built.

The visual story is:

1. DraftBar is one click away in the menu bar.
2. A small floating note appears quickly.
3. The user captures a short thought.
4. The note stays local as `note.md`.

## Approved Asset Direction

Use a mixed approach:

- Static detail image: use a real app screenshot.
- Animated flow image: create a controlled design-rendered GIF that visually matches the real screenshot style.

This gives the README both credibility and control. The screenshot proves the real editor surface; the GIF explains the quick-capture workflow without depending on a noisy desktop recording.

## Asset 1: Static Editor Detail Image

Create:

- `assets/demo-editor-detail.png`

Source:

- `/Users/dinghongjing/Desktop/DraftBar1.png`

Source properties:

- PNG
- 842 x 980
- RGBA

Use this image as the static README detail asset. It is acceptable because it:

- Shows the real DraftBar window.
- Has no cursor.
- Has no personal information.
- Shows meaningful sample content.
- Demonstrates title styling, normal text, task checkboxes, inline code, and local-first messaging.

The visible sample content is:

```md
# DraftBar launch

Capture a thought, then get back to work.

- [x] Record quick demo
- [ ] Package the DMG
- [ ] Publish the release

`note.md` stays local.
```

Do not use the older empty screenshot state. Empty-state screenshots make the README feel unfinished.

## Asset 2: Animated Fast Capture GIF

Create:

- `assets/demo-fast-capture.gif`

Use `/Users/dinghongjing/Desktop/DraftBar2.png` only as a visual reference or ending-frame reference. Do not use it as a standalone README image.

The GIF should be design-rendered or composited, not a raw desktop recording. It should visually match the real screenshot style:

- Rounded floating DraftBar window.
- Light translucent background.
- Close button in the top-left.
- Pin button and character count in the top-right.
- Clean macOS-like menu bar context.
- No personal desktop content.

The GIF script:

1. Start on a clean macOS-like desktop/menu bar view with DraftBar visible in the menu bar.
2. Show a small `Click` label near the menu bar icon.
3. Open the DraftBar floating note.
4. Show a `Capture` label as text appears.
5. Type or reveal:

   ```md
   Draft release note:
   - [ ] Package DMG
   - [ ] Add demo
   ```

6. Show a short `Done` label.
7. End with `Back to work`, returning visual emphasis to the desktop/menu bar context.

Keep labels in English only:

- `Click`
- `Capture`
- `Done`
- `Back to work`

The GIF should feel like a product demo, not a tutorial. Labels must be short and non-distracting.

## README Placement

Place both assets in the existing `Demo` section, after the text paragraph and before `Features`.

English README structure:

```md
## Demo

Open DraftBar from the menu bar, capture a thought, then get back to what you were doing. You can also drag from the menu bar icon to place the note where it feels natural.

![DraftBar quick capture demo](assets/demo-fast-capture.gif)

![DraftBar editor detail](assets/demo-editor-detail.png)
```

Chinese README structure:

```md
## 演示

从菜单栏唤起 DraftBar，快速记下一段草稿，然后回到原来的工作。你也可以从菜单栏图标拖出草稿窗，把它放在更顺手的位置。

![DraftBar 快速捕获演示](assets/demo-fast-capture.gif)

![DraftBar 编辑器细节](assets/demo-editor-detail.png)
```

Use the same image files in both README files. Do not create separate English and Chinese visual assets.

## File Organization

Use a repository-root `assets/` directory:

```text
assets/
  demo-editor-detail.png
  demo-fast-capture.gif
```

Do not store README demo assets under `DraftBar/Assets.xcassets`; that directory is for app assets.

## Acceptance Criteria

- `assets/demo-editor-detail.png` exists and is based on `/Users/dinghongjing/Desktop/DraftBar1.png`.
- `assets/demo-fast-capture.gif` exists and follows the approved quick-capture script.
- Both README files reference both assets in their `Demo` sections.
- The Chinese and English READMEs remain structurally synchronized.
- The assets do not include personal desktop information.
- The GIF includes only the approved short English labels.
- No README source-build, development-build, or known-limitations content is added.
- The final repository state is committed without pushing unless separately requested.

## Non-Goals

- Do not create a full marketing hero redesign.
- Do not replace the current product-first README structure.
- Do not add a website, landing page, or separate docs site.
- Do not create localized image variants.
- Do not use the empty DraftBar screenshot as the main demo image.
