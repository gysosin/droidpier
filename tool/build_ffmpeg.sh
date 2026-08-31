#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="${DROIDPIER_RUNTIME_WORK:-$root/.tools/droidpier-runtime}"
# Invalidate old binaries when the recipe or pinned input changes. Previously
# an existing executable silently kept its old (unoptimized) configuration.
recipe_hash="$(cat "$root/tool/build_ffmpeg.sh" "$root/tool/runtime-lock.json" | sha256sum | cut -d ' ' -f 1)"
stamp="$work/ffmpeg/recipe.sha256"
if [[ -x "$work/ffmpeg/install/bin/ffmpeg" && -f "$stamp" && "$(cat "$stamp")" == "$recipe_hash" ]]; then
  exit 0
fi
if ! command -v nasm >/dev/null 2>&1; then
  echo 'FFmpeg requires NASM for optimized x86-64 video decoding. Install nasm or use tool/linux/Dockerfile.' >&2
  exit 1
fi
source_archive="$(python3 "$root/tool/fetch_runtime.py" ffmpeg-source)"
mkdir -p "$work/source" "$work/ffmpeg"
if [[ ! -f "$work/source/ffmpeg-8.1.2/configure" ]]; then
  tar -C "$work/source" -xf "$source_archive"
fi
cd "$work/ffmpeg"
configuration=(
  --prefix="$work/ffmpeg/install" --disable-shared --enable-static
  --disable-autodetect --disable-doc --disable-debug --disable-ffplay --disable-ffprobe
  --disable-everything --disable-network --disable-gpl --disable-nonfree
  --enable-x86asm
  --enable-ffmpeg --enable-avcodec --enable-avformat --enable-avfilter
  --enable-swscale --enable-swresample --enable-protocol=file,pipe
  --enable-decoder=h264,rawvideo,wrapped_avframe --enable-parser=h264
  --enable-demuxer=matroska,h264,rawvideo --enable-muxer=rawvideo
  --enable-encoder=rawvideo --enable-filter=scale,format,null,testsrc2,color
  --enable-indev=lavfi
)
printf '%q ' "${configuration[@]}" > configure-arguments.txt
printf '\n' >> configure-arguments.txt
"$work/source/ffmpeg-8.1.2/configure" "${configuration[@]}"
make -j "${DROIDPIER_BUILD_JOBS:-4}"
make install
"$work/ffmpeg/install/bin/ffmpeg" -version
printf '%s\n' "$recipe_hash" > "$stamp"
