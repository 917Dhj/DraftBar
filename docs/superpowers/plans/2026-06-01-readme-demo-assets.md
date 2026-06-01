# README Demo Assets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the approved DraftBar README demo PNG and GIF assets, then reference them from both English and Chinese READMEs.

**Architecture:** Keep README demo binaries in a root-level `assets/` directory and keep app runtime assets untouched. Add one deterministic Python/Pillow script under `Scripts/` to copy the approved static screenshot and generate the quick-capture GIF from a scripted visual scene. Update `README.md` and `README.zh-CN.md` in the existing `Demo` sections using the same asset files.

**Tech Stack:** GitHub Flavored Markdown, PNG, GIF, `/opt/anaconda3/bin/python3`, Pillow 12.1.1.

---

## Assumptions

- Static screenshot source exists at `/Users/dinghongjing/Desktop/DraftBar1.png`.
- Ending-frame/reference screenshot exists at `/Users/dinghongjing/Desktop/DraftBar2.png`.
- Both desktop source images are PNG files with dimensions `842 x 980`.
- `/opt/anaconda3/bin/python3` can import Pillow.
- The implementation happens on `main`, matching the user's earlier approval for this README work.
- No push is performed unless separately requested.

## Files

- Create: `Scripts/generate_readme_demo_assets.py`
- Create: `assets/demo-editor-detail.png`
- Create: `assets/demo-fast-capture.gif`
- Modify: `README.md`
- Modify: `README.zh-CN.md`
- Reference only: `docs/superpowers/specs/2026-06-01-readme-demo-assets-design.md`

Do not modify `DraftBar/Assets.xcassets`, app source files, Xcode project files, `LICENSE`, or existing release metadata.

## Task 1: Generate Demo Assets

**Files:**
- Create: `Scripts/generate_readme_demo_assets.py`
- Create: `assets/demo-editor-detail.png`
- Create: `assets/demo-fast-capture.gif`

- [ ] **Step 1: Verify source screenshots and Pillow**

Run:

```bash
file /Users/dinghongjing/Desktop/DraftBar1.png /Users/dinghongjing/Desktop/DraftBar2.png
/opt/anaconda3/bin/python3 -c "import PIL; print(PIL.__version__)"
```

Expected output includes:

```text
/Users/dinghongjing/Desktop/DraftBar1.png: PNG image data, 842 x 980, 8-bit/color RGBA, non-interlaced
/Users/dinghongjing/Desktop/DraftBar2.png: PNG image data, 842 x 980, 8-bit/color RGBA, non-interlaced
12.1.1
```

- [ ] **Step 2: Add the asset generation script**

Create `Scripts/generate_readme_demo_assets.py` with this complete content:

