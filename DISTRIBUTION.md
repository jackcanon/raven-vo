# Distribution review — 2026-10-27

Published licence basis:

- Ming 3.0 TTS 0.5B official model card identifies the released checkpoint as MIT and links to inclusionAI/Ming-3.0-tts/LICENSE. The licence permits use, copying, modification, distribution, sublicensing and sale, conditioned on preserving its copyright and permission notice.
- The exact downloaded GGUF repository at revision 2eb8d37c7f10672e69c8aa33091baa04c461b66c marks the conversion as MIT and identifies the official model as its base.
- audio.cpp at bdf78b9140d091949b20311bcf7ecad3698e53fe carries Apache-2.0. The app bundles its unmodified executable, licence, and available dependency notices. The front end is separately MIT-licensed.

The app bundles full notices under Contents/Resources/ThirdParty, including Ming/Ming-LICENSE, model and adapted voice-catalogue attribution, and FrontEnd/LICENSE. Weights are downloaded separately from the pinned upstream URL; they are not included in the release ZIP.

This review supports software/model distribution under the stated licences. It is not an independent audit of training data, individual speaker consent, or rights to particular characters or generated content. Those rights are separate. Follow upstream guidance on consent, deception and identifying synthetic speech where appropriate. The app is independent and makes no claim of endorsement.

Sources:
- https://huggingface.co/inclusionAI/Ming-3.0-tts-0.5B
- https://github.com/inclusionAI/Ming-3.0-tts/blob/main/LICENSE
- https://huggingface.co/audio-cpp/Ming-3.0-TTS-0.5B-GGUF/blob/2eb8d37c7f10672e69c8aa33091baa04c461b66c/README.md
- https://github.com/0xShug0/audio.cpp/blob/bdf78b9140d091949b20311bcf7ecad3698e53fe/LICENSE

October 27, 2026, 0.4 update: RNNoise is bundled for sample cleanup. Xiph's BSD-3-Clause COPYING and AUTHORS are included; its pinned, checksum-verified default network is compiled into the helper. The app's reference-recording feature is intended for users' own voice samples and retains the original recording. No claim of rights to third-party voices or character identities is made.
