"""Verify the OS does not duplicate the single large Flutter startup logo."""
from pathlib import Path
import subprocess
import time
import re
import xml.etree.ElementTree as ET
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/native-startup'


def adb(*args):
    return subprocess.check_output(['adb', *args])


def verify(path):
    shot = Image.open(path).convert('RGB')
    # The native preparation window must contain only the shared blue background.
    # The existing Flutter rendering tests separately verify the large LK GROUP
    # image and that its 1.2-second display begins after the first visible frame.
    region = shot.crop((shot.width // 5, shot.height // 4,
                        shot.width * 4 // 5, shot.height * 3 // 4))
    background = (221, 246, 252)
    unexpected = sum(count for count, rgb in region.getcolors(region.width * region.height)
                     if any(abs(a - b) > 3 for a, b in zip(rgb, background)))
    fraction = unexpected / (region.width * region.height)
    assert fraction < 0.0001, f'{path.name}: unwanted native logo/content ({fraction:.2%})'
    print(f'{path.name}: no duplicate native logo; uniform LK background verified')


def launch_from_home():
    # Android 12 intentionally omits the system icon for adb/IDE starts.
    # Use the actual launcher UI, as a person opening the installed app does.
    adb('shell', 'input', 'keyevent', '3')
    width, height = map(int, re.search(r'(\d+)x(\d+)',
        adb('shell', 'wm', 'size').decode()).groups())
    time.sleep(1)
    adb('shell', 'input', 'swipe', str(width // 2), str(height * 4 // 5),
        str(width // 2), str(height // 5), '400')
    time.sleep(1)
    adb('shell', 'uiautomator', 'dump', '/sdcard/lk-launcher.xml')
    root = ET.fromstring(adb('shell', 'cat', '/sdcard/lk-launcher.xml'))
    for node in root.iter('node'):
        if 'LK Startup Check' in (node.get('text', ''), node.get('content-desc', '')):
            x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.attrib['bounds']))
            adb('shell', 'input', 'tap', str((x1 + x2) // 2), str((y1 + y2) // 2))
            return
    (OUT / 'launcher-not-found.png').write_bytes(adb('exec-out', 'screencap', '-p'))
    raise AssertionError('Debug fixture icon was not found in the launcher')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    adb('install', '-r', str(ROOT / 'build/native-apk/app-debug.apk'))
    adb('shell', 'input', 'keyevent', '82')
    for mode in ('no', 'yes'):
        adb('shell', 'cmd', 'uimode', 'night', mode)
        adb('shell', 'am', 'force-stop', 'com.lkgrouptrading.app')
        launch_from_home()
        time.sleep(1)
        path = OUT / f'android31-night-{mode}.png'
        path.write_bytes(adb('exec-out', 'screencap', '-p'))
        verify(path)


if __name__ == '__main__':
    main()
