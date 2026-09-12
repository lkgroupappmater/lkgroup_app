"""Capture the real Android OS launch window and reject blank/cropped logos."""
from pathlib import Path
import subprocess
import time
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/native-startup'


def adb(*args):
    return subprocess.check_output(['adb', *args])


def verify(path):
    shot = Image.open(path).convert('RGB')
    # Exclude system bars. Both blue and black brand pixels are below 150 red.
    region = shot.crop((shot.width // 5, shot.height // 4,
                        shot.width * 4 // 5, shot.height * 3 // 4))
    mask = region.getchannel('R').point(lambda x: 255 if x < 150 else 0)
    bounds = mask.getbbox()
    assert bounds, f'{path.name}: native startup is blank'
    actual = mask.crop(bounds)
    ratio = actual.width / actual.height
    assert abs(ratio - 598 / 384) < 0.07, f'{path.name}: clipped aspect ratio {ratio:.3f}'
    original = Image.open(ROOT / 'assets/images/lk_group_logo.png').convert('RGBA')
    expected = original.getchannel('A').resize(actual.size, Image.Resampling.LANCZOS)
    expected = expected.point(lambda x: 255 if x > 127 else 0)
    intersect = ImageChops.darker(actual, expected).histogram()[255]
    union = ImageChops.lighter(actual, expected).histogram()[255]
    overlap = intersect / union
    assert overlap > 0.92, f'{path.name}: logo silhouette mismatch {overlap:.1%}'
    print(f'{path.name}: full native LK GROUP logo, {actual.size}, silhouette overlap {overlap:.1%}')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    adb('install', '-r', str(ROOT / 'build/native-apk/app-debug.apk'))
    adb('shell', 'input', 'keyevent', '82')
    for mode in ('no', 'yes'):
        adb('shell', 'cmd', 'uimode', 'night', mode)
        adb('shell', 'am', 'force-stop', 'com.lkgrouptrading.app')
        adb('shell', 'am', 'start', '-n',
            'com.lkgrouptrading.app/.StartupPreviewActivity')
        time.sleep(1)
        path = OUT / f'android31-night-{mode}.png'
        path.write_bytes(adb('exec-out', 'screencap', '-p'))
        verify(path)


if __name__ == '__main__':
    main()
