#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FLUTTER="${OPEN_DEX_FLUTTER:-$ROOT/.tools/flutter/bin/flutter}"
APP="$ROOT/apps/desktop/build/linux/x64/debug/bundle/open_android_dex"

if [[ ! -x "$FLUTTER" ]]; then
  printf 'texture_bench failed: Flutter executable not found at %s\n' "$FLUTTER" >&2
  exit 2
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
  printf 'texture_bench failed: ffmpeg is not installed\n' >&2
  exit 2
fi

cd "$ROOT/apps/desktop"
"$FLUTTER" build linux --debug --no-pub \
  -t lib/bootstrap/texture_bench.dart >/dev/null

exec timeout --signal=TERM --kill-after=5s 45s \
  "$APP" "$@"
