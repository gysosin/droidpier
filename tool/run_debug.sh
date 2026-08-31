#!/usr/bin/env bash
set -euo pipefail
repository_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runtime_dir="${DROIDPIER_DEBUG_RUNTIME_DIR:-${HOME}/.local/opt/droidpier/0.1.0-beta.1}"
flutter_bin="${FLUTTER_BIN:-${repository_dir}/.tools/flutter/bin/flutter}"
export ADB_PATH="${ADB_PATH:-${runtime_dir}/resources/scrcpy/adb}"
export OPEN_DEX_SCRCPY_DIR="${OPEN_DEX_SCRCPY_DIR:-${runtime_dir}/resources/scrcpy}"
export OPEN_DEX_FFMPEG="${OPEN_DEX_FFMPEG:-${runtime_dir}/resources/ffmpeg/ffmpeg}"
export OPEN_DEX_AGENT_JAR="${OPEN_DEX_AGENT_JAR:-${runtime_dir}/resources/android/open-dex-agent.jar}"
# Never substitute a debug-signed APK for an installed release companion.
export OPEN_DEX_COMPANION_APK="${OPEN_DEX_COMPANION_APK:-${runtime_dir}/resources/android/companion.apk}"
for artifact in "$ADB_PATH" "$OPEN_DEX_FFMPEG" "$OPEN_DEX_AGENT_JAR" "$OPEN_DEX_COMPANION_APK" "$OPEN_DEX_SCRCPY_DIR/scrcpy-server"; do
  if [[ ! -f "$artifact" ]]; then
    echo 'A debug runtime artifact is missing. Set DROIDPIER_DEBUG_RUNTIME_DIR or the documented runtime overrides.' >&2
    exit 1
  fi
done
cd "${repository_dir}/apps/desktop"
exec "$flutter_bin" run -d linux --debug -t lib/main.dart "$@"
