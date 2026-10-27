# Third-party software

This front end invokes an unmodified, separately licensed audio.cpp executable. The build pins that project and all of its submodules, and packages their available LICENSE, COPYING and NOTICE files under `Contents/Resources/ThirdParty`.

- audio.cpp: Copyright 2026 ShugoAI LLC, Apache License 2.0.
- ggml: MIT.
- SentencePiece: Apache License 2.0; its bundled protobuf-lite and supporting notices are included.
- cJSON, utf8proc, and other bundled libraries retain their respective notices included with the engine source.
- Apple system frameworks are provided by macOS and are not redistributed here.

Ming 0.5B and its GGUF conversion are downloaded separately from Hugging Face. The model source is Inclusion AI / Ant Group's MIT-licensed Ming-3.0-tts. The exact model URL, revision, byte size, and SHA-256 checksum are specified in `Sources/ModelInstaller.swift`.

Original projects:

- https://github.com/0xShug0/audio.cpp
- https://github.com/inclusionAI/Ming-3.0-tts
- https://huggingface.co/audio-cpp/Ming-3.0-TTS-0.5B-GGUF
