#!/usr/bin/env python3
"""Records the candidate tutorial on the emulator and joins it to the voice-over.

    ./build-video.py            record, then assemble
    ./build-video.py record     only drive the app and record the takes
    ./build-video.py assemble   only rebuild the video from existing takes

Needs the Pixel_7_Pro emulator running with -gpu swiftshader_indirect (it crashed
with -gpu host), the debug app installed, and the local erims stack up. Taps are
timed to the sentences of the voice-over, in seconds from the start of each
clip's audio, so re-check the times below if the audio is regenerated.
"""
import os
import re
import secrets
import shlex
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
APP = HERE.parent.parent
CLIPS = HERE / "clips"
AUDIO = HERE / "audio"
OUTPUT = HERE / "candidate-tutorial.mp4"
ADB = str(Path.home() / "Android/Sdk/platform-tools/adb")
PACKAGE = "com.haskemovement.canvasser"
REMOTE = "/sdcard/tutorial-take.mp4"
SIZE = "1080x2340"

SETTLE = 1.5  # seconds between starting the recorder and timeline zero
TAP_DELAY = -0.095  # measured with software rendering: a tap shows this long after it is sent

# Screen positions on the 1440x3120 emulator.
PHONE_SIGNIN = (718, 1785)
PASSWORD_WITH_KEYBOARD = (720, 1599)
CLOSE_KEYBOARD = (200, 3036)
SIGN_IN = (718, 2310)
NEW_PASSWORD = (546, 1519)
CONFIRM_WITH_KEYBOARD = (720, 1233)
SAVE_PASSWORD_WITH_KEYBOARD = (720, 1509)
ALLOW_LOCATION = (719, 1992)
RANK_BUTTON = (1068, 938)
MOST_SUPPORTING = (966, 1349)
ISSUES_PERSUADABLE = (1022, 1370)
ISSUES_ALL = (418, 1370)
DEMO_WEST_ATTENTION = (700, 1807)
SEE_WARD_BY_WARD = (720, 2724)
LGA_BOX = (700, 465)
WARD_BOX = (700, 674)
THIRD_MENU_WARD = (300, 1011)
DEMO_CENTRAL_IN_LIST = (700, 1440)
OVERVIEW_TAB = (360, 2880)
PROFILE = (1355, 240)
OUTSIDE_MENU = (400, 1800)

# Slow enough that each one lands in the same place every time.
DOWN_A_SECTION = (720, 2300, 720, 1200, 1300)
DOWN_A_LITTLE = (720, 2300, 720, 1600, 1200)
DOWN_A_SCREEN = (720, 2400, 720, 900, 1300)
AREAS_TO_FOCUS = (720, 2400, 720, 1400, 1100)
BACK_TO_TOP = (720, 900, 720, 2700, 250)
PULL_TO_REFRESH = (720, 1000, 720, 2300, 900)

SAVE_PASSWORD_AT = 12.4
PASSWORD_CUT = SAVE_PASSWORD_AT + 0.2


