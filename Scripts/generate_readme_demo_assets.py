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

SOURCE_SIZE = (842, 980)
FRAME_COUNT = 70
MENU_ICON_CENTER = (742, MENU_BAR_HEIGHT // 2)
NOTE_TEXT_LINES = (
    "Draft release note:",
    "- [ ] Package DMG",
    "- [ ] Add demo",
)


def validate_source_image(path: Path) -> None:
    if not path.exists():
        raise FileNotFoundError(f"Missing source image: {path}")

    with Image.open(path) as image:
        if image.format != "PNG" or image.size != SOURCE_SIZE:
            raise ValueError(
                f"{path} must be a PNG image with size {SOURCE_SIZE}, got "
                f"{image.format} {image.size}"
            )


def load_font(size: int, *, bold: bool = False, mono: bool = False) -> ImageFont.ImageFont:
    font_paths = []
    if mono:
        font_paths.extend(
            [
                "/System/Library/Fonts/Menlo.ttc",
                "/System/Library/Fonts/SFNSMono.ttf",
            ]
        )
    elif bold:
        font_paths.extend(
            [
                "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
                "/Library/Fonts/Arial Bold.ttf",
                "/System/Library/Fonts/SFNS.ttf",
            ]
        )
    else:
        font_paths.extend(
            [
                "/System/Library/Fonts/SFNS.ttf",
                "/System/Library/Fonts/Supplemental/Arial.ttf",
                "/Library/Fonts/Arial.ttf",
            ]
        )

    for font_path in font_paths:
        path = Path(font_path)
        if not path.exists():
            continue
        try:
            return ImageFont.truetype(str(path), size=size)
        except OSError:
            continue

    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


LABEL_FONT = load_font(18, bold=True)
NOTE_FONT = load_font(22, mono=True)
DONE_FONT = load_font(15, bold=True)


def ease(value: float) -> float:
    value = min(max(value, 0.0), 1.0)
    return value * value * (3.0 - 2.0 * value)


def lerp(start: float, end: float, amount: float) -> float:
    return start + (end - start) * amount


def lerp_point(start: tuple[float, float], end: tuple[float, float], amount: float) -> tuple[int, int]:
    return (round(lerp(start[0], end[0], amount)), round(lerp(start[1], end[1], amount)))


def make_desktop_base() -> Image.Image:
    width, height = CANVAS_SIZE
    image = Image.new("RGBA", CANVAS_SIZE)
    draw = ImageDraw.Draw(image)

    for y in range(height):
        amount = y / (height - 1)
        red = round(222 - 38 * amount)
        green = round(232 - 28 * amount)
        blue = round(241 - 12 * amount)
        draw.line((0, y, width, y), fill=(red, green, blue, 255))

    draw.ellipse((-210, 74, 460, 710), fill=(239, 220, 200, 90))
    draw.ellipse((290, -160, 1040, 390), fill=(202, 227, 232, 135))
    draw.ellipse((56, 278, 760, 820), fill=(230, 238, 224, 120))

    draw.rounded_rectangle((64, 86, 394, 278), radius=18, fill=(255, 255, 255, 92))
    draw.rounded_rectangle((90, 118, 348, 134), radius=8, fill=(255, 255, 255, 120))
    draw.rounded_rectangle((90, 154, 298, 168), radius=7, fill=(255, 255, 255, 100))
    draw.rounded_rectangle((90, 190, 332, 204), radius=7, fill=(255, 255, 255, 100))

    draw.rounded_rectangle((332, 386, 628, 507), radius=24, fill=(255, 255, 255, 76))
    for index in range(7):
        x = 372 + index * 34
        draw.rounded_rectangle((x, 418, x + 24, 442), radius=7, fill=(255, 255, 255, 142))

    draw.rectangle((0, 0, width, MENU_BAR_HEIGHT), fill=(252, 252, 252, 232))
    draw.line((0, MENU_BAR_HEIGHT, width, MENU_BAR_HEIGHT), fill=(180, 188, 196, 86))
    draw.ellipse((17, 10, 29, 22), fill=(35, 38, 42, 210))
    draw.rounded_rectangle((MENU_ICON_CENTER[0] - 8, 10, MENU_ICON_CENTER[0] + 8, 24), radius=5, fill=(31, 33, 36, 225))
    draw.line((MENU_ICON_CENTER[0] - 4, 17, MENU_ICON_CENTER[0] + 4, 17), fill=(255, 255, 255, 235), width=2)
    draw.arc((802, 10, 820, 28), 210, 330, fill=(42, 45, 49, 190), width=2)
    draw.arc((826, 10, 850, 28), 215, 325, fill=(42, 45, 49, 190), width=2)
    draw.rounded_rectangle((872, 12, 902, 22), radius=5, outline=(42, 45, 49, 175), width=2)
    draw.rectangle((902, 15, 906, 19), fill=(42, 45, 49, 175))

    return image


def scaled_alpha(layer: Image.Image, opacity: float) -> Image.Image:
    opacity = min(max(opacity, 0.0), 1.0)
    if opacity >= 0.999:
        return layer

    result = layer.copy()
    alpha = result.getchannel("A").point(lambda pixel: round(pixel * opacity))
    result.putalpha(alpha)
    return result


def draw_note_panel(target: Image.Image, frame_index: int, progress: float) -> None:
    if progress <= 0.0:
        return

    x, y = NOTE_POSITION
    width, height = NOTE_SIZE
    y = round(y + (1.0 - progress) * 22)
    rect = (x, y, x + width, y + height)
    layer = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))

    shadow = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle((x + 7, y + 12, x + width + 7, y + height + 12), radius=24, fill=(0, 0, 0, 72))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    layer.alpha_composite(shadow)

    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle(rect, radius=22, fill=(252, 252, 249, 248), outline=(184, 190, 194, 156), width=1)
    draw.rounded_rectangle((x + 1, y + 1, x + width - 1, y + 54), radius=21, fill=(245, 245, 242, 245))
    draw.rectangle((x + 1, y + 34, x + width - 1, y + 56), fill=(245, 245, 242, 245))
    draw.line((x + 1, y + 56, x + width - 1, y + 56), fill=(203, 207, 210, 148))

    for index, color in enumerate(((255, 95, 87), (255, 189, 46), (40, 201, 64))):
        cx = x + 22 + index * 19
        draw.ellipse((cx - 5, y + 22 - 5, cx + 5, y + 22 + 5), fill=color + (230,))

    done_rect = (x + width - 76, y + 14, x + width - 24, y + 40)
    done_fill = (36, 120, 242, 245) if 47 <= frame_index <= 59 else (255, 255, 255, 210)
    done_outline = (30, 102, 220, 245) if 47 <= frame_index <= 59 else (196, 201, 206, 210)
    done_text = (255, 255, 255, 255) if 47 <= frame_index <= 59 else (38, 92, 160, 235)
    draw.rounded_rectangle(done_rect, radius=13, fill=done_fill, outline=done_outline, width=1)
    draw.text((done_rect[0] + 10, done_rect[1] + 4), "Done", font=DONE_FONT, fill=done_text)

    text_x = x + 30
    text_y = y + 92
    line_gap = 44
    for line_index, line in enumerate(NOTE_TEXT_LINES):
        draw.text((text_x, text_y + line_index * line_gap), line, font=NOTE_FONT, fill=(26, 28, 31, 255))

    caret_alpha = 255 if (frame_index // 5) % 2 == 0 else 80
    caret_x = text_x + 190
    caret_y = text_y + line_gap * 2 + 5
    draw.line((caret_x, caret_y, caret_x, caret_y + 28), fill=(38, 107, 214, caret_alpha), width=2)

    target.alpha_composite(scaled_alpha(layer, progress))


def panel_progress(frame_index: int) -> float:
    if frame_index < 12:
        return 0.0
    if frame_index < 24:
        return ease((frame_index - 12) / 11)
    if frame_index < 57:
        return 1.0
    return 1.0 - ease((frame_index - 57) / 12)


def current_label(frame_index: int) -> str:
    if frame_index < 16:
        return "Click"
    if frame_index < 47:
        return "Capture"
    if frame_index < 59:
        return "Done"
    return "Back to work"


def cursor_position(frame_index: int) -> tuple[int, int]:
    if frame_index < 16:
        return lerp_point((388, 312), MENU_ICON_CENTER, ease(frame_index / 15))
    if frame_index < 30:
        return lerp_point(MENU_ICON_CENTER, (634, 164), ease((frame_index - 16) / 13))
    if frame_index < 47:
        amount = (frame_index - 30) / 16
        drift = math.sin(amount * math.pi * 2.0)
        return (round(642 + amount * 78), round(174 + amount * 58 + drift * 5))
    if frame_index < 59:
        return lerp_point((706, 217), (856, 88), ease((frame_index - 47) / 11))
    return lerp_point((856, 88), (426, 330), ease((frame_index - 59) / 10))


def draw_menu_icon_highlight(target: Image.Image, frame_index: int) -> None:
    if not (8 <= frame_index <= 20):
        return

    draw = ImageDraw.Draw(target)
    pulse = math.sin((frame_index - 8) / 12 * math.pi)
    radius = round(14 + pulse * 9)
    alpha = round(122 - pulse * 52)
    cx, cy = MENU_ICON_CENTER
    draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), outline=(31, 95, 217, alpha), width=3)


