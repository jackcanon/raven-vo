# Linux distribution notices

Raven VO's frontend and PCM helper driver are MIT. Ming weights are downloaded separately under the pinned model's published MIT terms. audio.cpp is Apache-2.0 and RNNoise is BSD-3-Clause. The existing root `THIRD_PARTY.md`, model notices and bundled engine dependency notices also apply.

The Linux frontend uses unmodified **PySide6 / Qt 6.8.3** under LGPL-3.0 (with relevant Qt module third-party notices), not a proprietary Qt licence. The package keeps Qt as replaceable, dynamically linked libraries in the PyInstaller onedir bundle. The public frontend source and pinned build requirements accompany the package, and rebuilding the frontend against a modified compatible Qt/PySide distribution is permitted. No restriction on reverse engineering for debugging modifications to LGPL components is imposed.

Qt source and build information for the exact release: https://download.qt.io/archive/qt/6.8/6.8.3/ and https://download.qt.io/official_releases/QtForPython/pyside6/PySide6-6.8.3-src/ . Qt's licence overview: https://doc.qt.io/qtforpython-6/licenses.html . Preserve the shipped LGPL/GPL text and all dependency notices when redistributing; distributing a modified Qt or FFmpeg build requires reviewing that build's corresponding-source obligations. No claim is made that every third-party codec is suitable for every jurisdiction or use.

Pinned Python dependencies also include NumPy (BSD), SciPy (BSD and bundled numerical-library notices), SoundFile/libsndfile (BSD/LGPL as applicable), CFFI (MIT), pycparser (BSD) and Send2Trash (BSD). PyInstaller is a build tool under GPL with its distribution exception. Package assembly retains licence files from installed distributions and exact upstream Qt/PySide/FFmpeg source archives under `ThirdParty`, including corresponding-source download links. We do not include a model blob inside the app archive.

The initial preview is for compatibility testing; native hardware and all distribution obligations should be checked before treating it as a supported production release.

To run the editable frontend with a replacement compatible Qt/PySide installation, create a Python environment, install `source/requirements.txt` (substituting your Qt/PySide build), then run `PYTHONPATH=source RAVEN_VO_RESOURCES="$PWD/_internal/resources" python -m raven_vo` from the extracted bundle directory. The application does not enforce library signatures or prohibit replacement.
