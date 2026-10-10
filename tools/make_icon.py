#!/usr/bin/env python3
"""生成 1024x1024 App 图标：青绿底 + 白色对勾 + 课时点。"""
from PIL import Image, ImageDraw

S = 1024
ACC = (0x53, 0xB4, 0xA4)
DARK = (0x3F, 0x9C, 0x8D)

img = Image.new("RGB", (S, S), ACC)
d = ImageDraw.Draw(img)

# 顶部斜向高光
for y in range(S):
    t = y / S
    c = tuple(int(ACC[i] + (DARK[i] - ACC[i]) * t) for i in range(3))
    d.line([(0, y), (S, y)], fill=c)

# 白色圆角卡片
pad = 208
d.rounded_rectangle([pad, pad, S - pad, S - pad], radius=96, fill=(255, 255, 255))

# 对勾
cx, cy = S // 2, S // 2 + 8
w = 34
d.line([(cx - 118, cy + 4), (cx - 34, cy + 92)], fill=ACC, width=w, joint="curve")
d.line([(cx - 34, cy + 92), (cx + 122, cy - 78)], fill=ACC, width=w, joint="curve")

# 底部三个课时点
for i, x in enumerate((S // 2 - 78, S // 2, S // 2 + 78)):
    r = 20
    d.ellipse([x - r, S - pad - 108 - r, x + r, S - pad - 108 + r], fill=ACC)

out = "/var/minis/workspace/kebiaobao/Kebiaobao/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
img.save(out, "PNG")
print("saved", out, img.size)
