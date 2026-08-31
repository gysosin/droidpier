#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="${DROIDPIER_RUNTIME_WORK:-$root/.tools/droidpier-runtime}"
source_archive="$(python3 "$root/tool/fetch_runtime.py" ffmpeg-source)"
mkdir -p "$work/source" "$work/ffmpeg"
if [[ ! -f "$work/source/ffmpeg-8.1.2/configure" ]]; then
  tar -C "$work/source" -xf "$source_archive"
fi
cd "$work/ffmpeg"
configuration=(
  --prefix="$work/ffmpeg/install" --disable-shared --enable-static
  --disable-autodetect --disable-doc --disable-debug --disable-ffplay --disable-ffprobe
  --disable-everything --disable-network --disable-x86asm
  --enable-ffmpeg --enable-avcodec --enable-avformat --enable-avfilter
  --enable-swscale --enable-swresample --enable-protocol=file,pipe
  --enable-decoder=h264,rawvideo --enable-parser=h264
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