def takes(default_password, new_password):
    """(name, length, events, steps run before recording starts, wait afterwards)"""
    tap, typ, swipe = "tap", "type", "swipe"
    return [
        ("t01", 2.5, [], [], 1),
        ("t03", 15.9, [
            (2.5, tap, PHONE_SIGNIN),
            (3.2, typ, "08005550400"),
            (6.0, tap, PASSWORD_WITH_KEYBOARD),
            (7.2, typ, default_password),
            (11.6, tap, CLOSE_KEYBOARD),
            (13.8, tap, SIGN_IN),
        ], [], 6),
        ("t04", PASSWORD_CUT + 11.4, [
            (5.0, tap, NEW_PASSWORD),
            (5.7, typ, new_password),
            (9.4, tap, CONFIRM_WITH_KEYBOARD),
            (10.0, typ, new_password),
            (SAVE_PASSWORD_AT, tap, SAVE_PASSWORD_WITH_KEYBOARD),
            (PASSWORD_CUT + 6.6, tap, ALLOW_LOCATION),
        ], [], 3),
        ("t06", 2.5, [], [], 1),
        ("t08", 17.7, [(1.2, swipe, DOWN_A_SECTION)], [], 2),
        ("t09", 24.9, [(0.3, swipe, DOWN_A_LITTLE)], [], 2),
        ("t10", 18.5, [
            (0.2, swipe, DOWN_A_SECTION),
            (8.6, tap, RANK_BUTTON),
            (12.8, tap, MOST_SUPPORTING),
        ], [], 2),
        ("t11", 8.8, [(0.3, swipe, DOWN_A_SCREEN)], [], 2),
        ("t12", 11.6, [(0.3, swipe, DOWN_A_SCREEN)], [], 2),
        ("t13", 17.0, [
            (0.2, swipe, DOWN_A_SCREEN),
            (5.7, tap, ISSUES_PERSUADABLE),
            (13.0, tap, ISSUES_ALL),
        ], [], 2),
        ("t14", 16.5, [
            (3.7, swipe, BACK_TO_TOP),
            (4.2, swipe, BACK_TO_TOP),
            (4.7, swipe, BACK_TO_TOP),
            (5.2, swipe, BACK_TO_TOP),
            (5.7, swipe, BACK_TO_TOP),
            (7.2, tap, DEMO_WEST_ATTENTION),
        ], [], 2),
        ("t15", 2.5, [], [], 1),
        ("t16", 4.4, [(2.3, tap, SEE_WARD_BY_WARD)], [], 6),
        ("t17", 2.5, [], [], 1),
        ("t18", 12.9, [(0.3, swipe, AREAS_TO_FOCUS)], [], 2),
        ("t19", 12.7, [
            (0.3, swipe, DOWN_A_SCREEN),
            (5.0, swipe, DOWN_A_SCREEN),
        ], [], 2),
        ("t20", 6.5, [(0.2, swipe, DOWN_A_SCREEN)], [], 2),
        ("t21", 10.0, [
            (1.7, swipe, BACK_TO_TOP),
            (2.1, swipe, BACK_TO_TOP),
            (2.5, swipe, BACK_TO_TOP),
            (4.0, tap, WARD_BOX),
            (5.3, tap, THIRD_MENU_WARD),
        ], [], 4),
        ("t22", 15.6, [
            (0.8, tap, LGA_BOX),
            (10.6, tap, DEMO_CENTRAL_IN_LIST),
        ], [], 4),
        ("t23", 13.7, [
            (0.5, tap, OVERVIEW_TAB),
            (5.6, swipe, PULL_TO_REFRESH),
        ], [], 3),
        ("t24", 16.1, [(1.3, tap, PROFILE)], [], 2),
        ("t25", 2.5, [], [(tap, OUTSIDE_MENU), ("wait", 1.5)], 1),
    ]


def segments():
    """Which take each voice-over plays over."""
    def seg(name, take, **extra):
        return dict(name=name, take=take, start=0.0, **extra)
    return [
        seg("01-welcome", "t01"),
        seg("02-what-it-does", "t01"),
        seg("03-sign-in", "t03"),
        # The screen holds on the Save tap while the last sentence plays. The
        # next clip carries straight on from that frame into the phone setup.
        seg("04-set-password", "t04", freeze=PASSWORD_CUT, tail=0.2),
        dict(name="05-setup", take="t04", start=PASSWORD_CUT, lead=0.0),
        seg("06-headline", "t06"),
        seg("07-needs-attention", "t06"),
        seg("08-momentum", "t08"),
        seg("09-vote-count", "t09"),
        seg("10-ranked", "t10"),
        seg("11-team", "t11"),
        seg("12-gaps", "t12"),
        seg("13-issues", "t13"),
        seg("14-open-brief", "t14"),
        seg("15-brief-details", "t15"),
        seg("16-ward-by-ward", "t16"),
        seg("17-areas-top", "t17"),
        seg("18-where-to-focus", "t18"),
        seg("19-who-they-are", "t19"),
        seg("20-by-ward", "t20"),
        seg("21-choose-ward", "t21"),
        seg("22-choose-lga", "t22", tail=3.2),
        seg("23-updates", "t23"),
        seg("24-sign-out", "t24"),
        seg("25-closing", "t25", tail=1.5),
    ]


def adb(*args, **kwargs):
    return subprocess.run([ADB, *args], check=True, **kwargs)


def shell(command):
    adb("shell", command)


def do(action, value):
    if action == "tap":
        shell(f"input tap {value[0]} {value[1]}")
    elif action == "swipe":
        shell("input swipe " + " ".join(map(str, value)))
    elif action == "wait":
        time.sleep(value)
    else:
        for char in value:
            shell("input text " + shlex.quote("%s" if char == " " else char))
            time.sleep(0.05)


def demo_mode(on):
    def command(*args):
        shell("am broadcast -a com.android.systemui.demo -e command " + " ".join(args) + " >/dev/null")
    shell("settings put global sysui_demo_allowed 1")
    if not on:
        command("exit")
        return
    command("enter")
    command("clock -e hhmm 0900")
    command("battery -e level 100 -e plugged false")
    command("network -e wifi show -e level 4 -e fully true")
    command("network -e mobile hide")
    command("notifications -e visible false")