```python
#!/usr/bin/env python3
from __future__ import annotations

import math
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
ASSETS_DIR = ROOT / "assets"
EDITOR_SOURCE = Path.home() / "Desktop" / "DraftBar1.png"
FLOW_REFERENCE_SOURCE = Path.home() / "Desktop" / "DraftBar2.png"
EDITOR_OUTPUT = ASSETS_DIR / "demo-editor-detail.png"
GIF_OUTPUT = ASSETS_DIR / "demo-fast-capture.gif"

CANVAS_SIZE = (960, 540)
MENU_BAR_HEIGHT = 34
NOTE_SIZE = (390, 454)
NOTE_POSITION = (520, 62)
FRAME_DURATION_MS = 70

APP_TEXT = [
    ("Draft release note:", "body"),
    ("- [ ] Package DMG", "task"),
    ("- [ ] Add demo", "task"),
]


def load_font(size: int, weight: str = "regular") -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = []
    if weight == "bold":
        candidates.extend(
            [
                "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
                "/System/Library/Fonts/Supplemental/Helvetica Bold.ttf",
            ]
        )
    candidates.extend(
        [
            "/System/Library/Fonts/Supplemental/Arial.ttf",
            "/System/Library/Fonts/Supplemental/Helvetica.ttf",
            "/System/Library/Fonts/Helvetica.ttc",
        ]
    )

    for candidate in candidates:
        try:
            return ImageFont.truetype(candidate, size)
        except OSError:
            continue
    return ImageFont.load_default()


FONT_MENU = load_font(14)
FONT_MENU_BOLD = load_font(14, "bold")
FONT_LABEL = load_font(16, "bold")
FONT_BODY = load_font(25)
FONT_TASK = load_font(25)
FONT_COUNTER = load_font(18, "bold")


def ease_out_cubic(value: float) -> float:
    value = max(0.0, min(1.0, value))
    return 1 - pow(1 - value, 3)


def ensure_sources() -> None:
    for source in (EDITOR_SOURCE, FLOW_REFERENCE_SOURCE):
        if not source.exists():
            raise FileNotFoundError(f"Missing source image: {source}")

        with Image.open(source) as image:
            if image.size != (842, 980):
                raise ValueError(f"{source} has size {image.size}, expected (842, 980)")


def copy_editor_detail() -> None:
    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(EDITOR_SOURCE, EDITOR_OUTPUT)


def draw_desktop(draw: ImageDraw.ImageDraw, width: int, height: int) -> None:
    for y in range(height):
        t = y / max(height - 1, 1)
        r = int(235 + 12 * t)
        g = int(232 + 10 * t)
        b = int(226 + 12 * t)
        draw.line([(0, y), (width, y)], fill=(r, g, b))

    draw.rounded_rectangle((20, 62, 470, 470), radius=22, fill=(255, 255, 255, 130))
    draw.rounded_rectangle((38, 86, 452, 126), radius=12, fill=(255, 255, 255, 155))
    draw.rounded_rectangle((38, 146, 452, 330), radius=16, fill=(255, 255, 255, 115))
    draw.text((58, 96), "Release notes draft", fill=(80, 80, 80), font=FONT_MENU_BOLD)
    draw.text((58, 168), "Keep the main workspace open.", fill=(110, 110, 110), font=FONT_MENU)
    draw.text((58, 196), "Use DraftBar for quick capture.", fill=(110, 110, 110), font=FONT_MENU)

    draw.rectangle((0, 0, width, MENU_BAR_HEIGHT), fill=(248, 247, 244, 230))
    draw.text((16, 9), "Finder", fill=(50, 50, 50), font=FONT_MENU_BOLD)
    draw.text((70, 9), "File", fill=(70, 70, 70), font=FONT_MENU)
    draw.text((108, 9), "Edit", fill=(70, 70, 70), font=FONT_MENU)
    draw.text((148, 9), "View", fill=(70, 70, 70), font=FONT_MENU)
    draw.text((194, 9), "Window", fill=(70, 70, 70), font=FONT_MENU)

    draw.rounded_rectangle((796, 6, 822, 28), radius=6, fill=(235, 232, 224))
    draw.rectangle((806, 12, 813, 22), fill=(35, 35, 35))
    draw.ellipse((804, 10, 815, 15), fill=(35, 35, 35))
    draw.text((834, 9), "Wi-Fi", fill=(80, 80, 80), font=FONT_MENU)
    draw.text((888, 9), "10:24", fill=(80, 80, 80), font=FONT_MENU)


def draw_label(draw: ImageDraw.ImageDraw, text: str, center: tuple[int, int]) -> None:
    bbox = draw.textbbox((0, 0), text, font=FONT_LABEL)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    padding_x = 13
    padding_y = 8
    left = center[0] - text_width // 2 - padding_x
    top = center[1] - text_height // 2 - padding_y
    right = center[0] + text_width // 2 + padding_x
    bottom = center[1] + text_height // 2 + padding_y
    draw.rounded_rectangle((left, top, right, bottom), radius=15, fill=(34, 34, 34, 225))
    draw.text((center[0] - text_width // 2, center[1] - text_height // 2 - 1), text, fill=(255, 255, 255), font=FONT_LABEL)


def draw_checkbox(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int]) -> None:
    draw.rounded_rectangle(box, radius=4, outline=(130, 130, 130), width=3)


def draw_note_panel(progress: float, typed_chars: int) -> Image.Image:
    progress = ease_out_cubic(progress)
    base = Image.new("RGBA", NOTE_SIZE, (0, 0, 0, 0))
    draw = ImageDraw.Draw(base)

    shadow = Image.new("RGBA", NOTE_SIZE, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle((10, 10, NOTE_SIZE[0] - 10, NOTE_SIZE[1] - 10), radius=34, fill=(0, 0, 0, 45))
    shadow = shadow.filter(ImageFilter.GaussianBlur(10))
    base.alpha_composite(shadow)

    draw.rounded_rectangle((0, 0, NOTE_SIZE[0] - 1, NOTE_SIZE[1] - 1), radius=34, fill=(251, 248, 242), outline=(255, 255, 255, 170), width=2)

    draw.ellipse((22, 22, 74, 74), fill=(246, 244, 238), outline=(255, 255, 255), width=2)
    draw.line((40, 40, 56, 56), fill=(128, 128, 128), width=4)
    draw.line((56, 40, 40, 56), fill=(128, 128, 128), width=4)
    draw.text((292, 36), f"{min(52, typed_chars)} 字", fill=(118, 118, 118), font=FONT_COUNTER)
    draw.ellipse((342, 22, 394, 74), fill=(246, 244, 238), outline=(255, 255, 255), width=2)
    draw.rectangle((365, 39, 372, 56), fill=(35, 35, 35))
    draw.ellipse((362, 34, 375, 42), fill=(35, 35, 35))

    visible_text = "\n".join(line for line, _ in APP_TEXT)
    visible_text = visible_text[:typed_chars]
    y = 112
    cursor = 0

    for full_line, kind in APP_TEXT:
        line_chars = max(0, min(len(full_line), typed_chars - cursor))
        line = full_line[:line_chars]
        cursor += len(full_line) + 1
        if not line and typed_chars < cursor:
            break

        if kind == "task":
            box = (56, y + 5, 76, y + 25)
            draw_checkbox(draw, box)
            if line.startswith("- [ ] "):
                text = line[6:]
            else:
                text = line
            draw.text((90, y), text, fill=(36, 36, 36), font=FONT_TASK)
        else:
            draw.text((56, y), line, fill=(36, 36, 36), font=FONT_BODY)
        y += 42

    alpha = int(255 * progress)
    if alpha < 255:
        base.putalpha(Image.eval(base.getchannel("A"), lambda a: int(a * alpha / 255)))
    return base


def compose_frame(index: int, total: int) -> Image.Image:
    frame = Image.new("RGB", CANVAS_SIZE, (242, 238, 232))
    rgba = frame.convert("RGBA")
    draw = ImageDraw.Draw(rgba)
    draw_desktop(draw, *CANVAS_SIZE)

    note_progress = 0.0
    typed_chars = 0
    label = ""
    label_center = (806, 56)

    if index < 10:
        label = "Click"
        note_progress = 0.0
    elif index < 22:
        note_progress = (index - 10) / 12
        label = "Capture"
        label_center = (660, 96)
    elif index < 50:
        note_progress = 1.0
        full_text = "\n".join(line for line, _ in APP_TEXT)
        typed_chars = math.floor(len(full_text) * ((index - 22) / 28))
        label = "Capture"
        label_center = (660, 96)
    elif index < 58:
        note_progress = 1.0
        typed_chars = len("\n".join(line for line, _ in APP_TEXT))
        label = "Done"
        label_center = (704, 96)
    else:
        note_progress = 1.0
        typed_chars = len("\n".join(line for line, _ in APP_TEXT))
        label = "Back to work"
        label_center = (314, 365)

    if note_progress > 0:
        panel = draw_note_panel(note_progress, typed_chars)
        eased = ease_out_cubic(note_progress)
        scale = 0.18 + 0.82 * eased
        width = max(1, int(NOTE_SIZE[0] * scale))
        height = max(1, int(NOTE_SIZE[1] * scale))
        panel = panel.resize((width, height), Image.Resampling.LANCZOS)
        x = int(NOTE_POSITION[0] + (NOTE_SIZE[0] - width) * 0.95)
        y = int(NOTE_POSITION[1] + (NOTE_SIZE[1] - height) * 0.02)
        rgba.alpha_composite(panel, (x, y))

    if label:
        draw_label(draw, label, label_center)

    return rgba.convert("P", palette=Image.Palette.ADAPTIVE, colors=256)


def generate_fast_capture_gif() -> None:
    total_frames = 70
    frames = [compose_frame(i, total_frames) for i in range(total_frames)]
    durations = [FRAME_DURATION_MS] * total_frames
    durations[-1] = 900
    frames[0].save(
        GIF_OUTPUT,
        save_all=True,
        append_images=frames[1:],
        duration=durations,
        loop=0,
        optimize=False,
        disposal=2,
    )


def main() -> None:
    ensure_sources()
    copy_editor_detail()
    generate_fast_capture_gif()
    print(f"Wrote {EDITOR_OUTPUT.relative_to(ROOT)}")
    print(f"Wrote {GIF_OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Run the generation script**

Run:

```bash
/opt/anaconda3/bin/python3 Scripts/generate_readme_demo_assets.py
```

Expected output:

```text
Wrote assets/demo-editor-detail.png
Wrote assets/demo-fast-capture.gif
```

- [ ] **Step 4: Verify generated assets**

Run:

```bash
file assets/demo-editor-detail.png assets/demo-fast-capture.gif
```

Expected output includes:

```text
assets/demo-editor-detail.png: PNG image data, 842 x 980, 8-bit/color RGBA, non-interlaced
assets/demo-fast-capture.gif: GIF image data
```

Run:

```bash
/opt/anaconda3/bin/python3 - <<'PY'
from pathlib import Path
from PIL import Image

