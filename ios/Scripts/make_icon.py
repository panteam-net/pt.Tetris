"""Render the game's geometric cube mark to an opaque app icon (Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw

image = Image.new("RGB", (1024, 1024), (11, 15, 23))
draw = ImageDraw.Draw(image)
for y in range(1024):
    blend = y/1024
    draw.line((0, y, 1024, y), fill=(int(22-11*blend), int(32-17*blend), int(45-22*blend)))


def cube(x, y, color):
    size, depth = 155, 30
    draw.polygon([(x,y),(x+depth,y-depth),(x+size+depth,y-depth),(x+size,y)],
                 fill=tuple(min(255,int(c*1.15)) for c in color))
    draw.polygon([(x+size,y),(x+size+depth,y-depth),(x+size+depth,y+size-depth),(x+size,y+size)],
                 fill=tuple(int(c*.6) for c in color))
    draw.rounded_rectangle((x,y,x+size,y+size), radius=6, fill=color, outline=tuple(min(255,int(c*1.1)) for c in color), width=2)


for x,y in [(238,259),(411,259),(411,432),(584,432)]:
    cube(x,y,(91,232,196))
for x,y in [(238,630),(411,630),(584,630)]:
    cube(x,y,(255,177,105))
path = Path(__file__).resolve().parents[1] / "TetrisDuel/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
image.save(path)
print(path)
