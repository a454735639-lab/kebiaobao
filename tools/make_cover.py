#!/usr/bin/env python3
"""生成课时宝 App 封面图（1080x1920 竖版海报 + 1024 方版）。"""
from PIL import Image, ImageDraw, ImageFont

ACC = (0x53, 0xB4, 0xA4)
DARK = (0x2F, 0x82, 0x76)
LIGHT = (0x7F, 0xD3, 0xC4)
WHITE = (255, 255, 255)
FONT = "/usr/share/fonts/noto/NotoSansCJK-Bold.ttc"
FONT_R = "/usr/share/fonts/noto/NotoSansCJK-Regular.ttc"


def f(path, size):
    return ImageFont.truetype(path, size)


def grad(size, top, bottom):
    img = Image.new("RGB", (1, size[1]))
    d = ImageDraw.Draw(img)
    for y in range(size[1]):
        t = y / max(1, size[1] - 1)
        d.point((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return img.resize(size, Image.BILINEAR)


def check(d, cx, cy, scale, color, width):
    d.line([(cx - 118 * scale, cy + 4 * scale), (cx - 34 * scale, cy + 92 * scale)],
           fill=color, width=int(width * scale), joint="curve")
    d.line([(cx - 34 * scale, cy + 92 * scale), (cx + 122 * scale, cy - 78 * scale)],
           fill=color, width=int(width * scale), joint="curve")


def center(d, y, text, font, fill):
    w = d.textbbox((0, 0), text, font=font)[2]
    d.text(((1080 - w) / 2, y), text, font=font, fill=fill)
    return w


# ---------- 竖版封面 1080x1920 ----------
W, H = 1080, 1920
img = grad((W, H), LIGHT, DARK)
d = ImageDraw.Draw(img, "RGBA")

# 背景装饰圆
d.ellipse([-260, -180, 520, 600], fill=(255, 255, 255, 22))
d.ellipse([700, 1420, 1420, 2140], fill=(255, 255, 255, 18))

# 白色圆角 App 图标
S = 400
ix, iy = (W - S) // 2, 300
d.rounded_rectangle([ix, iy, ix + S, iy + S], radius=92, fill=WHITE)
check(d, W // 2, iy + S // 2 + 6, 1.05, ACC, 34)
for i, x in enumerate((W // 2 - 84, W // 2, W // 2 + 84)):
    r = 21
    d.ellipse([x - r, iy + S - 118 - r, x + r, iy + S - 118 + r], fill=ACC)

# 标题
center(d, 790, "课时宝", f(FONT, 132), WHITE)
center(d, 960, "课时管理 · 打卡记账", f(FONT_R, 50), (255, 255, 255, 235))

# 分隔线
d.line([(W // 2 - 120, 1060), (W // 2 + 120, 1060)], fill=(255, 255, 255, 110), width=3)

# 三条卖点
feats = ["多宝贝 · 课程独立核算", "每周几单独排课，节假日自动标记", "纯本地存储 · 不联网不上传"]
y = 1130
for t in feats:
    d.ellipse([150, y + 14, 176, y + 40], fill=(255, 255, 255, 220))
    d.text((204, y), t, font=f(FONT_R, 42), fill=(255, 255, 255, 245))
    y += 92

# 底部胶囊
label = "iOS 17+  ·  未签名 IPA  ·  本机自签安装"
fw = d.textbbox((0, 0), label, font=f(FONT_R, 34))[2]
bx, by = (W - fw - 96) // 2, 1700
d.rounded_rectangle([bx, by, bx + fw + 96, by + 88], radius=44, fill=(255, 255, 255, 46))
d.text((bx + 48, by + 22), label, font=f(FONT_R, 34), fill=(255, 255, 255, 240))

img.save("/var/minis/workspace/kebiaobao-cover.png", "PNG")
print("cover", img.size)

# ---------- 方版 1024 ----------
S2 = 1024
sq = grad((S2, S2), LIGHT, DARK)
d2 = ImageDraw.Draw(sq, "RGBA")
d2.ellipse([-220, -160, 460, 520], fill=(255, 255, 255, 20))
S3 = 340
ix3, iy3 = (S2 - S3) // 2, 210
d2.rounded_rectangle([ix3, iy3, ix3 + S3, iy3 + S3], radius=80, fill=WHITE)
check(d2, S2 // 2, iy3 + S3 // 2 + 5, 0.9, ACC, 34)
for x in (S2 // 2 - 72, S2 // 2, S2 // 2 + 72):
    r = 18
    d2.ellipse([x - r, iy3 + S3 - 100 - r, x + r, iy3 + S3 - 100 + r], fill=ACC)
center(d2, 640, "课时宝", f(FONT, 118), WHITE)
center(d2, 790, "课时管理 · 打卡记账", f(FONT_R, 44), (255, 255, 255, 235))
sq.save("/var/minis/workspace/kebiaobao-cover-square.png", "PNG")
print("square", sq.size)
