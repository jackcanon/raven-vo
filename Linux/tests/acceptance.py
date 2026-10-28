"""Actual pinned model + native engine inference, run on Linux CI."""
import os
from pathlib import Path
import subprocess
import time
import numpy as np
import soundfile as sf
from raven_vo.core import Store, download_model, generation_args

root = Path(os.environ["RAVEN_CI_MODEL_ROOT"])
root.mkdir(parents=True, exist_ok=True)
store = Store.choose(root)
last = [0]
def progress(count, total, message):
    if count - last[0] > 256 * 1024 * 1024 or count == total:
        print(message, count, "/", total, flush=True); last[0] = count
download_model(store.model, progress)
draft = {"script": "Hello. Raven voice over is running locally on Linux.", "voice": "US_James", "language": "en"}
args = generation_args(store, draft)
args[args.index("--threads") + 1] = "2"
output = store.path("samples/linux-real-inference.wav")
start = time.monotonic()
result = subprocess.run([os.environ["RAVEN_VO_ENGINE"], *args, "--out", str(output)], capture_output=True, text=True, timeout=600)
(root / "native-engine.log").write_text(result.stdout + result.stderr)
if result.returncode:
    print((result.stdout + result.stderr)[-10000:]); raise SystemExit(result.returncode)
samples, rate = sf.read(output)
assert len(samples) > 0 and np.isfinite(samples).all() and np.max(np.abs(samples)) > 0.00001
print("LINUX_NATIVE_INFERENCE_PASSED", "duration", len(samples) / rate, "wall_seconds", round(time.monotonic() - start, 2), flush=True)
