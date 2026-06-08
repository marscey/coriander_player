#!/usr/bin/env python3
"""Send touch events to iOS Simulator to navigate tabs and take screenshots."""
import subprocess
import time
import os

DEVICE = "4B672328-EEE8-495A-A824-433D5BF31280"
BUNDLE = "com.senyepss.corianderPlayer"
OUTPUT_DIR = "/tmp/ui_test"

# Tab positions (logical pixels on iPhone 16: 393x852, scale 2.67)
# From hierarchy: tabs at device pixel y=738-818 → logical y=276-306, center y≈291
TABS = {
    "01-music-library":  (39, 291),   # 音乐库
    "02-recent-plays":   (66, 291),   # 最近播放
    "03-cloud":          (93, 291),   # 连接
    "04-search":         (118, 291),  # 搜索
    "05-settings":       (147, 291),  # 设置
}

def tap(x, y):
    """Send a touch event using CGEvent via Python."""
    script = f'''
    use framework "CoreGraphics"
    use scripting additions

    set point to {{{x}, {y}}}
    set mouseLocation to point

    -- Create touch down event
    set mouseDown to current application's CGEventCreateMouseEvent(missing value, $
        current application's kCGEventLeftMouseDown, mouseLocation, $
        current application's kCGMouseButtonLeft)

    -- Create touch up event
    set mouseUp to current application's CGEventCreateMouseEvent(missing value, $
        current application's kCGEventLeftMouseUp, mouseLocation, $
        current application's kCGMouseButtonLeft)

    -- Post events
    current application's CGEventPost(current application's kCGHIDEventTap, mouseDown)
    delay 0.05
    current application's CGEventPost(current application's kCGHIDEventTap, mouseUp)
    '''
    subprocess.run(["osascript", "-e", script], capture_output=True, timeout=5)

def screenshot(name):
    """Take a simulator screenshot."""
    path = f"{OUTPUT_DIR}/{name}.png"
    subprocess.run([
        "xcrun", "simctl", "io", "device", "screenshot",
        "--display", "internal",
        path
    ] if False else [
        "xcrun", "simctl", "io", DEVICE, "screenshot", path
    ], capture_output=True, timeout=10)
    print(f"Screenshot: {path}")
    return path

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Launch app
    print("Launching app...")
    subprocess.run(["xcrun", "simctl", "launch", DEVICE, BUNDLE], capture_output=True)
    time.sleep(8)

    # Take initial screenshot (music library)
    print("Taking music library screenshot...")
    screenshot("01-music-library")

    # Navigate to each tab
    for name, (x, y) in list(TABS.items())[1:]:
        print(f"Navigating to {name}...")
        tap(x, y)
        time.sleep(3)
        screenshot(name)

    print(f"\nAll screenshots saved to {OUTPUT_DIR}/")
    print("Files:")
    for f in sorted(os.listdir(OUTPUT_DIR)):
        if f.endswith('.png'):
            print(f"  {f}")

if __name__ == "__main__":
    main()
