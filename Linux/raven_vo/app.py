from __future__ import annotations

import json
import math
import os
import shutil
import sys
import threading
import time
import uuid
from pathlib import Path

import numpy as np
import soundfile as sf
from PySide6.QtCore import QProcess, QProcessEnvironment, QTimer, QUrl, Qt, Signal
from PySide6.QtGui import QColor, QDesktopServices, QIcon, QPainter, QPalette, QPen
from PySide6.QtMultimedia import QAudio, QAudioFormat, QAudioOutput, QAudioSource, QMediaDevices, QMediaPlayer
from PySide6.QtWidgets import (QApplication, QCheckBox, QComboBox, QFileDialog, QFormLayout, QGroupBox,
    QHBoxLayout, QLabel, QLineEdit, QListWidget, QListWidgetItem, QMainWindow, QMessageBox,
    QPlainTextEdit, QProgressBar, QPushButton, QScrollArea, QSlider, QSplitter, QVBoxLayout, QWidget)

from . import __version__
from .audio import envelope, prepare_sample
from .core import (ENGLISH, LANGUAGES, MODEL_SIZE, MODEL_SHA, SAMPLES, Store, atomic_json,
                   checksum, download_model, generation_args, read_json, trash_take)
from .jobs import Jobs, SettingsQueue

RESOURCE = Path(os.environ.get("RAVEN_VO_RESOURCES", Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent)) / "resources"))
SOURCE_ROOT = Path(__file__).resolve().parents[2]
PLATFORM = "Windows" if sys.platform == "win32" else "Linux"
EXE_SUFFIX = ".exe" if sys.platform == "win32" else ""
ENGINE = Path(os.environ.get("RAVEN_VO_ENGINE", RESOURCE / ("engine/audiocpp_cli" + EXE_SUFFIX)))
DENOISER = Path(os.environ.get("RAVEN_VO_DENOISER", RESOURCE / ("engine/raven-denoise" + EXE_SUFFIX)))
BACKEND = os.environ.get("RAVEN_VO_BACKEND", "cpu")
CONFIG_HOME = Path(os.environ.get("APPDATA", Path.home() / "AppData/Roaming")) if sys.platform == "win32" else Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
CONFIG = Path(os.environ.get("RAVEN_VO_CONFIG", CONFIG_HOME / "raven-vo/settings.json"))


def button(text, action, accessible=None):
    widget = QPushButton(text)
    widget.setAccessibleName(accessible or text)
    widget.clicked.connect(action)
    return widget


def clock(milliseconds):
    seconds = max(0, int(milliseconds / 1000))
    return f"{seconds // 60}:{seconds % 60:02d}"


