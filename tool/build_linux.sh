#!/usr/bin/env bash
set -euo pipefail
repository_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flutter_bin="${FLUTTER_BIN:-${repository_dir}/.tools/flutter/bin/flutter}"
if [[ -z "${FLUTTER_BIN:-}" && ! -x "${flutter_bin}" ]]; then flutter_bin=flutter; fi
version="$(python3 "${repository_dir}/tool/version.py")"
version_code="$(python3 "${repository_dir}/tool/version.py" androidVersionCode)"
if [[ -z "${DROIDPIER_ANDROID_PAYLOAD_DIR:-}" ]]; then
  python3 "${repository_dir}/tool/build_android.py"
fi
if [[ -z "${DROIDPIER_FFMPEG:-}" ]]; then
  bash "${repository_dir}/tool/build_ffmpeg.sh"
elif [[ ! -x "$DROIDPIER_FFMPEG" ]]; then
  echo 'DROIDPIER_FFMPEG must name an executable decoder.' >&2
  exit 1
fi
bash "${repository_dir}/tool/build_adb.sh"
(
  cd "${repository_dir}/apps/desktop"
  "${flutter_bin}" pub get
  "${flutter_bin}" analyze
  "${flutter_bin}" test
  # Ship full Material font: icon tree shaking previously produced invalid glyphs.
  "${flutter_bin}" build linux --release --no-tree-shake-icons \
    --build-name="${version}" --build-number="${version_code}"
)
python3 "${repository_dir}/tool/package_linux.py"
