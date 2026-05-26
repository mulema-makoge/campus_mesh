from PIL import Image, ImageDraw

size = 1024
img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Background - solid for adaptive icon foreground
bg_color = (27, 79, 138)
draw.ellipse([0, 0, size, size], fill=bg_color)

cx, cy = size // 2, size // 2

nodes = [
    (cx, cy - 280),
    (cx + 240, cy - 120),
    (cx + 240, cy + 140),
    (cx, cy + 280),
    (cx - 240, cy + 140),
    (cx - 240, cy - 120),
    (cx, cy),
]

connections = [
    (0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 0),
    (0, 6), (1, 6), (2, 6), (3, 6), (4, 6), (5, 6),
    (0, 2), (1, 3),
]

line_color = (255, 255, 255, 140)
for a, b in connections:
    x1, y1 = nodes[a]
    x2, y2 = nodes[b]
    draw.line([x1, y1, x2, y2], fill=line_color, width=18)

node_color = (255, 255, 255, 255)
accent_color = (46, 134, 193, 255)

for i, (nx, ny) in enumerate(nodes):
    r = 52 if i == 6 else 38
    c = accent_color if i == 6 else node_color
    draw.ellipse([nx-r, ny-r, nx+r, ny+r], fill=c)

import os
os.makedirs('assets/icons', exist_ok=True)
img.save('assets/icons/app_icon.png')
print("Done: assets/icons/app_icon.png")