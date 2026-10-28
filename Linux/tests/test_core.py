import hashlib
import http.server
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest

import numpy as np
import soundfile as sf

from raven_vo.audio import envelope, prepare_sample
from raven_vo.core import Store, atomic_json, download_model, generation_args, trash_take

ROOT = Path(os.environ.get("RAVEN_TEST_ROOT", Path(__file__).resolve().parents[2] / ".build/linux-tests"))
ROOT.mkdir(parents=True, exist_ok=True)


class CoreChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=ROOT)
        self.root = Path(self.temp.name)
        self.store = Store.choose(self.root)

    def tearDown(self):
        self.temp.cleanup()

    def test_storage_identity_missing_volume_no_fallback(self):
        marker = self.root / ".raven-vo-storage-id"
        marker.unlink()
        with self.assertRaisesRegex(ValueError, "Reconnect"):
            self.store.path("models/fake")
        self.assertFalse(marker.exists())

    def test_safe_paths_and_atomic_settings(self):
        with self.assertRaisesRegex(ValueError, "outside"):
            self.store.path("../outside")
        atomic_json(self.root / "app-data/test.json", {"voice": "American James"})
        self.assertEqual(json.loads((self.root / "app-data/test.json").read_text())["voice"], "American James")
        self.assertFalse(list((self.root / "app-data").glob(".test.json.*")))

    def test_generation_modes_and_reference_validation(self):
        draft = {"script": "Hi $(not-a-shell-command)", "language": "en", "voice": "US_James"}
        args = generation_args(self.store, draft)
        self.assertIn("voice_id=US_James", args)
        self.assertIn(draft["script"], args)
        self.assertEqual(args[args.index("--backend") + 1], "cpu")
        draft.update(voice="designed", style="A thoughtful narrator")
        self.assertIn("vdes", generation_args(self.store, draft))
        draft.update(voice="reference", referenceFile="../wrong.wav")
        with self.assertRaises(ValueError):
            generation_args(self.store, draft)
        reference = self.root / "voice-references/own.wav"
        reference.write_bytes(b"fixture")
        draft.update(referenceFile="own.wav", language="ja", referenceTranscript="A test")
        args = generation_args(self.store, draft)
        self.assertIn("clon", args)
        self.assertIn("text_chunk_size=40", args)
        self.assertIn("reference_text=A test", args)

    def test_trash_pairing_and_rollback(self):
        audio = self.root / "samples/one.wav"
        audio.write_bytes(b"wav")
        audio.with_suffix(".json").write_text("{}")
        def failed(_):
            raise OSError("Simulated Trash failure")
        with self.assertRaises(OSError):
            trash_take(audio, audio.parent, failed)
        self.assertTrue(audio.exists() and audio.with_suffix(".json").exists())
        captured = []
        def fake_trash(path):
            bundle = Path(path)
            captured.extend(sorted(p.name for p in bundle.iterdir()))
        trash_take(audio, audio.parent, fake_trash)
        self.assertEqual(captured, ["one.json", "one.wav"])
        self.assertFalse(audio.exists())

    def test_cleanup_helper_and_raw_preservation(self):
        helper = os.environ.get("RAVEN_TEST_DENOISER")
        if not helper:
            self.skipTest("Set RAVEN_TEST_DENOISER to validate the native cleanup helper")
        rate = 48000
        source = self.root / "noisy.wav"
        generator = np.random.default_rng(42)
        samples = generator.normal(0, 0.025, rate * 4).astype(np.float32)
        sf.write(source, samples, rate)
        profile = prepare_sample(source, self.root / "voice-references", Path(helper), cleanup=True)
        self.assertTrue(profile["cleanupApplied"])
        output = self.root / "voice-references" / profile["fileName"]
        cleaned, output_rate = sf.read(output)
        self.assertEqual(output_rate, 24000)
        self.assertLess(abs(len(cleaned) / output_rate - 4), 0.02)
        self.assertLess(float(np.sqrt(np.mean(cleaned ** 2))), 0.015)
        self.assertTrue((self.root / "voice-references" / profile["rawFileName"]).exists())

    def test_audio_prepare_waveform_and_silence(self):
        rate = 24000
        source = self.root / "input.wav"
        samples = np.sin(np.arange(rate * 4) * 2 * np.pi * 220 / rate).astype(np.float32) * 0.2
        sf.write(source, samples, rate, subtype="FLOAT")
        profile = prepare_sample(source, self.root / "voice-references", None)
        self.assertAlmostEqual(profile["duration"], 4, places=2)
        copy = self.root / "voice-references" / profile["originalFileName"]
        self.assertEqual(copy.read_bytes(), source.read_bytes())
        values = envelope(source)
        self.assertEqual(len(values), 640)
        self.assertTrue(all(0 < value <= 1 for value in values))
        sf.write(source, np.zeros(rate * 4), rate)
        with self.assertRaisesRegex(ValueError, "silent"):
            prepare_sample(source, self.root / "voice-references", None)


class DownloadChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = b"raven-model-fixture-" * 1024
        cls.mode = "range"
        outer = cls
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                offset = int(self.headers.get("Range", "bytes=0-").split("=")[1].split("-")[0])
                if outer.mode == "ignore":
                    offset = 0
                self.send_response(206 if offset else 200)
                if offset:
                    self.send_header("Content-Range", f"bytes {offset}-{len(outer.data)-1}/{len(outer.data)}")
                self.send_header("Content-Length", str(len(outer.data) - offset))
                self.end_headers()
                self.wfile.write(outer.data[offset:])
            def log_message(self, *_):
                pass
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown(); cls.server.server_close(); cls.thread.join()

    def test_download_resume_ignored_range_checksum_and_preservation(self):
        with tempfile.TemporaryDirectory(dir=ROOT) as name:
            root = Path(name)
            sha = hashlib.sha256(self.data).hexdigest()
            url = f"http://127.0.0.1:{self.server.server_port}/fixture"
            for mode in ("range", "ignore"):
                self.__class__.mode = mode
                target = root / (mode + ".gguf")
                target.with_suffix(".gguf.partial").write_bytes(self.data[:111])
                download_model(target, url=url, size=len(self.data), sha=sha)
                self.assertEqual(target.read_bytes(), self.data)
            bad = root / "existing.gguf"
            bad.write_bytes(b"unique original")
            with self.assertRaisesRegex(ValueError, "preserved"):
                download_model(bad, url=url, size=len(self.data), sha=sha)
            self.assertEqual(bad.read_bytes(), b"unique original")
            with self.assertRaisesRegex(ValueError, "checksum"):
                download_model(root / "checksum.gguf", url=url, size=len(self.data), sha="0" * 64)
            self.assertFalse((root / "checksum.gguf").exists())


if __name__ == "__main__":
    unittest.main()
