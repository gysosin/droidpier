#!/usr/bin/env bash
set -euo pipefail
repository_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="${repository_dir}/.tools/droidpier-runtime/adb"
source_archive="$(python3 "${repository_dir}/tool/fetch_runtime.py" adb-source)"
source_dir="${work_dir}/android-tools-37.0.0"
mkdir -p "${work_dir}"
patch_hash="$(sha256sum < "${repository_dir}/tool/patches/android-tools-static-dependencies.patch")"
source_hash="$(sha256sum < "${source_archive}")"
patch_hash="${patch_hash}:${source_hash}"
if [[ ! -d "${source_dir}" || ! -f "${work_dir}/applied-patch.sha256" || "$(cat "${work_dir}/applied-patch.sha256")" != "${patch_hash}" ]]; then
  rm -rf "${source_dir}"
  tar -xf "${source_archive}" -C "${work_dir}"
  patch -d "${source_dir}" -p1 < "${repository_dir}/tool/patches/android-tools-static-dependencies.patch"
  printf '%s\n' "${patch_hash}" > "${work_dir}/applied-patch.sha256"
fi
dpkg-query -W -f='${binary:Package}\t${source:Package}\t${source:Version}\n' \
  libprotobuf-dev libbrotli-dev liblz4-dev libzstd-dev zlib1g-dev libgtest-dev \
  > "${work_dir}/system-build-inputs.tsv"
if ! cmp -s "${repository_dir}/tool/adb-build-inputs.tsv" "${work_dir}/system-build-inputs.tsv"; then
  echo 'ADB build inputs differ from the reviewed corresponding sources' >&2
  diff -u "${repository_dir}/tool/adb-build-inputs.tsv" "${work_dir}/system-build-inputs.tsv" >&2 || true
  exit 1
fi
cat > "${work_dir}/protoc-with-optionals" <<'SH'
#!/bin/sh
exec protoc --experimental_allow_proto3_optional "$@"
SH
chmod 755 "${work_dir}/protoc-with-optionals"
cmake -S "${source_dir}" -B "${work_dir}/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DANDROID_TOOLS_PATCH_VENDOR=OFF \
  -DANDROID_TOOLS_USE_BUNDLED_FMT=ON \
  -DANDROID_TOOLS_USE_BUNDLED_LIBUSB=ON \
  -DANDROID_TOOLS_LIBUSB_ENABLE_UDEV=OFF \
  -DProtobuf_USE_STATIC_LIBS=ON \
  -DProtobuf_PROTOC_EXECUTABLE="${work_dir}/protoc-with-optionals"
cmake --build "${work_dir}/build" --target adb --parallel "${BUILD_JOBS:-4}"
mkdir -p "${work_dir}/install/bin"
install -m755 "${work_dir}/build/vendor/adb" "${work_dir}/install/bin/adb"
"${work_dir}/install/bin/adb" version
ldd "${work_dir}/install/bin/adb" > "${work_dir}/linkage.txt"
if grep -Eq 'lib(usb|protobuf|brotli|lz4|zstd|z\.so)' "${work_dir}/linkage.txt"; then
  echo 'ADB unexpectedly depends on an unbundled external library' >&2
  exit 1
fi
