#!/usr/bin/env python3
"""Generate the notification inbox visual reference used for Flutter polish."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs/design_refs/2026-06-19-notification-inbox-reference.png"
FONT = "/System/Library/Fonts/AppleSDGothicNeo.ttc"

BG = "#0F0F0F"
CARD = "#1D1D1D"
CARD_SUB = "#292929"
DIVIDER = "#373737"
TEXT = "#F7F9FC"
SECONDARY = "#A6B0BD"
DISABLED = "#6E7784"
LIVE = "#FF4444"
ACCENT = "#2979FF"
POSITIVE = "#18C67A"
YELLOW = "#FFD600"


def font(size: int, weight: int = 0) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT, size=size, index=weight)


def rounded(draw: ImageDraw.ImageDraw, box, radius: int, fill, outline=None, width: int = 1) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def text(draw: ImageDraw.ImageDraw, xy, value: str, size: int, fill=TEXT, weight: int = 0) -> None:
    draw.text(xy, value, font=font(size, weight), fill=fill)


def centered(draw: ImageDraw.ImageDraw, box, value: str, size: int, fill=TEXT, weight: int = 0) -> None:
    fnt = font(size, weight)
    left, top, right, bottom = draw.textbbox((0, 0), value, font=fnt)
    width = right - left
    height = bottom - top
    x = box[0] + (box[2] - box[0] - width) / 2
    y = box[1] + (box[3] - box[1] - height) / 2 - 1
    draw.text((x, y), value, font=fnt, fill=fill)


def pill(draw, x, y, label, color, width=None) -> int:
    fnt = font(10, 0)
    bbox = draw.textbbox((0, 0), label, font=fnt)
    w = width or (bbox[2] - bbox[0] + 18)
    rounded(
        draw,
        (x, y, x + w, y + 22),
        11,
        fill=with_alpha(color, 0.18),
        outline=with_alpha(color, 0.52),
    )
    draw.text((x + 9, y + 4), label, font=fnt, fill=color)
    return w


def with_alpha(hex_color: str, alpha: float) -> tuple[int, int, int, int]:
    hex_color = hex_color.lstrip("#")
    base = BG.lstrip("#")
    red = int(hex_color[0:2], 16)
    green = int(hex_color[2:4], 16)
    blue = int(hex_color[4:6], 16)
    base_red = int(base[0:2], 16)
    base_green = int(base[2:4], 16)
    base_blue = int(base[4:6], 16)
    return (
        int((red * alpha) + (base_red * (1 - alpha))),
        int((green * alpha) + (base_green * (1 - alpha))),
        int((blue * alpha) + (base_blue * (1 - alpha))),
        255,
    )


def draw_icon_box(draw, x, y, color, glyph):
    rounded(draw, (x, y, x + 38, y + 38), 8, fill=with_alpha(color, 0.16), outline=with_alpha(color, 0.38))
    centered(draw, (x, y, x + 38, y + 38), glyph, 17, fill=color, weight=0)


def draw_metric(draw, x, y, label, value, color):
    rounded(draw, (x, y, x + 104, y + 54), 8, fill=CARD_SUB, outline=DIVIDER)
    text(draw, (x + 10, y + 8), label, 10, fill=color, weight=0)
    text(draw, (x + 10, y + 25), value, 17, fill=TEXT, weight=0)


def draw_entry(draw, y, icon_color, glyph, title, body, time_label, tags):
    draw_icon_box(draw, 30, y + 12, icon_color, glyph)
    text(draw, (80, y + 11), title, 15, fill=TEXT, weight=0)
    text(draw, (325, y + 13), time_label, 11, fill=DISABLED, weight=0)
    text(draw, (80, y + 35), body, 11, fill=SECONDARY, weight=0)
    tag_x = 80
    for label, color in tags:
        tag_x += pill(draw, tag_x, y + 59, label, color) + 6


def main() -> None:
    image = Image.new("RGBA", (390, 844), BG)
    draw = ImageDraw.Draw(image)

    text(draw, (24, 20), "9:41", 16, fill=TEXT, weight=0)
    text(draw, (326, 20), "100", 13, fill=TEXT, weight=0)
    text(draw, (16, 61), "‹", 32, fill=TEXT, weight=0)
    text(draw, (58, 67), "푸시 알림", 11, fill=DISABLED, weight=0)
    text(draw, (58, 84), "알림함", 24, fill=TEXT, weight=0)
    rounded(draw, (295, 72, 366, 106), 8, fill=CARD_SUB, outline=DIVIDER)
    centered(draw, (295, 72, 366, 106), "모두 읽음", 12, fill=SECONDARY, weight=0)

    rounded(draw, (16, 124, 374, 247), 8, fill=CARD, outline=DIVIDER)
    draw_icon_box(draw, 30, 138, LIVE, "!")
    text(draw, (84, 139), "오늘 놓치지 않은 신호", 16, fill=TEXT, weight=0)
    text(draw, (84, 163), "3개 수신 · 2개 안 읽음", 12, fill=SECONDARY, weight=0)
    draw_metric(draw, 30, 187, "최근", "3", LIVE)
    draw_metric(draw, 143, 187, "안 읽음", "2", ACCENT)
    draw_metric(draw, 256, 187, "바로", "7", POSITIVE)

    filters = [("전체", True), ("안 읽음", False), ("경기", False), ("브리프", False)]
    x = 16
    for label, selected in filters:
        w = 58 if label != "안 읽음" else 74
        fill = TEXT if selected else CARD
        outline = TEXT if selected else DIVIDER
        rounded(draw, (x, 263, x + w, 299), 8, fill=fill, outline=outline)
        centered(draw, (x, 263, x + w, 299), label, 12, fill=BG if selected else SECONDARY, weight=0)
        x += w + 8

    rounded(draw, (16, 313, 374, 572), 8, fill=CARD, outline=DIVIDER)
    draw_entry(
        draw,
        313,
        LIVE,
        "R",
        "득점 장면",
        "7회말 문보경 우전 적시타 · 현재 4:3",
        "20:12",
        [("득점", LIVE), ("새 알림", LIVE), ("바로 열기", ACCENT)],
    )
    draw.line((32, 404, 358, 404), fill=CARD_SUB, width=1)
    draw_entry(
        draw,
        405,
        LIVE,
        "H",
        "홈런",
        "오스틴 좌월 홈런 · 잠실 경기 흐름 변화",
        "19:48",
        [("홈런", LIVE), ("바로 열기", ACCENT)],
    )
    draw.line((32, 496, 358, 496), fill=CARD_SUB, width=1)
    draw_entry(
        draw,
        497,
        ACCENT,
        "B",
        "월요일 야구 체크",
        "이번 주 KBO 일정과 기록 흐름을 확인하세요",
        "09:00",
        [("야구 브리프", ACCENT)],
    )

    text(draw, (16, 595), "받을 준비된 신호", 14, fill=SECONDARY, weight=0)
    text(draw, (334, 595), "설정 ›", 12, fill=SECONDARY, weight=0)
    rounded(draw, (16, 621, 374, 785), 8, fill=CARD, outline=DIVIDER)
    rows = [
        ("경기 시작", "플레이볼과 시작 임박 알림", LIVE, "바로"),
        ("득점", "점수 변화 즉시 알림", LIVE, "바로"),
        ("경기 종료", "최종 결과 확인", POSITIVE, "요약"),
        ("이닝 교대", "따라가기 화면 갱신", ACCENT, "따라가기"),
    ]
    y = 621
    for index, (title, sub, color, mode) in enumerate(rows):
        text(draw, (32, y + 14), "●", 13, fill=color, weight=0)
        text(draw, (58, y + 12), title, 15, fill=TEXT, weight=0)
        text(draw, (58, y + 35), sub, 11, fill=DISABLED, weight=0)
        pill(draw, 313, y + 20, mode, color, width=45 if mode != "따라가기" else 61)
        y += 41
        if index != len(rows) - 1:
            draw.line((32, y, 358, y), fill=CARD_SUB, width=1)

    image.convert("RGB").save(OUT, quality=95)
    print(OUT)


if __name__ == "__main__":
    main()
