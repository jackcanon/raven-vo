from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import ssl
import threading
import time
import urllib.request
import uuid
from pathlib import Path

MODEL_NAME = "ming-3.0-tts-0.5b-bf16.gguf"
MODEL_SIZE = 2_998_284_288
MODEL_SHA = "43f108a4e6bb54af13071d0cb345a094e0b011b3b8318d8fb2c61753733f5312"
MODEL_URL = "https://huggingface.co/audio-cpp/Ming-3.0-TTS-0.5B-GGUF/resolve/2eb8d37c7f10672e69c8aa33091baa04c461b66c/" + MODEL_NAME
LANGUAGES = [("en", "English"), ("zh", "Chinese · 中文"), ("ja", "Japanese · 日本語"),
             ("ko", "Korean · 한국어"), ("de", "German · Deutsch"), ("fr", "French"), ("es", "Spanish")]
ENGLISH = [("US_James", "American James", "American · male"), ("US_Emma", "American Emma", "American · female"),
           ("UK_George", "British George", "British · male"), ("UK_Charlotte", "British Charlotte", "British · female")]
SAMPLES = {"en": "Every story deserves to be heard. Together, we create unforgettable moments.",
           "zh": "你好，每一个故事都值得被听见。让我们一起创造难忘的时刻。",
           "ja": "こんにちは。すべての物語には価値があります。忘れられない瞬間を一緒に作りましょう。",
           "ko": "안녕하세요. 모든 이야기는 소중합니다. 잊지 못할 순간을 함께 만들어 보세요.",
           "de": "Jede Geschichte verdient es, gehört zu werden. Gemeinsam schaffen wir unvergessliche Momente.",
           "fr": "Chaque histoire mérite d’être entendue. Ensemble, créons des moments inoubliables.",
           "es": "Cada historia merece ser escuchada. Juntos, creamos momentos inolvidables."}


def atomic_json(path: Path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name("." + path.name + "." + uuid.uuid4().hex)
    try:
        with temp.open("x", encoding="utf-8") as f:
            json.dump(value, f, ensure_ascii=False, indent=2)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


def read_json(path: Path, fallback=None):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return fallback


class Store:
    """Require the selected folder's identity marker; never recreate a missing volume."""
    def __init__(self, root: Path, identity: str):
        self.root, self.identity = root, identity

    @classmethod
    def choose(cls, folder: Path):
        root = folder.expanduser().resolve(strict=True)
        if not root.is_dir():
            raise ValueError("Choose an existing storage folder.")
        marker = root / ".raven-vo-storage-id"
        if not marker.exists():
            marker.write_text(str(uuid.uuid4()), encoding="utf-8")
        identity = marker.read_text(encoding="utf-8").strip()
        if not identity:
            raise ValueError("The storage identity marker is invalid. Choose another folder.")
        store = cls(root, identity)
        store.check()
        for name in ("models", "samples", "app-data", "voice-references", "runs", "tmp"):
            (root / name).mkdir(exist_ok=True)
        return store

    def check(self):
        try:
            valid = (self.root / ".raven-vo-storage-id").read_text(encoding="utf-8").strip() == self.identity
        except OSError:
            valid = False
        if not valid:
            raise ValueError("Reconnect the selected storage folder or choose another folder. No fallback storage was used.")

    def path(self, relative: str):
        self.check()
        target = self.root / relative
        if not target.resolve().is_relative_to(self.root.resolve()):
            raise ValueError("The file is outside the selected storage folder.")
        return target

    @property
    def model(self):
        return self.path("models/" + MODEL_NAME)


def checksum(path: Path, cancel=None):
    h = hashlib.sha256()
    with path.open("rb") as f:
        while block := f.read(1024 * 1024):
            if cancel and cancel.is_set():
                raise InterruptedError("Cancelled; any partial download was kept.")
            h.update(block)
    return h.hexdigest()


def download_model(destination: Path, progress=lambda *_: None, cancel=None, *, url=MODEL_URL, size=MODEL_SIZE, sha=MODEL_SHA):
    cancel = cancel or threading.Event()
    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_suffix(destination.suffix + ".partial")
    if destination.is_symlink() or partial.is_symlink():
        raise ValueError("Choose a model path without symbolic links.")
    if destination.exists():
        progress(0, size, "Verifying installed model…")
        if destination.stat().st_size != size or checksum(destination, cancel) != sha:
            raise ValueError("The existing model failed verification and was preserved. Choose another storage folder.")
        return destination
    offset = partial.stat().st_size if partial.exists() else 0
    if offset > size:
        raise ValueError("The partial download is larger than expected. Choose another folder.")
    if offset < size:
        headers = {"Accept-Encoding": "identity", "User-Agent": "RavenVO-Linux/0.5-preview"}
        if offset:
            headers["Range"] = f"bytes={offset}-"
        # A frozen Python must use the target distribution's trust store, not
        # an absolute certificate path from the CI machine's Python build.
        system_ca = Path("/etc/ssl/certs/ca-certificates.crt")
        context = ssl.create_default_context(cafile=str(system_ca) if system_ca.is_file() else None)
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=30, context=context) as response:
            if response.status == 206:
                match = re.fullmatch(r"bytes (\d+)-(\d+)/(\d+)", response.headers.get("Content-Range", ""))
                if not match or int(match[1]) != offset or int(match[3]) != size:
                    raise ValueError("The download server returned an invalid resume range.")
            elif response.status == 200:
                offset = 0  # The host ignored Range; restart the partial file safely.
            else:
                raise ValueError(f"Download returned HTTP {response.status}.")
            with partial.open("ab" if offset else "wb") as f:
                while block := response.read(1024 * 1024):
                    if cancel.is_set():
                        raise InterruptedError("Download cancelled. Resume it to continue.")
                    offset += len(block)
                    if offset > size:
                        raise ValueError("The download is larger than expected.")
                    f.write(block)
                    progress(offset, size, "Downloading Ming 0.5B…")
    progress(size, size, "Verifying SHA-256…")
    if partial.stat().st_size != size or checksum(partial, cancel) != sha:
        raise ValueError("The model checksum did not match. The partial file was kept; no model was installed.")
    if destination.exists():
        raise ValueError("A model appeared at the destination; it was not replaced.")
    partial.rename(destination)
    return destination


