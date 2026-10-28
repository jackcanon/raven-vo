"""Retain upstream notices plus clear corresponding-source locations for Qt/FFmpeg."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import sys
import tarfile
import urllib.request

root = Path(sys.argv[1])
sources = {
    name: f"https://download.qt.io/archive/qt/6.8/6.8.3/submodules/{name}-everywhere-src-6.8.3.tar.xz"
    for name in ["qtbase", "qtmultimedia", "qtimageformats", "qtsvg"]
}
sources["pyside6"] = "https://download.qt.io/official_releases/QtForPython/pyside6/PySide6-6.8.3-src/pyside-setup-everywhere-src-6.8.3.tar.xz"
sources["ffmpeg"] = "https://ffmpeg.org/releases/ffmpeg-7.1.tar.xz"


def collect(pair):
    name, url = pair
    count = 0
    with urllib.request.urlopen(url, timeout=90) as response, tarfile.open(fileobj=response, mode="r|xz") as archive:
        for member in archive:
            path = Path(member.name)
            if path.is_absolute() or ".." in path.parts:
                raise ValueError("Unsafe upstream archive member")
            base = path.name.lower()
            if member.isfile() and (any(base.startswith(token) for token in ["license", "copying", "notice", "copyright", "authors"]) or "LICENSES" in path.parts or base == "qt_attribution.json"):
                if member.size > 4 * 1024 * 1024:
                    raise ValueError("Unexpectedly large notice file")
                target = root / name / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.extractfile(member).read())
                count += 1
    if not count:
        raise ValueError("No licence notices found for " + name)
    return name, count

root.mkdir(parents=True, exist_ok=True)
with ThreadPoolExecutor(max_workers=3) as pool:
    for name, count in pool.map(collect, sources.items()):
        print("Upstream notices", name, count)
(root / "CORRESPONDING-SOURCES.md").write_text(
    "# Corresponding upstream sources\n\n" + "\n".join(f"- {name}: {url}" for name, url in sources.items()) +
    "\n\nUnmodified Qt/PySide libraries are dynamically linked and replaceable. The application source, dependency versions and build instructions accompany this package. "
    "This package uses the LGPL option. No restriction on reverse engineering to debug LGPL modifications is imposed. "
    "For upstream build configurations and patch details, consult the exact PySide6 6.8.3 source release and Qt's FFmpeg build documentation.\n",
    encoding="utf-8")
