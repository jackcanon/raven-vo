"""Isolated GUI acceptance. No microphone capture or audible playback is started."""
import json
import os
from pathlib import Path
import tempfile
import time

import numpy as np
import soundfile as sf
from PySide6.QtWidgets import QApplication
from raven_vo.app import Window

root = Path(os.environ.get("RAVEN_TEST_ROOT", Path(__file__).resolve().parents[2] / ".build/linux-tests"))
root.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(dir=root) as temp:
    folder = Path(temp)
    os.environ["RAVEN_VO_CONFIG"] = str(folder / "config.json")
    # app.py was already imported, so explicitly isolate its configuration constant.
    import raven_vo.app as module
    module.CONFIG = folder / "config.json"
    app = QApplication.instance() or QApplication([])
    app.setStyle("Fusion")
    window = Window()
    window.show()
    def wait_until(predicate, timeout=10):
        start = time.monotonic()
        while not predicate():
            app.processEvents()
            time.sleep(0.01)
            if time.monotonic() - start > timeout:
                raise AssertionError("Timed out: " + window.status.text())
    seen = []
    window.jobs.progress.connect(lambda count, total, text: seen.append((count, total)))
    window.jobs.signals.progress.emit(2_998_284_288, 2_998_284_288, "Large model progress test")
    app.processEvents()
    assert seen[-1] == (2_998_284_288, 2_998_284_288)
    window.choose_storage_path(folder)
    wait_until(lambda: not window.jobs.pending and window.store is not None)
    assert window.preset.count() == 4
    window.language.setCurrentIndex(window.language.findData("zh"))
    assert window.preset.count() == 239
    window.custom.setChecked(True)
    assert not window.preset.isEnabled()
    window.own.setChecked(True)
    assert not window.custom.isChecked()
    window.language.setCurrentIndex(window.language.findData("en"))
    window.microphone.addItem("Missing microphone fixture", "missing-device")
    window.microphone.setCurrentIndex(window.microphone.findData("missing-device"))
    window.start_capture(True)
    assert not window.recording and "unavailable" in window.status.text()
    window.microphone.setCurrentIndex(0)
    window.script.setPlainText("This draft is preserved.")
    window.title.setText("Linux UI acceptance")
    window.save_draft()
    wav = folder / "samples/test.wav"
    signal = np.sin(np.arange(24000 * 4) * 2 * np.pi * 220 / 24000) * 0.2
    sf.write(wav, signal, 24000)
    window.load_audio(wav, "Waveform acceptance")
    wait_until(lambda: len(window.waveform.peaks) == 640)
    window.player.setPosition(1500)
    assert window.play.accessibleName() == "Play or pause audio"
    assert window.position.accessibleName() == "Playback position"
    assert window.microphone.accessibleName() == "Microphone"
    window.resize(1100, 800)
    app.processEvents()
    window.grab().save(str(root / "linux-ui-smoke.png"))
    window.close()
    wait_until(lambda: window.real_close and not window.isVisible())
    data = json.loads((folder / "app-data/linux-draft.json").read_text())
    assert data["script"] == "This draft is preserved."
print("LINUX_UI_SMOKE_PASSED: languages, separate modes, explicit missing-input rejection, async waveform, accessible transport, draft save and graceful flush")
