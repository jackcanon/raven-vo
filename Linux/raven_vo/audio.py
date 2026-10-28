from __future__ import annotations

import math
import subprocess
import shutil
import tempfile
import uuid
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly


def envelope(path: Path, bins=640):
    with sf.SoundFile(path) as file:
        if not len(file):
            return []
        count = min(bins, len(file))
        peaks = np.zeros(count, dtype=np.float32)
        offset = 0
        for block in file.blocks(blocksize=8192, dtype="float32", always_2d=True):
            values = np.max(np.abs(block), axis=1)
            buckets = ((np.arange(len(block)) + offset) * count // len(file)).astype(np.int64)
            np.maximum.at(peaks, buckets, np.clip(np.nan_to_num(values), 0, 1))
            offset += len(block)
        return peaks.tolist()


def quality(samples, rate, room_tone=False):
    peak = float(np.max(np.abs(samples)))
    rms = float(np.sqrt(np.mean(np.square(samples, dtype=np.float64))))
    window = samples[:max(1, int(1.5 * rate))] if room_tone else samples
    noise = float(np.sqrt(np.mean(np.square(window, dtype=np.float64))))
    db = lambda value: 20 * math.log10(max(value, 1e-8))
    clipped = float(np.mean(np.abs(samples) >= 0.999) * 100)
    return {"peakDBFS": db(peak), "rmsDBFS": db(rms), "noiseDBFS": db(noise), "clippedPercent": clipped,
            "guidance": "Lower microphone gain and record again; clipping cannot be repaired." if clipped > 0.1 else
            "Raise microphone gain or move closer and record again." if db(rms) < -35 else
            "Recording level looks usable. Compare the original and cleaned audio by ear."}


def prepare_sample(source: Path, folder: Path, helper: Path | None, cleanup=False, mic_check=False):
    info = sf.info(source)
    if not 2.98 <= info.duration <= 15.02:
        raise ValueError("Use a recording between 3 and 15 seconds long.")
    samples, rate = sf.read(source, dtype="float32", always_2d=True)
    samples = samples.mean(axis=1)
    if not np.isfinite(samples).all():
        raise ValueError("The recording contains invalid audio samples.")
    if np.max(np.abs(samples)) <= 0.0001:
        raise ValueError("This sample is silent or too quiet. Check the selected microphone and input gain.")
    folder.mkdir(parents=True, exist_ok=True)
    token = uuid.uuid4().hex
    raw = folder / ("Voice-Raw-" + token + ".wav")
    original = folder / ("Voice-Source-" + token + source.suffix)
    shutil.copy2(source, original)
    # This audition copy preserves rate and level while normalizing to mono.
    sf.write(raw, samples, rate, subtype="FLOAT")
    report = quality(samples, rate, room_tone=mic_check)
    prepared = samples
    if cleanup or mic_check:
        if not helper or not helper.is_file():
            raise ValueError("The RNNoise helper is missing. The raw sample was preserved; reinstall the application.")
        divisor = math.gcd(rate, 48000)
        high = resample_poly(samples, 48000 // divisor, rate // divisor)
        pcm = np.clip(np.rint(high * 32768), -32768, 32767).astype("<i2")
        with tempfile.TemporaryDirectory(prefix="raven-cleanup-", dir=folder) as temp:
            src, dest = Path(temp) / "input.pcm", Path(temp) / "output.pcm"
            src.write_bytes(pcm.tobytes())
            subprocess.run([str(helper), str(src), str(dest)], check=True, timeout=60, capture_output=True,
                           creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            result = np.frombuffer(dest.read_bytes(), dtype="<i2")
            if len(result) != len(pcm):
                raise ValueError("Cleanup returned an incomplete recording; the raw sample was preserved.")
            prepared = result.astype(np.float32) / 32768
            rate = 48000
    divisor = math.gcd(rate, 24000)
    prepared = resample_poly(prepared, 24000 // divisor, rate // divisor)
    output = folder / ("Voice-Clean-" + token + ".wav" if cleanup or mic_check else "Voice-Sample-" + token + ".wav")
    sf.write(output, prepared, 24000, subtype="PCM_16")
    return {"fileName": output.name, "rawFileName": raw.name, "duration": len(prepared) / 24000,
            "cleanupApplied": cleanup or mic_check, "originalFileName": original.name, "quality": report, "transcript": ""}