checks = {
    "assets/demo-editor-detail.png": (842, 980),
    "assets/demo-fast-capture.gif": (960, 540),
}

for path, expected_size in checks.items():
    image = Image.open(path)
    print(path, image.size, getattr(image, "n_frames", 1))
    assert image.size == expected_size
    if path.endswith(".gif"):
        assert image.n_frames == 70
PY
```

Expected output:

```text
assets/demo-editor-detail.png (842, 980) 1
assets/demo-fast-capture.gif (960, 540) 70
```

- [ ] **Step 5: Commit generated assets and script**

Run:

```bash
git add Scripts/generate_readme_demo_assets.py assets/demo-editor-detail.png assets/demo-fast-capture.gif
git commit -m "docs: add readme demo assets"
```

Expected: commit succeeds and includes exactly the script plus two asset files.

## Task 2: Insert Assets Into Both READMEs

**Files:**
- Modify: `README.md`
- Modify: `README.zh-CN.md`

- [ ] **Step 1: Update the English README Demo section**

In `README.md`, replace:

```md
## Demo

Open DraftBar from the menu bar, capture a thought, then get back to what you were doing. You can also drag from the menu bar icon to place the note where it feels natural.

## Features
```

with:

```md
## Demo

Open DraftBar from the menu bar, capture a thought, then get back to what you were doing. You can also drag from the menu bar icon to place the note where it feels natural.

