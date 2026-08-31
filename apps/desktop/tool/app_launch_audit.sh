#!/usr/bin/env bash
# Launch every advertised Android application on a real scrcpy display long
# enough for its initial UI to settle. Captures are deleted after metrics are
# extracted; only the non-content summary remains.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRCPY_DIR="${OPEN_DEX_SCRCPY_DIR:-$ROOT/.tools/scrcpy-v4.1}"
SCRCPY="$SCRCPY_DIR/scrcpy"
ADB="$SCRCPY_DIR/adb"
DURATION="${1:-20}"
SUMMARY="${2:-/tmp/open-dex-app-launch-audit-summary.tsv}"
TEMP_DIR="$(mktemp -d /tmp/open-dex-app-launch-audit-XXXXXX)"

cleanup() {
  case "$TEMP_DIR" in
    /tmp/open-dex-app-launch-audit-??????) ;;
    *) return ;;
  esac
  [ -d "$TEMP_DIR" ] || return
  find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type f -delete
  rmdir "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM HUP

if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [ "$DURATION" -lt 10 ]; then
  echo "duration must be an integer of at least 10 seconds" >&2
  exit 2
fi
if [ ! -x "$SCRCPY" ] || [ ! -x "$ADB" ]; then
  echo "scrcpy runtime is unavailable at $SCRCPY_DIR" >&2
  exit 2
fi

SERIAL="$($ADB get-serialno)"
if [ -z "$SERIAL" ] || [ "$SERIAL" = unknown ]; then
  echo "an authorised Android device is required" >&2
  exit 2
fi

printf 'result\tpackage\tdisplay\tvideo_size\tframes\tyavg\tyrange\tbackend_error\n' > "$SUMMARY"
mapfile -t PACKAGES < <(
  "$ADB" shell cmd package query-activities --brief \
    -a android.intent.action.MAIN \
    -c android.intent.category.LAUNCHER |
    sed -n 's#^ *\([^/ ]*\)/.*#\1#p' |
    sort -u
)

echo "Auditing ${#PACKAGES[@]} apps for ${DURATION}s each"
echo "Summary: $SUMMARY"

index=0
for package_name in "${PACKAGES[@]}"; do
  index=$((index + 1))
  stdout_file="$TEMP_DIR/$index.out"
  stderr_file="$TEMP_DIR/$index.err"
  video_file="$TEMP_DIR/$index.mkv"

  "$SCRCPY" \
    --serial="$SERIAL" \
    --new-display=1280x720/240 \
    --max-fps=60 \
    --video-codec=h264 \
    --video-bit-rate=12M \
    --no-window \
    --no-audio \
    --record="$video_file" \
    --record-format=mkv \
    --start-app="$package_name" \
    --time-limit="$DURATION" > "$stdout_file" 2> "$stderr_file"

  display_id="$(sed -n \
    's/.*New display:.*(id=\([0-9][0-9]*\)).*/\1/p' \
    "$stdout_file" | tail -1)"

  started=no
  grep -q 'Starting app' "$stdout_file" && started=yes
  frames="$(ffprobe -v error -select_streams v:0 -count_frames \
    -show_entries stream=nb_read_frames -of csv=p=0 \
    "$video_file" 2>/dev/null | tail -1)"
  video_size="$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=width,height -of csv=s=x:p=0 \
    "$video_file" 2>/dev/null | tail -1)"
  # Calibration on the real device shows scrcpy's virtual-display teardown
  # writes black video at EOF. Sample five seconds before EOF so this describes
  # the settled app while still honoring the full dwell time.
  frame_stats="$(ffmpeg -hide_banner -nostdin -loglevel error \
    -sseof -5 -i "$video_file" -frames:v 1 \
    -vf signalstats,metadata=print:file=- -f null - 2>/dev/null)"
  yavg="$(sed -n 's/.*YAVG=//p' <<< "$frame_stats" | tail -1)"
  ymin="$(sed -n 's/.*YMIN=//p' <<< "$frame_stats" | tail -1)"
  ymax="$(sed -n 's/.*YMAX=//p' <<< "$frame_stats" | tail -1)"
  yrange="$(awk -v low="${ymin:-0}" -v high="${ymax:-0}" \
    'BEGIN { printf "%.1f", high - low }')"
  backend_error=no
  grep -qiE 'error|failed|exception|denied|not found' \
    "$stdout_file" "$stderr_file" && backend_error=yes

  result=PASS
  if [ -z "$display_id" ] || [ "$started" != yes ] ||
     [ -z "$frames" ] || [ "$frames" = 0 ]; then
    result=FAIL
  elif awk -v average="${yavg:-0}" -v spread="$yrange" \
    'BEGIN { exit !(average < 20 && spread < 4) }'; then
    result=BLACK
  fi

  printf '[%02d/%02d] %-5s %-42s frames=%-5s final-luma=%s/%s\n' \
    "$index" "${#PACKAGES[@]}" "$result" "$package_name" \
    "${frames:-0}" "${yavg:-n/a}" "$yrange"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$result" "$package_name" "${display_id:-none}" \
    "${video_size:-unknown}" "${frames:-0}" "${yavg:-n/a}" "$yrange" \
    "$backend_error" >> "$SUMMARY"

  # These files may contain private on-device UI. The validated directory was
  # created above solely for this run, so remove each exact file immediately.
  unlink "$video_file"
  unlink "$stdout_file"
  unlink "$stderr_file"
done

cleanup
echo "Audit complete"
