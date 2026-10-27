#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
source_dir="$repo/.build/audio.cpp"
commit=bdf78b9140d091949b20311bcf7ecad3698e53fe
mkdir -p "$repo/.build/tmp"
export TMPDIR="$repo/.build/tmp"
export CLANG_MODULE_CACHE_PATH="$repo/.build/clang-cache"
if [[ ! -d "$source_dir/.git" ]]; then
  git init "$source_dir"
  git -C "$source_dir" remote add origin https://github.com/0xShug0/audio.cpp.git
fi
git -C "$source_dir" fetch --depth 1 origin "$commit"
git -C "$source_dir" checkout --detach FETCH_HEAD
git -C "$source_dir" submodule update --init --recursive --depth 1
cd "$source_dir"
bash scripts/build_metal.sh --build-dir build/macos-portable-release --build-type Release --archs arm64 --deployment-target 14.0 --native-cpu OFF --model-set custom --models ming3_tts --deployment-build --target audiocpp_cli --jobs "${BUILD_JOBS:-8}"