![DraftBar quick capture demo](assets/demo-fast-capture.gif)

![DraftBar editor detail](assets/demo-editor-detail.png)

## Features
```

- [ ] **Step 2: Update the Chinese README Demo section**

In `README.zh-CN.md`, replace:

```md
## 演示

从菜单栏唤起 DraftBar，快速记下一段草稿，然后回到原来的工作。你也可以从菜单栏图标拖出草稿窗，把它放在更顺手的位置。

## 功能
```

with:

```md
## 演示

从菜单栏唤起 DraftBar，快速记下一段草稿，然后回到原来的工作。你也可以从菜单栏图标拖出草稿窗，把它放在更顺手的位置。

![DraftBar 快速捕获演示](assets/demo-fast-capture.gif)

![DraftBar 编辑器细节](assets/demo-editor-detail.png)

## 功能
```

- [ ] **Step 3: Verify README asset references**

Run:

```bash
rg -n "demo-fast-capture.gif|demo-editor-detail.png" README.md README.zh-CN.md
```

Expected output:

```text
README.md:21:![DraftBar quick capture demo](assets/demo-fast-capture.gif)
README.md:23:![DraftBar editor detail](assets/demo-editor-detail.png)
README.zh-CN.md:21:![DraftBar 快速捕获演示](assets/demo-fast-capture.gif)
README.zh-CN.md:23:![DraftBar 编辑器细节](assets/demo-editor-detail.png)
```

- [ ] **Step 4: Verify README structure remains synchronized**

Run:

```bash
rg -n "^## Demo|^## Features|^## 演示|^## 功能" README.md README.zh-CN.md
```

Expected output:

```text
README.md:17:## Demo
README.md:25:## Features
README.zh-CN.md:17:## 演示
README.zh-CN.md:25:## 功能
```

- [ ] **Step 5: Verify forbidden README content was not added**

Run:

```bash
rg -n "Bui[l]d from source|Develo[p]ment build|Known Limitat[i]ons|coming s[o]on|T[O]DO|T[B]D|源码构[建]|已知限[制]" README.md README.zh-CN.md
```

Expected: command exits with status `1` and prints nothing.

- [ ] **Step 6: Commit README updates**

Run:

```bash
git add README.md README.zh-CN.md
git commit -m "docs: show readme demo assets"
```

Expected: commit succeeds and includes exactly `README.md` and `README.zh-CN.md`.

## Task 3: Final Verification

**Files:**
- Verify: `Scripts/generate_readme_demo_assets.py`
- Verify: `assets/demo-editor-detail.png`
- Verify: `assets/demo-fast-capture.gif`
- Verify: `README.md`
- Verify: `README.zh-CN.md`

- [ ] **Step 1: Regenerate assets to verify reproducibility**

Run:

```bash
/opt/anaconda3/bin/python3 Scripts/generate_readme_demo_assets.py
git diff -- assets/demo-editor-detail.png assets/demo-fast-capture.gif
```

Expected: the script prints both `Wrote ...` lines and `git diff` prints nothing.

- [ ] **Step 2: Verify Markdown whitespace**

Run:

```bash
git diff --check HEAD~2..HEAD
```

Expected: command exits with status `0` and prints nothing.

- [ ] **Step 3: Verify latest commits and clean status**

Run:

```bash
git log --oneline -3
git status --short --untracked-files=all --ignored=no
```

Expected:

- Recent commits include `docs: show readme demo assets` and `docs: add readme demo assets`.
- `git status` prints nothing.

- [ ] **Step 4: Final visual inspection**

Open or inspect:

```text
assets/demo-editor-detail.png
assets/demo-fast-capture.gif
```

Expected:

- The PNG matches the approved non-empty DraftBar screenshot from `/Users/dinghongjing/Desktop/DraftBar1.png`.
- The GIF shows the quick-capture flow with only these labels: `Click`, `Capture`, `Done`, `Back to work`.
- Neither asset contains personal desktop content.
