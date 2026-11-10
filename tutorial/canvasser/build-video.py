#!/usr/bin/env python3
"""Records the canvassing tutorial on the emulator and joins it to the voice-over.

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
OUTPUT = HERE / "canvassing-tutorial.mp4"
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
SEARCH = (720, 675)
SEARCH_CLEAR = (1350, 675)
ALL = (195, 858)
NOT_YET = (546, 858)
PERSUADABLE = (1230, 858)
TURN_OUT_SCROLLED = (460, 856)
NEED_PVC_SCROLLED = (908, 856)
UNSURE_END = (696, 856)
VISITED_END = (1180, 856)
AISHA_IN_LIST = (411, 1388)
ONLY_RESULT = (411, 1136)
BOTTOM_RIGHT_BUTTON = (1100, 2900)
BACK = (100, 240)
SYNC_NOW = (1277, 446)
ADD_VOTER_NO_LIST = (1156, 2880)
MEGAPHONE = (1188, 240)
PROFILE = (1356, 240)
OUTSIDE_MENU = (400, 1800)
# The conversation form.
STRONG_SUPPORT = (280, 632)
LEANING_SUPPORT = (776, 632)
UNDECIDED = (232, 812)
HAS_PVC = (212, 1164)
YES = (156, 1696)
ROADS = (512, 2048)
JOBS = (784, 2048)
WATER = (472, 2228)
NOTES_SCROLLED = (720, 2520)
SAVE_SCROLLED = (720, 2832)
# The add voter form.
MALE = (168, 720)
YEAR = (720, 940)
PHONE_ADD = (720, 1180)
ADD_AND_RECORD = (720, 2236)

FORM_UP = (720, 2600, 720, 900, 900)
LIST_UP = (720, 2400, 720, 1500, 700)
LIST_DOWN = (720, 1500, 720, 2400, 700)
CHIPS_LEFT = (1300, 858, 300, 858, 500)
CHIPS_RIGHT = (200, 858, 1400, 858, 300)

SIGN_IN_AT = 15.7
SAVE_PASSWORD_AT = 15.2
PASSWORD_CUT = SAVE_PASSWORD_AT + 0.2
SAVE_AT = 7.4
# Saving can take over 3 seconds. By this point the voter's page has loaded behind the message.
SAVED_MESSAGE_SHOWING = SAVE_AT + 5.5


def takes(default_password, new_password):
    """(name, length, events, steps run before recording starts, wait afterwards)"""
    tap, typ, swipe = "tap", "type", "swipe"
    return [
        ("t01", 2.5, [], [], 1),
        ("t04", SIGN_IN_AT + 1.2, [
            (2.4, tap, PHONE_SIGNIN),
            (3.4, typ, "08005550200"),
            (6.2, tap, PASSWORD_WITH_KEYBOARD),
            (7.4, typ, default_password),
            (13.0, tap, CLOSE_KEYBOARD),
            (SIGN_IN_AT, tap, SIGN_IN),
        ], [], 6),
        ("t05", PASSWORD_CUT + 18.2, [
            (5.0, tap, NEW_PASSWORD),
            (5.8, typ, new_password),
            (11.6, tap, CONFIRM_WITH_KEYBOARD),
            (12.3, typ, new_password),
            (SAVE_PASSWORD_AT, tap, SAVE_PASSWORD_WITH_KEYBOARD),
            (PASSWORD_CUT + 13.0, tap, ALLOW_LOCATION),
        ], [], 2),
        ("t07", 2.5, [], [], 1),
        ("t09", 26.4, [
            (22.5, swipe, LIST_UP),
            (24.1, swipe, LIST_DOWN),
        ], [], 2),
        ("t10", 17.8, [
            (2.8, tap, SEARCH),
            (3.8, typ, "aisha"),
            (15.0, tap, SEARCH_CLEAR),
            (16.2, tap, CLOSE_KEYBOARD),
        ], [], 2),
        ("t11", 21.8, [
            (11.0, tap, NOT_YET),
            (17.4, tap, ALL),
        ], [], 2),
        ("t13", 21.0, [(4.6, tap, AISHA_IN_LIST)], [], 2),
        ("t14", 14.8, [(4.6, tap, BOTTOM_RIGHT_BUTTON)], [], 2),
        ("t15", 34.9, [
            (27.0, tap, UNDECIDED),
            (33.0, tap, LEANING_SUPPORT),
        ], [], 2),
        ("t16", 23.6, [(8.3, tap, HAS_PVC)], [], 2),
        ("t17", 8.8, [(4.0, tap, YES)], [], 2),
        ("t18", 18.6, [
            (12.1, tap, JOBS),
            (12.9, tap, WATER),
            (14.3, tap, ROADS),
            (16.3, tap, ROADS),
        ], [], 2),
        ("t19", 14.4, [(1.6, swipe, FORM_UP)], [], 2),
        ("t20", 2.5, [], [], 1),
        ("t21", 13.9, [
            (7.3, tap, NOTES_SCROLLED),
            (7.9, typ, "Wants the borehole repaired"),
        ], [], 2),
        ("t22", SAVED_MESSAGE_SHOWING + 1.0, [
            (4.0, tap, CLOSE_KEYBOARD),
            (SAVE_AT, tap, SAVE_SCROLLED),
        ], [], 3),
        ("t23", 18.5, [(16.3, tap, BACK)], [], 2),
        ("t24", 2.5, [], [(tap, CLOSE_KEYBOARD), ("wait", 1.5)], 1),
        ("t25", 19.2, [
            (2.7, tap, SEARCH),
            (3.2, typ, "fatima"),
            (4.4, tap, CLOSE_KEYBOARD),
            (5.6, tap, ONLY_RESULT),
            (7.0, tap, BOTTOM_RIGHT_BUTTON),
            (8.6, tap, UNDECIDED),
            (9.4, swipe, FORM_UP),
            (15.4, tap, SAVE_SCROLLED),
        ], [("airplane", True), ("wait", 3)], 5),
        ("t26", 2.5, [], [
            (tap, BACK), ("wait", 1.5),
            (tap, SEARCH_CLEAR), ("wait", 1),
            (tap, CLOSE_KEYBOARD), ("wait", 1.5),
        ], 1),
        ("t27", 19.9, [
            (0.5, "airplane", False),
            (9.4, tap, SYNC_NOW),
        ], [], 2),
        ("t28", 11.9, [
            (4.4, tap, SEARCH),
            (5.0, typ, "Peter Adamu"),
            (6.9, tap, CLOSE_KEYBOARD),
        ], [], 2),
        ("t29", 23.0, [
            (1.6, tap, ADD_VOTER_NO_LIST),
            (7.9, tap, MALE),
            (9.2, tap, YEAR),
            (9.7, typ, "1987"),
            (10.6, tap, PHONE_ADD),
            (11.0, typ, "08005550299"),
            (18.8, tap, CLOSE_KEYBOARD),
            (21.0, tap, ADD_AND_RECORD),
        ], [], 2),
        ("t30", 11.2, [
            (4.2, tap, STRONG_SUPPORT),
            (4.7, swipe, FORM_UP),
            (5.9, tap, SAVE_SCROLLED),
        ], [], 5),
        ("t31", 38.8, [
            (2.7, swipe, CHIPS_LEFT),
            (4.0, swipe, CHIPS_RIGHT),
            (9.4, tap, PERSUADABLE),
            # A tap too soon after a swipe only stops the slide, and selects nothing.
            (13.9, swipe, CHIPS_LEFT),
            (15.6, tap, TURN_OUT_SCROLLED),
            (21.4, tap, NEED_PVC_SCROLLED),
            (26.6, swipe, CHIPS_LEFT),
            (27.9, tap, UNSURE_END),
            (32.6, tap, VISITED_END),
        ], [
            (tap, SEARCH_CLEAR), ("wait", 1),
            (tap, CLOSE_KEYBOARD), ("wait", 1.5),
        ], 2),
        ("t32", 10.5, [
            (3.6, tap, MEGAPHONE),
            (9.0, tap, BACK),
        ], [], 2),
        ("t33", 22.1, [(3.0, tap, PROFILE)], [], 2),
        ("t34", 2.5, [], [
            # Closing the menu brings the keyboard back, because the search box has focus.
            (tap, OUTSIDE_MENU), ("wait", 1.5),
            (swipe, CHIPS_RIGHT), ("wait", 0.6),
            (swipe, CHIPS_RIGHT), ("wait", 1),
            (tap, ALL), ("wait", 1.2),
            (tap, CLOSE_KEYBOARD), ("wait", 1.5),
        ], 1),
    ]


def segments():
    """Which take each voice-over plays over."""
    def seg(name, take, **extra):
        return dict(name=name, take=take, start=0.0, **extra)
    return [
        seg("01-welcome", "t01"),
        seg("02-what-is-canvassing", "t01"),
        seg("03-before-you-start", "t01"),
        # Holds on the Sign in spinner during the last sentence.
        seg("04-sign-in", "t04", freeze=SIGN_IN_AT + 0.4),
        seg("05-set-password", "t05", freeze=PASSWORD_CUT, tail=0.2),
        dict(name="06-setup", take="t05", start=PASSWORD_CUT, lead=0.0),
        seg("07-home-top", "t07"),
        seg("08-sync-bar", "t07"),
        seg("09-voter-list", "t09"),
        seg("10-search", "t10"),
        seg("11-where-to-start", "t11"),
        seg("12-today-count", "t07"),
        seg("13-open-voter", "t13"),
        seg("14-open-form", "t14"),
        seg("15-support", "t15"),
        seg("16-pvc", "t16"),
        seg("17-plans-to-vote", "t17"),
        seg("18-issues", "t18"),
        seg("19-gender-age", "t19"),
        seg("20-contact", "t20"),
        seg("21-notes", "t21"),
        # Holds on the "Saved conversation" message, which only shows for 4 seconds.
        seg("22-save", "t22", freeze=SAVED_MESSAGE_SHOWING),
        seg("23-after-save", "t23"),
        seg("24-back-on-list", "t24"),
        seg("25-no-network", "t25"),
        seg("26-offline-bar", "t26"),
        seg("27-back-online", "t27"),
        seg("28-search-first", "t28"),
        seg("29-add-voter", "t29"),
        seg("30-new-voter-conversation", "t30", tail=2.2),
        seg("31-follow-up-lists", "t31"),
        seg("32-announcements", "t32"),
        seg("33-account", "t33"),
        seg("34-closing", "t34", tail=1.5),
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
    elif action == "airplane":
        shell(f"cmd connectivity airplane-mode {'enable' if value else 'disable'}")
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
        do("airplane", False)
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
        subprocess.run([
            "ffmpeg", "-v", "error", "-y", "-i", str(CLIPS / f"{seg['take']}.mp4"), "-i", str(audio),
            "-filter_complex", f"[0:v]{chain}[v];[1:a]{sound}[a]", "-map", "[v]", "-map", "[a]",
            "-c:v", "libx264", "-preset", "medium", "-crf", "21", "-r", "30",
            "-c:a", "aac", "-b:a", "128k", "-t", f"{total:.3f}", str(out),
        ], check=True)
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