def record():
    config = (APP / "lib/config.dart").read_text()
    default_password = re.search(r"'DEFAULT_PASSWORD', defaultValue: '([^']+)'", config).group(1)
    new_password = "Demo" + secrets.token_hex(3)

    CLIPS.mkdir(exist_ok=True)
    subprocess.run([str(HERE / "reset-demo.sh")], check=True)
    demo_mode(True)
    shell(f"monkey -p {PACKAGE} -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1")
    time.sleep(10)

    try:
        for name, length, events, before, wait_after in takes(default_password, new_password):
            print(f"Recording {name}", flush=True)
            for action, value in before:
                do(action, value)
            started = time.monotonic()
            recorder = subprocess.Popen(
                [ADB, "shell", "screenrecord", "--size", SIZE, "--bit-rate", "8000000", REMOTE],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            for at, action, value in events:
                wait = started + SETTLE + at - time.monotonic()
                if wait > 0:
                    time.sleep(wait)
                elif wait < -0.3:
                    print(f"  {action} at {at} ran {-wait:.2f}s late", flush=True)
                do(action, value)
            wait = started + SETTLE + length - time.monotonic()
            if wait > 0:
                time.sleep(wait)
            shell("pkill -INT screenrecord")
            recorder.wait(timeout=15)
            time.sleep(1)
            adb("pull", REMOTE, str(CLIPS / f"{name}.mp4"), stdout=subprocess.DEVNULL)
            shell(f"rm -f {REMOTE}")
            time.sleep(wait_after)
    finally:
        demo_mode(False)


def duration(path):
    out = subprocess.check_output(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)], text=True)
    return float(out)


def assemble():
    work = CLIPS / "segments"
    work.mkdir(parents=True, exist_ok=True)
    parts = []
    for seg in segments():
        audio = AUDIO / f"{seg['name']}.mp3"
        lead = seg.get("lead", 0.35)
        total = lead + duration(audio) + seg.get("tail", 0.55)
        offset = SETTLE - TAP_DELAY
        video_start = max(0.0, offset + seg["start"] - lead)

        # eof_action=pass keeps the only frame of a take where the screen never changes.
        chain = "fps=30:eof_action=pass,format=yuv420p,tpad=stop_mode=clone:stop_duration=90"
        if "freeze" in seg:
            held = lead + seg["freeze"] - seg["start"]
            chain += f",trim=start={video_start:.3f}:duration={held:.3f},setpts=PTS-STARTPTS"
            chain += ",tpad=stop_mode=clone:stop_duration=90"
            chain += f",trim=duration={total:.3f}"
        else:
            chain += f",trim=start={video_start:.3f}:duration={total:.3f}"
        chain += ",setpts=PTS-STARTPTS"

        sound = f"aresample=48000,aformat=channel_layouts=stereo,adelay={int(lead * 1000)}:all=1,apad,atrim=0:{total:.3f}"
        out = work / f"{seg['name']}.mp4"
        # ffmpeg now and then drops the picture from a one-frame take, so check.
        for attempt in range(4):
            subprocess.run([
                "ffmpeg", "-v", "error", "-y", "-i", str(CLIPS / f"{seg['take']}.mp4"), "-i", str(audio),
                "-filter_complex", f"[0:v]{chain}[v];[1:a]{sound}[a]", "-map", "[v]", "-map", "[a]",
                "-c:v", "libx264", "-preset", "medium", "-crf", "21", "-r", "30",
                "-c:a", "aac", "-b:a", "128k", "-t", f"{total:.3f}", str(out),
            ], check=True)
            streams = subprocess.check_output(
                ["ffprobe", "-v", "error", "-show_entries", "stream=codec_type", "-of", "csv=p=0", str(out)], text=True)
            if "video" in streams:
                break
        else:
            raise RuntimeError(f"{seg['name']} came out with no picture")
        parts.append(out)
        print(f"Built {seg['name']} ({total:.1f}s)", flush=True)

    listing = work / "list.txt"
    listing.write_text("".join(f"file '{p}'\n" for p in parts))
    subprocess.run([
        "ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", str(listing),
        "-c:v", "copy", "-af", "loudnorm=I=-16:TP=-1.5:LRA=11", "-ar", "48000",
        "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", str(OUTPUT),
    ], check=True)
    print(f"Done: {OUTPUT.name}, {duration(OUTPUT):.1f}s, {os.path.getsize(OUTPUT) / 1e6:.1f} MB", flush=True)


if __name__ == "__main__":
    step = sys.argv[1] if len(sys.argv) > 1 else "all"
    if step in ("all", "record"):
        record()
    if step in ("all", "assemble"):
        assemble()
