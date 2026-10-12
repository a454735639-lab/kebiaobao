#!/usr/bin/env python3
"""生成 1024x1024 桌面图标（v1.12.0 重绘）。

设计：青绿斜向渐变底 + 斜向高光 + 白色圆角卡片 + 环形进度 + 对勾 + 三颗课时点。
4x 超采样后降采样，边缘平滑（PIL 自身无抗锯齿）。
iOS 会自己裁圆角，底图铺满整块画布。
"""
from PIL import Image, ImageDraw, ImageFilter

S = 1024
SS = 2                       # 超采样倍数（iSH 内存有限，2x + LANCZOS 足够平滑）
W = S * SS

ACC = (0x53, 0xB4, 0xA4)
ACC_D = (0x2E, 0x8A, 0x7C)
LIGHT = (0x7F, 0xD3, 0xC4)
DARK = (0x33, 0x8F, 0x81)
OUT = "/var/minis/workspace/kebiaobao/Kebiaobao/Assets.xcassets/AppIcon.appiconset/"


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient_bg(top, bot):
    """斜向渐变（135°），逐行画再旋转 45° 太重 —— 直接按 (x+y) 混合画小图再放大"""
    small = Image.new("RGB", (256, 256))
    sd = ImageDraw.Draw(small)
    for y in range(256):
        for x in range(256):
            t = (x + y) / 510
            sd.point((x, y), fill=lerp(top, bot, t))
    return small.resize((W, W), Image.BICUBIC)


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1],
                                        radius=radius, fill=255)
    return m


def draw_all(top, bot, card_fill, acc, acc_deep, dot_fill, glow=True):
    img = gradient_bg(top, bot).convert("RGBA")

    # 左上大高光 + 右下暗角，制造体积感
    # 注意：PIL 的 ImageDraw 在 RGBA 图上画半透明色是**覆盖**不是混合，
    # 必须画到独立 layer 再 alpha_composite。
    shade = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade, "RGBA")
    sd.ellipse([-W * 0.30, -W * 0.34, W * 0.46, W * 0.42], fill=(255, 255, 255, 30))
    sd.ellipse([W * 0.58, W * 0.60, W * 1.30, W * 1.32], fill=(0, 0, 0, 26))
    shade = shade.filter(ImageFilter.GaussianBlur(int(0.05 * W)))
    img.alpha_composite(shade)
    d = ImageDraw.Draw(img, "RGBA")

    # 卡片投影
    pad = int(0.185 * W)
    rad = int(0.085 * W)
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [pad, pad + int(0.014 * W), W - pad, W - pad + int(0.014 * W)],
        radius=rad, fill=(0, 0, 0, 60))
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(0.022 * W)))
    img.alpha_composite(shadow)

    # 白色卡片（用 mask 保证圆角平滑）
    card = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    cm = rounded_mask(W, rad)
    off = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(off).rounded_rectangle([pad, pad, W - pad, W - pad],
                                          radius=rad, fill=card_fill)
    card.paste(off, (0, 0), cm)
    img.alpha_composite(card)

    cx, cy = W // 2, int(W * 0.452)
    R = int(0.132 * W)          # 环半径
    lw = int(0.030 * W)         # 环线宽

    # 环形底槽（半透明色在 ImageDraw 里是覆盖不是混合，直接用调浅的实色）
    track = lerp((255, 255, 255), acc, 0.22)
    d.arc([cx - R, cy - R, cx + R, cy + R], start=0, end=360,
          fill=track, width=lw)
    # 进度弧（约 68%，从 -90° 起）
    d.arc([cx - R, cy - R, cx + R, cy + R], start=-90, end=-90 + 245,
          fill=acc_deep + (255,), width=lw)

    # 环心对勾
    k = 0.052 * W
    d.line([(cx - k * 1.55, cy + k * 0.10), (cx - k * 0.48, cy + k * 1.18)],
           fill=acc_deep + (255,), width=int(0.030 * W), joint="curve")
    d.line([(cx - k * 0.48, cy + k * 1.18), (cx + k * 1.72, cy - k * 1.05)],
           fill=acc_deep + (255,), width=int(0.030 * W), joint="curve")

    # 底部三颗课时点（第一颗空心 = 还有剩余）
    dy = int(0.735 * W)
    r = int(0.0245 * W)
    for i, x in enumerate((W // 2 - int(0.118 * W), W // 2, W // 2 + int(0.118 * W))):
        if i == 0:
            d.ellipse([x - r, dy - r, x + r, dy + r],
                      outline=dot_fill + (255,), width=int(0.016 * W))
        else:
            d.ellipse([x - r, dy - r, x + r, dy + r], fill=dot_fill + (255,))

    if glow:
        pass
    return img.convert("RGB").resize((S, S), Image.LANCZOS)


if __name__ == "__main__":
    # 亮色：青绿斜渐变 + 白卡
    light = draw_all(LIGHT, DARK, (255, 255, 255, 255), ACC, ACC_D,
                     (0x3C, 0x9C, 0x8E))
    light.save(OUT + "AppIcon.png", "PNG")
    print("saved AppIcon.png")

    # 深色：深青底 + 白卡 + 提亮青绿
    dark = draw_all((0x24, 0x4E, 0x48), (0x0B, 0x1A, 0x18),
                    (255, 255, 255, 255), (0x5F, 0xC9, 0xB8),
                    (0x5F, 0xC9, 0xB8), (0x5F, 0xC9, 0xB8))
    dark.save(OUT + "AppIcon-Dark.png", "PNG")
    print("saved AppIcon-Dark.png")

    # tinted：灰度，系统自身上色
    tint = draw_all((0xC8, 0xC8, 0xC8), (0x8A, 0x8A, 0x8A),
                    (255, 255, 255, 255), (0x3A, 0x3A, 0x3A),
                    (0x3A, 0x3A, 0x3A), (0x3A, 0x3A, 0x3A))
    tint.convert("L").convert("RGB").save(OUT + "AppIcon-Tinted.png", "PNG")
    print("saved AppIcon-Tinted.png")