def draw_click_ripple(target: Image.Image, position: tuple[int, int], frame_index: int, start_frame: int) -> None:
    age = frame_index - start_frame
    if age < 0 or age > 8:
        return

    draw = ImageDraw.Draw(target)
    radius = 8 + age * 4
    alpha = max(0, 170 - age * 19)
    x, y = position
    draw.ellipse((x - radius, y - radius, x + radius, y + radius), outline=(27, 103, 224, alpha), width=3)


def draw_label(target: Image.Image, label: str, cursor: tuple[int, int]) -> None:
    draw = ImageDraw.Draw(target)
    text_box = draw.textbbox((0, 0), label, font=LABEL_FONT)
    text_width = text_box[2] - text_box[0]
    text_height = text_box[3] - text_box[1]
    x = min(cursor[0] + 24, CANVAS_SIZE[0] - text_width - 36)
    y = min(max(cursor[1] + 20, MENU_BAR_HEIGHT + 8), CANVAS_SIZE[1] - text_height - 28)
    rect = (x, y, x + text_width + 24, y + text_height + 18)
    draw.rounded_rectangle(rect, radius=14, fill=(22, 27, 35, 232))
    draw.text((x + 12, y + 8), label, font=LABEL_FONT, fill=(255, 255, 255, 255))


