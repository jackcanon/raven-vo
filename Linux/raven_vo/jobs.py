from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from PySide6.QtCore import QObject, QRunnable, QThreadPool, Signal, Slot


class JobSignals(QObject):
    result = Signal(str, object)
    error = Signal(str, str)
    progress = Signal(object, object, str)


class Worker(QRunnable):
    def __init__(self, key, fn, signals):
        super().__init__()
        self.key, self.fn, self.signals = key, fn, signals

    def run(self):
        try:
            self.signals.result.emit(self.key, self.fn(self.signals.progress.emit))
        except Exception as error:
            self.signals.error.emit(self.key, str(error))


class Jobs(QObject):
    failed = Signal(str)
    progress = Signal(object, object, str)
    changed = Signal(bool)
    def __init__(self, parent=None):
        super().__init__(parent)
        self.signals = JobSignals(self)
        self.signals.result.connect(self.complete)
        self.signals.error.connect(self.failure)
        self.signals.progress.connect(self.progress)
        self.pending = {}
        self.sequence = 0

    def run(self, fn, done):
        self.sequence += 1
        key = str(self.sequence)
        self.pending[key] = done
        self.changed.emit(True)
        QThreadPool.globalInstance().start(Worker(key, fn, self.signals))

    @Slot(str, object)
    def complete(self, key, result):
        callback = self.pending.pop(key, None)
        try:
            if callback:
                callback(result)
        except Exception as error:
            self.failed.emit(str(error))
        self.changed.emit(bool(self.pending))

    @Slot(str, str)
    def failure(self, key, message):
        self.pending.pop(key, None)
        self.failed.emit(message)
        self.changed.emit(bool(self.pending))


class SettingsQueue(QObject):
    failed = Signal(str)
    flushed = Signal()
    def __init__(self, parent=None):
        super().__init__(parent)
        self.pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix="raven-settings")

    def submit(self, fn):
        future = self.pool.submit(fn)
        future.add_done_callback(self.finished)

    def finished(self, future):
        if future.exception():
            self.failed.emit("Could not save settings: " + str(future.exception()))

    def flush_and_close(self):
        future = self.pool.submit(lambda: None)
        future.add_done_callback(lambda _: self.flushed.emit())
        self.pool.shutdown(wait=False)
