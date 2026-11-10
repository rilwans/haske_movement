#!/usr/bin/env bash
# Records one clip from the emulator into clips/<name>.mp4.
#   ./record-clip.sh 02-sign-in
# Press Ctrl+C to stop. A clip can be up to 3 minutes long.
set -uo pipefail

[ $# -eq 1 ] || { echo "Usage: $0 <clip-name>" >&2; exit 2; }
here="$(cd "$(dirname "$0")" && pwd)"
adb="$HOME/Android/Sdk/platform-tools/adb"
remote="/sdcard/tutorial-clip.mp4"
mkdir -p "$here/clips"

echo "Recording $1. Press Ctrl+C to stop."
# Ctrl+C has to stop only the recorder, so that the rest of this script runs.
trap ':' INT
# The Pixel 7 Pro emulator can't encode its full 1440x3120. Without a size it
# falls back to 720x1280, which squashes the picture.
"$adb" shell screenrecord --size 1080x2340 --bit-rate 8000000 "$remote"
trap - INT

# The phone needs a moment to finish writing the file.
sleep 2
"$adb" pull "$remote" "$here/clips/$1.mp4" && "$adb" shell rm -f "$remote"
echo "Saved clips/$1.mp4"