def draw_cursor(target: Image.Image, position: tuple[int, int]) -> None:
    x, y = position
    draw = ImageDraw.Draw(target)
    outline = [
        (x, y),
        (x + 2, y + 31),
        (x + 10, y + 23),
        (x + 16, y + 37),
        (x + 23, y + 34),
        (x + 17, y + 20),
        (x + 29, y + 20),
    ]
    fill = [
        (x + 2, y + 3),
        (x + 4, y + 27),
        (x + 10, y + 18),
        (x + 17, y + 32),
        (x + 19, y + 31),
        (x + 13, y + 17),
        (x + 24, y + 18),
    ]
    draw.polygon(outline, fill=(36, 39, 43, 255))
    draw.polygon(fill, fill=(255, 255, 255, 255))


def make_gif_frames() -> list[Image.Image]:
    base = make_desktop_base()
    frames = []
    for frame_index in range(FRAME_COUNT):
        frame = base.copy()
        cursor = cursor_position(frame_index)
        draw_menu_icon_highlight(frame, frame_index)
        draw_note_panel(frame, frame_index, panel_progress(frame_index))
        draw_click_ripple(frame, MENU_ICON_CENTER, frame_index, 12)
        draw_click_ripple(frame, (856, 88), frame_index, 53)
        draw_label(frame, current_label(frame_index), cursor)
        draw_cursor(frame, cursor)
        frames.append(frame.convert("RGB"))
    return frames


def main() -> None:
    validate_source_image(EDITOR_SOURCE)
    validate_source_image(FLOW_REFERENCE_SOURCE)
    ASSETS_DIR.mkdir(exist_ok=True)

    shutil.copyfile(EDITOR_SOURCE, EDITOR_OUTPUT)

    frames = make_gif_frames()
    frames[0].save(
        GIF_OUTPUT,
        save_all=True,
        append_images=frames[1:],
        duration=FRAME_DURATION_MS,
        loop=0,
        optimize=False,
        disposal=2,
    )

    print("Wrote assets/demo-editor-detail.png")
    print("Wrote assets/demo-fast-capture.gif")


if __name__ == "__main__":
    main()
