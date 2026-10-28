#!/usr/bin/env bash
set -euo pipefail
[[ "$(uname -s)" == Linux ]] || { echo 'Build this engine on Linux.' >&2; exit 1; }
repo="$(cd "$(dirname "$0")/../.." && pwd)"
source_dir="${LINUX_ENGINE_SOURCE:-$repo/.build/linux-audio.cpp}"
commit=bdf78b9140d091949b20311bcf7ecad3698e53fe
backend="${RAVEN_BUILD_BACKEND:-cpu}"
case "$backend" in cpu|cuda|vulkan|hip) ;; *) echo 'Invalid backend' >&2; exit 2;; esac
mkdir -p "$repo/.build/tmp"
export TMPDIR="$repo/.build/tmp"
if [[ ! -d "$source_dir/.git" ]]; then
  git init "$source_dir"
  git -C "$source_dir" remote add origin https://github.com/0xShug0/audio.cpp.git
fi
git -C "$source_dir" fetch --depth 1 origin "$commit"
git -C "$source_dir" checkout --detach FETCH_HEAD
git -C "$source_dir" submodule update --init --recursive --depth 1
cd "$source_dir"
bash scripts/build_linux.sh --backend "$backend" --build-dir build/raven-linux --build-type Release --native-cpu OFF --model-set custom --models ming3_tts --deployment-build --target audiocpp_cli --jobs "${BUILD_JOBS:-2}"
