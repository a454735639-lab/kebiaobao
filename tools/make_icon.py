#!/usr/bin/env python3
"""生成 1024x1024 桌面图标：青绿渐变底 + 白色圆角卡片 + 对勾 + 课时点。

iOS 会自己裁圆角，所以底图铺满整块画布。
"""
from PIL import Image, ImageDraw

S = 1024
ACC = (0x53, 0xB4, 0xA4)
DARK = (0x2F, 0x82, 0x76)
LIGHT = (0x7F, 0xD3, 0xC4)

img = Image.new("RGB", (S, S))
d = ImageDraw.Draw(img, "RGBA")

# 纵向渐变底
for y in range(S):
    t = y / (S - 1)
    d.line([(0, y), (S, y)], fill=tuple(int(LIGHT[i] + (DARK[i] - LIGHT[i]) * t) for i in range(3)))

# 左上装饰高光
d.ellipse([-200, -160, 440, 480], fill=(255, 255, 255, 26))

# 白色圆角卡片
pad = 196
d.rounded_rectangle([pad, pad, S - pad, S - pad], radius=92, fill=(255, 255, 255, 255))

# 对勾
cx, cy = S // 2, S // 2 + 6
w = 34
d.line([(cx - 118, cy + 4), (cx - 34, cy + 92)], fill=ACC, width=w, joint="curve")
d.line([(cx - 34, cy + 92), (cx + 122, cy - 78)], fill=ACC, width=w, joint="curve")

# 底部三个课时点
for x in (S // 2 - 84, S // 2, S // 2 + 84):
    r = 21
    d.ellipse([x - r, S - pad - 112 - r, x + r, S - pad - 112 + r], fill=ACC)

out = "/var/minis/workspace/kebiaobao/Kebiaobao/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
img.save(out, "PNG")
print("saved", out, img.size)
