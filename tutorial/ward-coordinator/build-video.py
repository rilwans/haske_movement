#!/usr/bin/env python3
"""Records the tutorial on the Android emulator and joins it to the voice-over.

    ./build-video.py            record, then assemble
    ./build-video.py record     only drive the app and record the takes
    ./build-video.py assemble   only rebuild the video from existing takes

Needs the Pixel_7_Pro emulator running with -gpu swiftshader_indirect (it crashed
with -gpu host), the debug app installed, and the local erims stack up. Taps are timed to the sentences of the voice-over, so
re-check the times in TAKES if the audio is regenerated.
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
OUTPUT = HERE / "ward-coordinator-tutorial.mp4"
ADB = str(Path.home() / "Android/Sdk/platform-tools/adb")
PACKAGE = "com.haskemovement.canvasser"
REMOTE = "/sdcard/tutorial-take.mp4"
SIZE = "1080x2340"

SETTLE = 1.5  # seconds between starting the recorder and timeline zero
TAP_DELAY = -0.095  # measured with -gpu swiftshader_indirect: a tap shows on video this long after its wall-clock time

# Screen positions on the 1440x3120 emulator.
PHONE_SIGNIN = (718, 1785)
PASSWORD_WITH_KEYBOARD = (720, 1599)
CLOSE_KEYBOARD = (200, 3036)
SIGN_IN = (718, 2310)
NEW_PASSWORD = (546, 1519)
CONFIRM_WITH_KEYBOARD = (720, 1233)
SAVE_PASSWORD_WITH_KEYBOARD = (720, 1509)
ALLOW_LOCATION = (719, 1992)
TEAM_TAB = (1259, 2902)
ONBOARD_BUTTON = (1050, 2602)
LAST_NAME = (718, 730)
PHONE_FORM = (718, 969)
POLLING_UNIT = (718, 1747)
FIRST_SEARCH_RESULT = (270, 975)
SAVE = (718, 2012)
ADDED_HERE = (1051, 874)
SYNC_NOW = (1277, 446)

SAVE_PASSWORD_AT = 11.5  # on the password take's timeline
PASSWORD_CUT = SAVE_PASSWORD_AT + 0.2


def takes(default_password, new_password):
    """Each take: its name, then (time, action, value) on its own timeline."""
    return [
        ("t01", 11.2, []),
        ("t02", 10.2, [
            (1.5, "tap", PHONE_SIGNIN),
            (2.0, "type", "08005550101"),
            (4.7, "tap", PASSWORD_WITH_KEYBOARD),
            (5.5, "type", default_password),
            (7.7, "tap", CLOSE_KEYBOARD),
            (8.5, "tap", SIGN_IN),
        ]),
        ("t03", PASSWORD_CUT + 13.5, [
            (5.0, "tap", NEW_PASSWORD),
            (5.6, "type", new_password),
            (8.0, "tap", CONFIRM_WITH_KEYBOARD),
            (8.5, "type", new_password),
            (SAVE_PASSWORD_AT, "tap", SAVE_PASSWORD_WITH_KEYBOARD),
            (PASSWORD_CUT + 7.6, "tap", ALLOW_LOCATION),
        ]),
        ("t05", 8.4, [
            (4.0, "tap", TEAM_TAB),
            (6.3, "tap", ONBOARD_BUTTON),
        ]),
        ("t06", 13.9, [
            (0.3, "type", "Musa"),
            (1.4, "tap", LAST_NAME),
            (1.8, "type", "Ibrahim"),
            (3.2, "tap", PHONE_FORM),
            (3.6, "type", "08005550102"),
        ]),
        ("t07", 10.5, [
            (1.2, "tap", POLLING_UNIT),
            (4.7, "type", "sch lanwa"),
            (8.6, "tap", FIRST_SEARCH_RESULT),
        ]),
        ("t08", 13.8, [
            (4.1, "tap", CLOSE_KEYBOARD),
            (5.6, "tap", SAVE),
        ]),
        ("t09", 35.0, [
            (1.8, "tap", ADDED_HERE),
            (14.3, "tap", SYNC_NOW),
        ]),
    ]


def segments():
    """Which take each voice-over plays over, and where it starts in that take."""
    second_half = duration(AUDIO / "09-check-status.mp3") + 0.6
    return [
        dict(name="01-welcome", take="t01", start=0.0),
        dict(name="02-sign-in", take="t02", start=0.0),
        # The screen holds on the Save tap while the last sentence plays. The
        # next clip carries straight on from that frame into the phone setup.
        dict(name="03-set-password", take="t03", start=0.0, freeze=PASSWORD_CUT, tail=0.2),
        dict(name="04-setup", take="t03", start=PASSWORD_CUT, lead=0.0),
        dict(name="05-open-form", take="t05", start=0.0),
        dict(name="06-details", take="t06", start=0.0),
        dict(name="07-polling-unit", take="t07", start=0.0),
        dict(name="08-save", take="t08", start=0.0),
        dict(name="09-check-status", take="t09", start=0.0),
        dict(name="10-handover", take="t09", start=second_half, tail=1.5),
    ]


def adb(*args, **kwargs):
    return subprocess.run([ADB, *args], check=True, **kwargs)


def shell(command):
    adb("shell", command)


def do(action, value):
    if action == "tap":
        shell(f"input tap {value[0]} {value[1]}")
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

    for name, length, events in takes(default_password, new_password):
        print(f"Recording {name}", flush=True)
        started = time.monotonic()
        recorder = subprocess.Popen(
            [ADB, "shell", "screenrecord", "--size", SIZE, "--bit-rate", "8000000", REMOTE],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for at, action, value in events:
            wait = started + SETTLE + at - time.monotonic()
            if wait > 0:
                time.sleep(wait)
            else:
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
        # Time for the app to reach the next screen before the next take.
        time.sleep(5)

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