class Waveform(QWidget):
    seek = Signal(float)
    def __init__(self):
        super().__init__()
        self.peaks, self.position, self.duration = [], 0, 0
        self.setMinimumHeight(66)
        self.setAccessibleName("Audio waveform; use the playback position slider to seek")

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        mid = self.height() / 2
        painter.setPen(QPen(QColor("#9a9a9a"), 1))
        painter.drawLine(0, int(mid), self.width(), int(mid))
        fraction = self.position / self.duration if self.duration else 0
        count = min(len(self.peaks), max(1, self.width() // 3))
        if count:
            stride = self.width() / count
            for index in range(count):
                first = index * len(self.peaks) // count
                last = max(first + 1, (index + 1) * len(self.peaks) // count)
                height = max(2, math.sqrt(max(self.peaks[first:last])) * (self.height() - 8))
                painter.setPen(QPen(QColor("#f4f4f4" if index / count < fraction else "#929292"), max(1, stride - 1)))
                painter.drawLine(int(index * stride), int(mid - height / 2), int(index * stride), int(mid + height / 2))
            painter.setPen(QPen(QColor("#ffffff"), 2))
            painter.drawLine(int(self.width() * fraction), 0, int(self.width() * fraction), self.height())

    def mousePressEvent(self, event):
        self._seek(event)

    def mouseMoveEvent(self, event):
        if event.buttons() & Qt.LeftButton:
            self._seek(event)

    def _seek(self, event):
        if self.duration and self.isEnabled():
            self.seek.emit(max(0, min(1, event.position().x() / max(1, self.width()))) * self.duration)


class Window(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle(f"Raven VO · {PLATFORM} Preview")
        icon = RESOURCE / "AppIcon.png"
        if not icon.exists():
            icon = SOURCE_ROOT / "Assets/AppIcon.png"
        self.setWindowIcon(QIcon(str(icon)))
        self.resize(1180, 860)
        self.store = None
        self.model_ready = False
        self.profile = None
        self.mic_check = None
        self._loading = True
        self.process = None
        self.recording = False
        self.capture = None
        self.player_path = None
        self.wave_request = 0
        self.real_close = False
        self.closing = False
        self.cancel_event = threading.Event()
        self.jobs = Jobs(self)
        self.wave_jobs = Jobs(self)
        self.saves = SettingsQueue(self)
        self.jobs.failed.connect(self.error)
        self.jobs.changed.connect(lambda _: self.update_enabled())
        self.jobs.progress.connect(self.download_progress)
        self.saves.failed.connect(self.error)
        self.saves.flushed.connect(self.close_after_save, Qt.QueuedConnection)
        self.wave_jobs.failed.connect(lambda message: self.status.setText("Waveform unavailable; playback controls are still available. " + message))
        self.player = QMediaPlayer(self)
        self.audio_output = QAudioOutput(self)
        self.player.setAudioOutput(self.audio_output)
        self.player.positionChanged.connect(self.position_changed)
        self.player.durationChanged.connect(self.duration_changed)
        self.player.playbackStateChanged.connect(lambda _: self.play.setText("Pause" if self.player.isPlaying() else "Play"))
        self.player.errorOccurred.connect(lambda *_: self.error("Playback failed: " + self.player.errorString()))
        self.autosave = QTimer(self)
        self.autosave.setSingleShot(True)
        self.autosave.setInterval(650)
        self.autosave.timeout.connect(self.save_draft)
        self.record_timer = QTimer(self)
        self.record_timer.setInterval(100)
        self.record_timer.timeout.connect(self.capture_tick)
        self.cancel_kill = QTimer(self)
        self.cancel_kill.setSingleShot(True)
        self.cancel_kill.timeout.connect(lambda: self.process.kill() if self.process else None)
        self.build_ui()
        self.devices = QMediaDevices(self)
        self.devices.audioInputsChanged.connect(self.refresh_inputs)
        self.refresh_inputs()
        self._loading = False
        config = read_json(CONFIG, {})
        self.config = config
        self.cleanup.setChecked(config.get("cleanup", False))
        self.restore_input(config.get("microphone", ""))
        if os.environ.get("RAVEN_VO_STORAGE"):
            self.choose_storage_path(Path(os.environ["RAVEN_VO_STORAGE"]))
        elif config.get("storage") and config.get("identity"):
            store = Store(Path(config["storage"]), config["identity"])
            self.load_store(store)
        self.update_enabled()

    def build_ui(self):
        host = QWidget()
        self.setCentralWidget(host)
        root = QHBoxLayout(host)
        self.takes = QListWidget()
        self.takes.setAccessibleName("Your takes")
        self.takes.currentItemChanged.connect(self.take_selected)
        sidebar = QWidget()
        left = QVBoxLayout(sidebar)
        left.addWidget(QLabel("Your takes"))
        left.addWidget(self.takes)
        self.delete = button("Delete take…", self.delete_take)
        left.addWidget(self.delete)
        left.addWidget(button("Open recordings folder", self.open_recordings))
        right = QWidget()
        column = QVBoxLayout(right)
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        content = QWidget()
        area = QVBoxLayout(content)
        area.addWidget(QLabel("<h2>Raven VO</h2>A voice for your story. Created on your computer."))
        area.addWidget(QLabel(f"Currently powered by Ming 0.5B · Local generation · {PLATFORM} CPU preview"))
        storage = QHBoxLayout()
        self.storage_label = QLabel("Choose where to store your model, takes and voice samples.")
        self.storage_label.setWordWrap(True)
        storage.addWidget(self.storage_label, 1)
        self.choose = button("Choose storage…", self.choose_storage)
        storage.addWidget(self.choose)
        self.download = button("Download / verify Ming", self.install_model)
        storage.addWidget(self.download)
        area.addLayout(storage)
        self.download_bar = QProgressBar()
        self.download_bar.setAccessibleName("Model download progress")
        self.download_bar.hide()
        area.addWidget(self.download_bar)
        setup = QHBoxLayout()
        options = QWidget()
        settings = QVBoxLayout(options)
        options.setMinimumWidth(270)
        options.setMaximumWidth(360)
        form = QFormLayout()
        self.language = QComboBox()
        for identifier, name in LANGUAGES:
            self.language.addItem(name, identifier)
        self.language.setAccessibleName("Language")
        self.language.currentIndexChanged.connect(self.language_changed)
        form.addRow("Language", self.language)
        self.preset = QComboBox()
        self.preset.setAccessibleName("Preset voice")
        self.preset.currentIndexChanged.connect(self.edited)
        form.addRow("Preset voice", self.preset)
        settings.addLayout(form)
        self.voice_detail = QLabel()
        self.voice_detail.setWordWrap(True)
        settings.addWidget(self.voice_detail)
        custom = QGroupBox("Custom Voice")
        custom_layout = QVBoxLayout(custom)
        self.custom = QCheckBox("Use custom voice")
        self.custom.toggled.connect(self.custom_changed)
        custom_layout.addWidget(self.custom)
        self.style = QPlainTextEdit()
        self.style.setAccessibleName("Custom voice description")
        self.style.setPlaceholderText("Describe the voice's accent, age, tone and pace.")
        self.style.setMaximumHeight(100)
        self.style.textChanged.connect(self.edited)
        custom_layout.addWidget(self.style)
        settings.addWidget(custom)
        own = QGroupBox("Your Voice")
        own_layout = QVBoxLayout(own)
        self.own = QCheckBox("Use your voice")
        self.own.toggled.connect(self.own_changed)
        own_layout.addWidget(self.own)
        explain = QLabel("Ming matches your voice from a short recording. No model training step is needed.")
        explain.setWordWrap(True)
        own_layout.addWidget(explain)
        self.voice_options = QWidget()
        vo = QVBoxLayout(self.voice_options)
        vo.setContentsMargins(0, 0, 0, 0)
        vo.addWidget(QLabel("Microphone"))
        self.microphone = QComboBox()
        self.microphone.setAccessibleName("Microphone")
        self.microphone.currentIndexChanged.connect(self.preferences_changed)
        vo.addWidget(self.microphone)
        self.refresh = button("Refresh microphones", self.refresh_inputs)
        vo.addWidget(self.refresh)
        self.meter = QProgressBar()
        self.meter.setRange(0, 100)
        self.meter.setAccessibleName("Microphone input level")
        vo.addWidget(self.meter)
        self.meter_note = QLabel("The input meter runs only during recording.")
        self.meter_note.setWordWrap(True)
        vo.addWidget(self.meter_note)
        self.check = button("1. Check microphone", lambda: self.start_capture(True))
        vo.addWidget(self.check)
        note = QLabel("Stay quiet for two seconds, then speak naturally. Recordings stop after 12 seconds.")
        note.setWordWrap(True)
        vo.addWidget(note)
        self.quality_note = QLabel()
        self.quality_note.setWordWrap(True)
        vo.addWidget(self.quality_note)
        row = QHBoxLayout()
        self.original_check = button("Original test", lambda: self.play_reference(self.mic_check, False, "Microphone check · Original test"))
        self.cleaned_check = button("Cleaned test", lambda: self.play_reference(self.mic_check, True, "Microphone check · Cleaned test"))
        row.addWidget(self.original_check); row.addWidget(self.cleaned_check)
        vo.addLayout(row)
        self.cleanup = QCheckBox("Clean up new samples")
        self.cleanup.toggled.connect(self.preferences_changed)
        vo.addWidget(self.cleanup)
        note = QLabel("RNNoise runs on the saved recording before cloning. The raw sample is kept. Use 3–15 seconds of your own voice.")
        note.setWordWrap(True)
        vo.addWidget(note)
        row = QHBoxLayout()
        self.record = button("2. Record sample", lambda: self.start_capture(False))
        self.stop_record = button("Stop recording", self.stop_capture)
        self.import_audio = button("Import…", self.import_sample)
        row.addWidget(self.record); row.addWidget(self.stop_record); row.addWidget(self.import_audio)
        vo.addLayout(row)
        self.listen = button("Listen to sample", lambda: self.play_reference(self.profile, True, "Your Voice · Sample"))
        vo.addWidget(self.listen)
        self.transcript = QPlainTextEdit()
        self.transcript.setMaximumHeight(85)
        self.transcript.setPlaceholderText("Exact words in the sample (optional)")
        self.transcript.setAccessibleName("Voice sample transcript, optional")
        self.transcript.textChanged.connect(self.edited)
        vo.addWidget(self.transcript)
        own_layout.addWidget(self.voice_options)
        settings.addWidget(own)
        settings.addStretch()
        setup.addWidget(options)
        script_box = QVBoxLayout()
        script_box.addWidget(QLabel("Script"))
        self.title = QLineEdit()
        self.title.setPlaceholderText("Take title")
        self.title.setAccessibleName("Take title")
        self.title.textChanged.connect(self.edited)
        script_box.addWidget(self.title)
        self.script = QPlainTextEdit()
        self.script.setPlaceholderText("Write the words to speak. The app does not translate them.")
        self.script.setAccessibleName("Voice-over script")
        self.script.setMinimumHeight(350)
        self.script.textChanged.connect(self.edited)
        script_box.addWidget(self.script, 1)
        self.characters = QLabel("0 characters")
        script_box.addWidget(self.characters)
        script_box.addWidget(button("Try a sample script", self.sample_script))
        setup.addLayout(script_box, 1)
        area.addLayout(setup)
        controls = QHBoxLayout()
        self.generate = button("Generate voice-over", self.generate_take)
        self.generate.setObjectName("primary")
        self.cancel = button("Cancel", self.cancel_work)
        controls.addWidget(self.generate); controls.addWidget(self.cancel); controls.addStretch()
        area.addLayout(controls)
        self.status = QLabel("Choose a storage folder to begin.")
        self.status.setWordWrap(True)
        self.status.setTextInteractionFlags(Qt.TextSelectableByMouse)
        area.addWidget(self.status)
        scroll.setWidget(content)
        column.addWidget(scroll, 1)
        player = QGroupBox("Listen")
        transport = QVBoxLayout(player)
        top = QHBoxLayout()
        self.now_playing = QLabel("Choose a take or audition a voice sample")
        top.addWidget(self.now_playing, 1)
        self.load_script = button("Load script", self.restore_take)
        self.export = button("Export WAV…", self.export_take)
        top.addWidget(self.load_script); top.addWidget(self.export)
        transport.addLayout(top)
        self.waveform = Waveform()
        self.waveform.seek.connect(lambda value: self.player.setPosition(int(value)))
        transport.addWidget(self.waveform)
        self.position = QSlider(Qt.Horizontal)
        self.position.setAccessibleName("Playback position")
        self.position.sliderMoved.connect(self.player.setPosition)
        self.position.valueChanged.connect(lambda value: self.player.setPosition(value) if self.position.hasFocus() else None)
        transport.addWidget(self.position)
        row = QHBoxLayout()
        self.elapsed = QLabel("0:00")
        self.remaining = QLabel("−0:00")
        row.addWidget(self.elapsed); row.addStretch()
        self.back = button("↶ 5s", lambda: self.player.setPosition(max(0, self.player.position() - 5000)), "Skip back five seconds")
        self.play = button("Play", self.play_pause, "Play or pause audio")
        self.forward = button("5s ↷", lambda: self.player.setPosition(min(self.player.duration(), self.player.position() + 5000)), "Skip forward five seconds")
        row.addWidget(self.back); row.addWidget(self.play); row.addWidget(self.forward); row.addStretch()
        row.addWidget(QLabel("Volume"))
        self.volume = QSlider(Qt.Horizontal)
        self.volume.setRange(0, 100); self.volume.setValue(100); self.volume.setMaximumWidth(110)
        self.volume.setAccessibleName("Playback volume")
        self.volume.valueChanged.connect(lambda value: self.audio_output.setVolume(value / 100))
        row.addWidget(self.volume); row.addWidget(self.remaining)
        transport.addLayout(row)
        column.addWidget(player)
        split = QSplitter()
        split.addWidget(sidebar); split.addWidget(right); split.setSizes([250, 930])
        root.addWidget(split)
        self.language_changed()

    def busy(self):
        return bool(self.jobs.pending or self.process or self.recording)

    def update_enabled(self):
        ready = self.store is not None
        busy = self.busy()
        for item in (self.choose, self.download, self.microphone, self.refresh, self.import_audio, self.check, self.record, self.custom, self.own, self.language, self.cleanup):
            item.setEnabled(not busy and (ready or item is self.choose))
        self.preset.setEnabled(not busy and not self.custom.isChecked() and not self.own.isChecked())
        self.generate.setEnabled(ready and self.model_ready and ENGINE.is_file() and not busy and bool(self.script.toPlainText().strip()))
        self.cancel.setEnabled(bool(self.process or self.download_bar.isVisible()))
        self.stop_record.setVisible(self.recording)
        self.stop_record.setEnabled(self.recording)
        self.record.setVisible(not self.recording)
        self.check.setVisible(not self.recording)
        self.style.setVisible(self.custom.isChecked())
        self.voice_options.setVisible(self.own.isChecked())
        self.original_check.setEnabled(bool(self.mic_check) and not busy)
        self.cleaned_check.setEnabled(bool(self.mic_check) and not busy)
        self.listen.setEnabled(bool(self.profile) and not busy)
        self.delete.setEnabled(bool(self.takes.currentItem()) and not busy)
        self.export.setEnabled(bool(self.takes.currentItem()) and not busy)
        self.load_script.setEnabled(bool(self.takes.currentItem()) and not busy)
        for control in (self.play, self.back, self.forward, self.position, self.waveform):
            control.setEnabled(self.player_path is not None and not self.recording)

    def edited(self, *_):
        if self._loading:
            return
        self.characters.setText(f"{len(self.script.toPlainText())} characters")
        self.autosave.start()
        self.update_enabled()

    def preferences_changed(self, *_):
        if self._loading or not hasattr(self, "config"):
            return
        self.config.update(cleanup=self.cleanup.isChecked(), microphone=self.microphone.currentData() or "")
        snapshot = dict(self.config)
        self.saves.submit(lambda: atomic_json(CONFIG, snapshot))

    def language_changed(self, *_):
        previous = self.preset.currentData()
        self.preset.blockSignals(True)
        self.preset.clear()
        language = self.language.currentData() or "en"
        voices = ENGLISH if language == "en" else [("natural", "Natural voice", "Automatic voice for this language")]
        if language == "zh":
            voices += read_json(Path(__file__).with_name("chinese_voices.json"), [])
        for identifier, name, detail in voices:
            self.preset.addItem(name, identifier)
            self.preset.setItemData(self.preset.count() - 1, detail, Qt.ToolTipRole)
        self.preset.setCurrentIndex(max(0, self.preset.findData(previous)))
        self.preset.blockSignals(False)
        self.edited()

    def custom_changed(self, active):
        if active:
            self.own.setChecked(False)
        self.edited()

    def own_changed(self, active):
        if active:
            self.custom.setChecked(False)
        self.edited()

    def draft(self):
        return {"title": self.title.text(), "script": self.script.toPlainText(), "language": self.language.currentData(),
                "voice": "designed" if self.custom.isChecked() else "reference" if self.own.isChecked() else self.preset.currentData(),
                "presetVoice": self.preset.currentData(), "style": self.style.toPlainText(),
                "referenceFile": self.profile["fileName"] if self.profile else None, "referenceTranscript": self.transcript.toPlainText()}

    def save_draft(self):
        if not self.store:
            return
        store, snapshot = self.store, self.draft()
        def save():
            path = store.path("app-data/linux-draft.json")
            atomic_json(path, snapshot)
        self.saves.submit(save)

    def apply_draft(self, draft):
        self._loading = True
        self.title.setText(draft.get("title", "My voice-over"))
        self.script.setPlainText(draft.get("script", ""))
        self.style.setPlainText(draft.get("style", "A warm, clear narrator with measured pacing."))
        self.language.setCurrentIndex(max(0, self.language.findData(draft.get("language") or "en")))
        self.language_changed()
        self.preset.setCurrentIndex(max(0, self.preset.findData(draft.get("presetVoice") or draft.get("voice"))))
        self.custom.setChecked(draft.get("voice") == "designed")
        self.own.setChecked(draft.get("voice") == "reference")
        self.transcript.setPlainText(draft.get("referenceTranscript") or "")
        self._loading = False
        self.edited()

    def choose_storage(self):
        folder = QFileDialog.getExistingDirectory(self, "Choose model and recording storage")
        if folder:
            self.choose_storage_path(Path(folder))

    def choose_storage_path(self, folder):
        self.jobs.run(lambda _: Store.choose(folder), self.load_store)

    def load_store(self, store):
        def read(_):
            store.check()
            return (read_json(store.path("app-data/linux-draft.json"), {}), read_json(store.path("app-data/linux-your-voice.json")), read_json(store.path("app-data/linux-mic-check.json")))
        def done(values):
            self.player.stop()
            self.player.setSource(QUrl())
            self.player_path = None
            self.wave_request += 1
            self.waveform.peaks = []
            self.waveform.update()
            self.store = store
            self.profile, self.mic_check = values[1:]
            self.config.update(storage=str(store.root), identity=store.identity)
            self.preferences_changed()
            self.storage_label.setText(str(store.root))
            self.model_ready = False
            self.apply_draft(values[0])
            self.reload_takes()
            self.status.setText("Download or verify Ming to enable generation.")
            self.update_quality()
            self.update_enabled()
        self.jobs.run(read, done)

    def install_model(self):
        if not self.store:
            return
        store = self.store
        self.cancel_event.clear()
        self.model_ready = False
        self.download_bar.show()
        self.jobs.run(lambda progress: download_model(store.model, progress, self.cancel_event), self.model_installed)

    def model_installed(self, path):
        self.model_ready = True
        self.download_bar.hide()
        self.status.setText("Ming verified and ready. Generation runs locally.")
        self.update_enabled()

    def download_progress(self, count, total, text):
        self.download_bar.setRange(0, 1000)
        self.download_bar.setValue(int(count / max(1, total) * 1000))
        self.status.setText(text)

    def sample_script(self):
        self.script.setPlainText(SAMPLES.get(self.language.currentData(), SAMPLES["en"]))
        if not self.title.text().strip():
            self.title.setText("Voice-over sample")

    def reload_takes(self, select=None):
        if not self.store:
            return
        store = self.store
        def scan(_):
            rows = []
            for path in store.path("samples").glob("*.wav"):
                if path.is_symlink():
                    continue
                info = read_json(path.with_suffix(".json"), {})
                rows.append((path, info, path.stat().st_mtime))
            return sorted(rows, key=lambda row: row[2], reverse=True)
        def done(rows):
            self.takes.clear()
            for path, info, _ in rows:
                item = QListWidgetItem(info.get("title") or path.stem)
                item.setData(Qt.UserRole, (path, info))
                item.setToolTip(f"{info.get('voice', 'Audio take')} · {info.get('language', 'en')}")
                self.takes.addItem(item)
                if select and path == select:
                    self.takes.setCurrentItem(item)
            self.update_enabled()
        self.jobs.run(scan, done)

    def take_selected(self, item, previous=None):
        if item:
            path, info = item.data(Qt.UserRole)
            self.load_audio(path, info.get("title") or path.stem)
        self.update_enabled()

    def load_audio(self, path, title, autoplay=False):
        if not self.store:
            return
        try:
            self.store.check()
            self.player.stop()
            self.player_path = path
            self.now_playing.setText(title)
            self.player.setSource(QUrl.fromLocalFile(str(path)))
            self.waveform.peaks = []
            self.waveform.update()
            self.wave_request += 1
            request = self.wave_request
            def done(values):
                if request == self.wave_request:
                    self.waveform.peaks = values
                    self.waveform.update()
            self.wave_jobs.run(lambda _: envelope(path), done)
            if autoplay:
                self.player.play()
            self.update_enabled()
        except Exception as error:
            self.error(str(error))

    def position_changed(self, value):
        self.position.blockSignals(True)
        self.position.setValue(value)
        self.position.blockSignals(False)
        self.elapsed.setText(clock(value))
        self.remaining.setText("−" + clock(max(0, self.player.duration() - value)))
        self.position.setAccessibleDescription(f"{clock(value)} of {clock(self.player.duration())}")
        self.waveform.position = value
        self.waveform.update()

    def duration_changed(self, value):
        self.position.setRange(0, max(0, value))
        self.waveform.duration = value
        self.position_changed(self.player.position())

    def play_pause(self):
        if self.recording:
            return
        if self.player.isPlaying():
            self.player.pause()
        else:
            if self.player.position() >= self.player.duration():
                self.player.setPosition(0)
            self.player.play()

    def restore_take(self):
        item = self.takes.currentItem()
        if not item:
            return
        _, info = item.data(Qt.UserRole)
        if not info.get("script"):
            self.error("This audio take has no saved script.")
            return
        name = info.get("referenceFile")
        if name and Path(name).name == name:
            self.profile = read_json(self.store.path("voice-references/" + name).with_suffix(".json"))
        self.apply_draft(info)

    def delete_take(self):
        item = self.takes.currentItem()
        if not item or not self.store:
            return
        path, info = item.data(Qt.UserRole)
        choice = QMessageBox.question(self, "Move take to Trash?", "Audio and its saved settings will be placed together in a recovery folder in Trash. Your script and voice samples are preserved.")
        if choice != QMessageBox.Yes:
            return
        self.player.stop()
        self.player.setSource(QUrl())
        self.player_path = None
        self.waveform.peaks = []
        self.waveform.update()
        store = self.store
        self.jobs.run(lambda _: trash_take(path, store.path("samples")), lambda _: self.reload_takes())

    def open_recordings(self):
        if self.store:
            try:
                QDesktopServices.openUrl(QUrl.fromLocalFile(str(self.store.path("samples"))))
            except Exception as error:
                self.error(str(error))

    def export_take(self):
        item = self.takes.currentItem()
        if not item:
            return
        path, _ = item.data(Qt.UserRole)
        target, _ = QFileDialog.getSaveFileName(self, "Export WAV", path.name, "WAV audio (*.wav)")
        if target and Path(target).resolve() != path.resolve():
            self.jobs.run(lambda _: shutil.copy2(path, target), lambda _: self.status.setText("WAV exported."))

    def generate_take(self):
        if not self.store or not self.model_ready or self.busy():
            return
        try:
            draft = self.draft()
            args = generation_args(self.store, draft, BACKEND)
            run = self.store.path("runs/" + uuid.uuid4().hex)
            # A generation run is a unique, small directory; setup occurs on a worker.
            def prepare(_):
                run.mkdir()
                return run
            self.jobs.run(prepare, lambda _: self.start_engine(run, draft, args))
        except Exception as error:
            self.error(str(error))

    def start_engine(self, run, draft, args):
        self.player.stop()
        self.save_draft()
        process = QProcess(self)
        self.process = process
        self.run_log = ""
        self.generation_cancelled = False
        process.setProgram(str(ENGINE))
        process.setArguments(args + ["--out", str(run / "output.wav")])
        process.setWorkingDirectory(str(self.store.root))
        environment = QProcessEnvironment.systemEnvironment()
        environment.insert("TMPDIR", str(self.store.path("tmp")))
        process.setProcessEnvironment(environment)
        process.setProcessChannelMode(QProcess.MergedChannels)
        process.readyReadStandardOutput.connect(self.engine_output)
        process.finished.connect(lambda code, status: self.engine_finished(run, draft, code))
        process.errorOccurred.connect(lambda error: self.engine_failed(process.errorString()) if error == QProcess.FailedToStart else None)
        self.status.setText("Generating locally on CPU… Timing depends on your computer.")
        process.start()
        self.update_enabled()

    def engine_output(self):
        if self.process:
            self.run_log = (self.run_log + bytes(self.process.readAllStandardOutput()).decode("utf-8", "replace"))[-1_000_000:]

    def engine_failed(self, message):
        self.process = None
        self.error("The engine could not start: " + message)
        self.update_enabled()

    def engine_finished(self, run, draft, code):
        self.cancel_kill.stop()
        self.engine_output()
        self.process = None
        store, log = self.store, self.run_log
        def save(_):
            store.check()
            (run / "generation.log").write_text(log, encoding="utf-8")
            if self.generation_cancelled:
                return None
            if code:
                raise ValueError(f"Ming stopped with code {code}. Engine log: {run / 'generation.log'}")
            info = sf.info(run / "output.wav")
            if info.frames <= 0:
                raise ValueError("The engine returned empty audio.")
            name = "Take-" + time.strftime("%Y-%m-%d-%H-%M-%S") + "-" + uuid.uuid4().hex[:6] + ".wav"
            target = store.path("samples/" + name)
            (run / "output.wav").rename(target)
            metadata = dict(draft, title=draft.get("title", "").strip() or "Untitled take", created=time.time() - 978307200)
            atomic_json(target.with_suffix(".json"), metadata)
            return target, metadata
        def done(result):
            if result:
                self.reload_takes(select=result[0])
                self.load_audio(result[0], result[1]["title"])
                self.status.setText("Take ready. Your script and settings were saved.")
            else:
                self.status.setText("Generation cancelled. Your script is kept.")
        self.jobs.run(save, done)

    def cancel_work(self):
        self.cancel_event.set()
        if self.process:
            self.generation_cancelled = True
            self.process.terminate()
            self.cancel_kill.start(3000)
        self.status.setText("Cancellation requested; finishing the current operation safely…")

    def refresh_inputs(self):
        if self.recording:
            return
        previous = self.microphone.currentData()
        self.microphone.blockSignals(True)
        self.microphone.clear()
        default = QMediaDevices.defaultAudioInput()
        self.microphone.addItem("System default · " + (default.description() if not default.isNull() else "No input"), "")
        for device in QMediaDevices.audioInputs():
            self.microphone.addItem(device.description(), bytes(device.id()).hex())
        if previous and self.microphone.findData(previous) < 0:
            self.microphone.addItem("Selected microphone unavailable", previous)
        self.restore_input(previous or "")
        self.microphone.blockSignals(False)

    def restore_input(self, identifier):
        if identifier and self.microphone.findData(identifier) < 0:
            self.microphone.addItem("Selected microphone unavailable", identifier)
        self.microphone.setCurrentIndex(max(0, self.microphone.findData(identifier)))

    def start_capture(self, mic_check):
        if self.busy() or not self.store:
            return
        try:
            self.store.check()
            identifier = self.microphone.currentData()
            device = QMediaDevices.defaultAudioInput() if not identifier else next((d for d in QMediaDevices.audioInputs() if bytes(d.id()).hex() == identifier), None)
            if device is None or device.isNull():
                raise ValueError("The selected microphone is unavailable. Choose another input.")
            format = QAudioFormat()
            format.setSampleRate(48000); format.setChannelCount(1); format.setSampleFormat(QAudioFormat.Int16)
            if not device.isFormatSupported(format):
                format = device.preferredFormat()
            types = {QAudioFormat.Int16: np.dtype("<i2"), QAudioFormat.Int32: np.dtype("<i4"), QAudioFormat.Float: np.dtype("<f4"), QAudioFormat.UInt8: np.dtype("u1")}
            if format.sampleFormat() not in types:
                raise ValueError("This input's audio format is unsupported. Choose another microphone.")
            self.capture_format = (format.sampleRate(), format.channelCount(), types[format.sampleFormat()])
            self.player.stop()
            self.capture = QAudioSource(device, format, self)
            self.capture_chunks = []
            self.capture_size = 0
            self.recording_check = mic_check
            self.capture_started = time.monotonic()
            self.recording = True
            self.capture_io = self.capture.start()
            if self.capture_io is None or self.capture.error() != QAudio.NoError:
                raise ValueError("The microphone did not start. Check PipeWire/PulseAudio input permissions and device availability.")
            self.capture_io.readyRead.connect(self.capture_ready)
            self.record_timer.start()
            self.status.setText("Recording the selected microphone. Press Stop recording to finish early.")
            self.update_enabled()
        except Exception as error:
            self.recording = False
            if self.capture:
                self.capture.stop(); self.capture.deleteLater(); self.capture = None
            self.error(str(error)); self.update_enabled()

    def capture_ready(self):
        if not self.capture_io or not self.recording:
            return
        data = bytes(self.capture_io.readAll())
        self.capture_chunks.append(data)
        self.capture_size += len(data)
        rate, channels, dtype = self.capture_format
        frames = len(data) // (dtype.itemsize * channels)
        if frames:
            samples = self.decode_pcm(data[:frames * dtype.itemsize * channels], channels, dtype)
            db = 20 * math.log10(max(float(np.sqrt(np.mean(samples ** 2))), 1e-8))
            self.meter.setValue(int(max(0, min(100, (db + 60) / 60 * 100))))
            self.meter_note.setText(f"{db:.0f} dBFS · " + ("Input detected" if db > -55 else "No clear signal; check input and gain"))
        if self.capture_size > 64 * 1024 * 1024:
            QTimer.singleShot(0, self.stop_capture)

    @staticmethod
    def decode_pcm(data, channels, dtype):
        samples = np.frombuffer(data, dtype=dtype).astype(np.float32)
        if dtype.kind == "i":
            samples /= float(2 ** (dtype.itemsize * 8 - 1))
        elif dtype.kind == "u":
            samples = (samples - 128) / 128
        # A multi-channel interface's first input is used when mono capture is unavailable.
        return samples.reshape(-1, channels)[:, 0]

    def capture_tick(self):
        seconds = time.monotonic() - self.capture_started
        self.status.setText(f"Recording · {seconds:.1f}s / 12s · " + ("Stay quiet for room tone" if self.recording_check and seconds < 2 else "Speak naturally"))
        if seconds >= 12 or self.capture.error() != QAudio.NoError:
            self.stop_capture()

    def stop_capture(self):
        if not self.recording:
            return
        self.capture_ready()
        self.recording = False
        self.record_timer.stop()
        capture_error = self.capture.error()
        self.capture.stop(); self.capture.deleteLater(); self.capture = None
        data, self.capture_chunks = b"".join(self.capture_chunks), []
        rate, channels, dtype = self.capture_format
        frames = len(data) // (dtype.itemsize * channels)
        if capture_error != QAudio.NoError or frames < rate * 3:
            self.error("The input stopped or did not record three seconds of audio. Check the microphone and try again.")
            self.update_enabled(); return
        samples = self.decode_pcm(data[:frames * dtype.itemsize * channels], channels, dtype)
        store, mic_check, cleanup = self.store, self.recording_check, self.cleanup.isChecked()
        def prepare(_):
            folder = store.path("voice-references")
            raw = folder / ("Recording-" + uuid.uuid4().hex + ".wav")
            sf.write(raw, samples, rate, subtype="PCM_16")
            return prepare_sample(raw, folder, DENOISER, cleanup, mic_check)
        self.jobs.run(prepare, lambda profile: self.reference_ready(profile, mic_check))
        self.update_enabled()

    def import_sample(self):
        source, _ = QFileDialog.getOpenFileName(self, "Import 3–15 seconds of your voice", "", "Audio (*.wav *.flac *.aiff *.ogg *.mp3)")
        if source and self.store:
            store, cleanup = self.store, self.cleanup.isChecked()
            self.jobs.run(lambda _: prepare_sample(Path(source), store.path("voice-references"), DENOISER, cleanup), lambda profile: self.reference_ready(profile, False))

    def reference_ready(self, profile, mic_check):
        if mic_check:
            self.mic_check = profile
            self.cleanup.setChecked(True)
        else:
            self.profile = profile
            self.transcript.clear()
        store = self.store
        path = "app-data/linux-mic-check.json" if mic_check else "app-data/linux-your-voice.json"
        snapshot = dict(profile)
        def save():
            atomic_json(store.path(path), snapshot)
            atomic_json(store.path("voice-references/" + snapshot["fileName"]).with_suffix(".json"), snapshot)
        self.saves.submit(save)
        self.update_quality()
        self.status.setText("Microphone check ready. Compare Original test and Cleaned test." if mic_check else "Your Voice sample is ready.")
        self.edited()

    def update_quality(self):
        profile = self.mic_check or self.profile
        if profile and profile.get("quality"):
            quality = profile["quality"]
            self.quality_note.setText(f"Peak {quality['peakDBFS']:.0f} dBFS · Noise estimate {quality['noiseDBFS']:.0f} dBFS. " + quality["guidance"])
        else:
            self.quality_note.clear()

    def play_reference(self, profile, cleaned, title):
        if not profile or not self.store:
            return
        name = profile.get("fileName" if cleaned else "rawFileName", "")
        try:
            if not name or Path(name).name != name:
                raise ValueError("The voice reference is unavailable.")
            self.load_audio(self.store.path("voice-references/" + name), title, autoplay=True)
        except Exception as error:
            self.error(str(error))

    def error(self, message):
        self.download_bar.hide()
        self.status.setText(message)
        self.status.setAccessibleDescription("Error: " + message)

    def closeEvent(self, event):
        if self.real_close:
            event.accept(); return
        if self.closing:
            event.ignore(); return
        if self.busy():
            QMessageBox.information(self, "Finish the current operation", "Stop recording, cancel generation/download, or wait for audio processing to finish before quitting.")
            event.ignore(); return
        self.autosave.stop()
        self.save_draft()
        self.player.stop()
        event.ignore()
        self.closing = True
        self.saves.flush_and_close()

    def close_after_save(self):
        self.player.setSource(QUrl())
        self.real_close = True
        self.close()


def main():
    app = QApplication(sys.argv)
    app.setApplicationName("Raven VO")
    app.setOrganizationName("Happy Jack Media")
    app.setApplicationVersion(__version__)
    app.setDesktopFileName("raven-vo")
    if sys.platform == "win32":
        import ctypes
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("HappyJack.RavenVO")
    app.setStyle("Fusion")
    palette = QPalette()
    for role, value in [(QPalette.Window, "#242424"), (QPalette.WindowText, "#f3f3f3"),
                        (QPalette.Base, "#191919"), (QPalette.AlternateBase, "#333333"),
                        (QPalette.Text, "#f3f3f3"), (QPalette.Button, "#414141"),
                        (QPalette.ButtonText, "#ffffff"), (QPalette.Light, "#b8b8b8"),
                        (QPalette.Mid, "#747474"), (QPalette.Dark, "#929292"),
                        (QPalette.Highlight, "#555555"), (QPalette.HighlightedText, "#ffffff")]:
        palette.setColor(role, QColor(value))
    palette.setColor(QPalette.Disabled, QPalette.Text, QColor("#b8b8b8"))
    palette.setColor(QPalette.Disabled, QPalette.ButtonText, QColor("#b8b8b8"))
    app.setPalette(palette)
    app.setStyleSheet("""
        QWidget { background: #242424; color: #f3f3f3; font-size: 13px; }
        QLineEdit, QPlainTextEdit, QListWidget, QComboBox { background: #191919; border: 1px solid #747474; border-radius: 5px; padding: 6px; }
        QPushButton { background: #414141; color: #ffffff; border: 1px solid #777777; padding: 7px; border-radius: 5px; }
        QPushButton:hover { background: #555555; }
        QPushButton:focus, QComboBox:focus, QLineEdit:focus, QPlainTextEdit:focus, QSlider:focus { border: 2px solid #ffffff; }
        QPushButton#primary { background: #f2ad32; color: #111111; }
        QWidget:disabled { color: #b8b8b8; }
        QPushButton:disabled { background: #333333; border-color: #555555; }
        QPushButton#primary:disabled { background: #333333; color: #b8b8b8; }
        QGroupBox { border: 1px solid #6c6c6c; border-radius: 5px; margin-top: 14px; padding-top: 12px; }
        QGroupBox::title { subcontrol-origin: margin; left: 8px; }
        QProgressBar { border: 1px solid #777777; min-height: 9px; text-align: center; }
        QProgressBar::chunk { background: #b8b8b8; }
        QListWidget::item:selected { background: #555555; }
    """)
    window = Window()
    window.show()
    if "--screenshot" in sys.argv:
        index = sys.argv.index("--screenshot")
        if index + 1 < len(sys.argv):
            QTimer.singleShot(800, lambda: window.grab().save(sys.argv[index + 1]))
    if "--smoke-test" in sys.argv:
        QTimer.singleShot(1500, window.close)
    return app.exec()
