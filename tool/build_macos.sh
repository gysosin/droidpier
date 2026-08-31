#!/usr/bin/env bash
set -euo pipefail
repository_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flutter_bin="${FLUTTER_BIN:-flutter}"
version="$(python3 "${repository_dir}/tool/version.py")"
code="$(python3 "${repository_dir}/tool/version.py" androidVersionCode)"
if [[ -z "${DROIDPIER_ANDROID_PAYLOAD_DIR:-}" ]]; then
  python3 "${repository_dir}/tool/build_android.py"
fi
(
  cd "${repository_dir}/apps/desktop"
  "${flutter_bin}" pub get
  "${flutter_bin}" analyze
  "${flutter_bin}" test --exclude-tags golden
  "${flutter_bin}" build macos --release --no-tree-shake-icons --build-name="${version}" --build-number="${code}"
)
python3 "${repository_dir}/tool/package_native.py" macos
