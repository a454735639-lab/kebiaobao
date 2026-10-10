#!/usr/bin/env python3
"""生成 iOS 18 dark / tinted 图标变体。

- dark: 深色底（#1B3A35 → #0E211E）+ 白色卡片保留
- tinted: 灰度版（系统会自己上色，只需提供亮度图）
"""
from PIL import Image, ImageDraw

SRC = "/var/minis/workspace/kebiaobao/Kebiaobao/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
OUT = "/var/minis/workspace/kebiaobao/Kebiaobao/Assets.xcassets/AppIcon.appiconset/"

S = 1024
ACC = (0x53, 0xB4, 0xA4)
DARK_TOP = (0x1B, 0x3A, 0x35)
DARK_BOT = (0x0C, 0x1C, 0x1A)


def base(top, bot):
    img = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(img, "RGBA")
    for y in range(S):
        t = y / (S - 1)
        d.line([(0, y), (S, y)],
               fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
    return img, d


def card(d, fill=(255, 255, 255, 255), acc=ACC):
    d.ellipse([-200, -160, 440, 480], fill=(255, 255, 255, 20))
    pad = 196
    d.rounded_rectangle([pad, pad, S - pad, S - pad], radius=92, fill=fill)
    cx, cy = S // 2, S // 2 + 6
    d.line([(cx - 118, cy + 4), (cx - 34, cy + 92)], fill=acc, width=34, joint="curve")
    d.line([(cx - 34, cy + 92), (cx + 122, cy - 78)], fill=acc, width=34, joint="curve")
    for x in (S // 2 - 84, S // 2, S // 2 + 84):
        d.ellipse([x - 21, S - pad - 112 - 21, x + 21, S - pad - 112 + 21], fill=acc)


# dark：深底 + 白卡（青绿对勾在深底卡片上更亮）
img, d = base(DARK_TOP, DARK_BOT)
card(d, fill=(255, 255, 255, 255), acc=(0x5F, 0xC9, 0xB8))
img.save(OUT + "AppIcon-Dark.png", "PNG")

# tinted：灰度（系统会叠色），用亮灰卡 + 深灰勾
img, d = base((0xC8, 0xC8, 0xC8), (0x8A, 0x8A, 0x8A))
card(d, fill=(255, 255, 255, 255), acc=(0x30, 0x30, 0x30))
img.convert("L").convert("RGB").save(OUT + "AppIcon-Tinted.png", "PNG")

print("ok")
