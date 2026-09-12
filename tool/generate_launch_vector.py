"""Encode the supplied PNG pixels as native Android paths, without retracing.

Pillow is used only to read the source. The generated asset is VectorDrawable
code: exact colors, transparency and letter shapes with a safe native inset.
"""
from collections import defaultdict
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def generate():
    image = Image.open(ROOT / 'assets/images/lk_group_logo.png').convert('RGBA')
    paths = defaultdict(list)
    for y in range(image.height):
        x = 0
        while x < image.width:
            color = image.getpixel((x, y))
            end = x + 1
            while end < image.width and image.getpixel((end, y)) == color:
                end += 1
            if color[3]:
                paths[color].append(f'M{x},{y}h{end-x}v1h{x-end}z')
            x = end
    lines = [
        '<?xml version="1.0" encoding="utf-8"?>',
        '<!-- Generated from the original LK GROUP PNG by tool/generate_launch_vector.py.',
        '     All artwork fits inside the Android 12 safe circle, including LK GROUP. -->',
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"',
        '    android:width="288dp" android:height="288dp"',
        '    android:viewportWidth="598" android:viewportHeight="598">',
        '    <group android:scaleX="0.52" android:scaleY="0.52"',
        '        android:translateX="143.52" android:translateY="199.16">',
    ]
    for (r, g, b, a), parts in sorted(paths.items()):
        lines.append(f'        <path android:fillColor="#{a:02x}{r:02x}{g:02x}{b:02x}" android:pathData="{"".join(parts)}" />')
    lines += ['    </group>', '</vector>', '']
    destination = ROOT / 'android/app/src/main/res/drawable/lk_group_launch.xml'
    destination.write_text('\n'.join(lines))
    print(f'Generated {destination.name}: {destination.stat().st_size} bytes')


if __name__ == '__main__':
    generate()