def generation_args(store: Store, draft: dict, backend="cpu"):
    if backend not in {"cpu", "metal", "cuda", "vulkan", "hip"}:
        raise ValueError("Unsupported engine backend.")
    script = draft.get("script", "").strip()
    language = draft.get("language") or "en"
    voice = draft.get("voice", "US_James")
    if not script or len(script) > 20000:
        raise ValueError("Enter a script of 1–20,000 characters.")
    if language not in dict(LANGUAGES):
        raise ValueError("Choose a supported language.")
    task = "vdes" if voice == "designed" else "clon" if voice == "reference" else "tts"
    args = ["--family", "ming3_tts", "--task", task, "--backend", backend, "--model", str(store.model),
            "--text", script, "--request-option", f"language={language}", "--threads", str(min(8, os.cpu_count() or 2)), "--metrics", "--log"]
    if voice == "designed":
        if not draft.get("style", "").strip():
            raise ValueError("Describe the Custom Voice you want.")
        args += ["--request-option", "instruct=" + draft["style"]]
    elif voice == "reference":
        name = draft.get("referenceFile", "")
        if not name or Path(name).name != name or not name.endswith(".wav"):
            raise ValueError("Record or import your voice sample first.")
        reference = store.path("voice-references/" + name)
        if not reference.is_file():
            raise ValueError("The saved voice sample is unavailable.")
        args += ["--voice-ref", str(reference), "--request-option", "text_chunk_size=" + ("40" if language in {"zh", "ja", "ko"} else "100")]
        if draft.get("referenceTranscript", "").strip():
            args += ["--request-option", "reference_text=" + draft["referenceTranscript"].strip()]
    elif voice == "natural":
        args += ["--request-option", "template_name=multilingual"]
    else:
        args += ["--request-option", "template_name=ip", "--request-option", "voice_id=" + voice]
    return args


def trash_take(audio: Path, folder: Path, trash=None):
    from send2trash import send2trash
    trash = trash or send2trash
    if audio.is_symlink() or audio.parent.resolve() != folder.resolve() or audio.suffix.lower() != ".wav":
        raise ValueError("Only a take in the recordings folder can be deleted.")
    files = [audio]
    metadata = audio.with_suffix(".json")
    if metadata.exists():
        if metadata.is_symlink():
            raise ValueError("The take metadata is a symbolic link.")
        files.append(metadata)
    # Trash a single recovery folder, avoiding a half-deleted audio/metadata pair.
    bundle = folder / ("Raven-VO-deleted-" + uuid.uuid4().hex)
    bundle.mkdir()
    moved = []
    try:
        for path in files:
            path.rename(bundle / path.name)
            moved.append(path)
        trash(str(bundle))
    except Exception:
        for path in reversed(moved):
            saved = bundle / path.name
            if saved.exists() and not path.exists():
                saved.rename(path)
        if bundle.exists() and not list(bundle.iterdir()):
            bundle.rmdir()
        raise
    return True
