# JOBA basic face comparison

Private CPU service; no public port, no third-party image API. YuNet detects one face and SFace creates a normalized 128-value descriptor. Models and licenses are pinned in `models.json`; `download_models.py` verifies length and SHA-256. YuNet is MIT; SFace is Apache-2.0. Runtime dependencies are pinned in `requirements.txt`.

This intentionally performs **no liveness, anti-photo, replay, deepfake or camera-stream checks**. The oval and pulse only guide framing. It must not be described as OS Face ID or spoof-resistant authentication. Similarity >= 0.45 enables password reset. This is an initial implementation threshold, not a measured false-accept rate; population/device accuracy has not been calibrated.

The API accepts JPEG/PNG up to 2 MiB, decodes at most 16 MP, requires exactly one sufficiently large face, and never stores the source image. The API stores an AES-256-GCM encrypted descriptor, bound to user ID by authenticated encryption. Consent is explicit; existing accounts authenticate with their password before enrollment. Setup can be declined. Document-verification selfies are never silently reused. A user can delete their template in Profile → Security → Face recovery.

After two invalid passwords in ten minutes, an opaque five-minute challenge can compare a new camera capture. A match creates one short-lived reset token; it does not log the user in or change verification/access. Reset consumes the proof and revokes all sessions. Normal login, credential changes, template changes, disabling and deletion invalidate outstanding proofs. No recovery for staff, blocked or deleted accounts. Unknown accounts receive the same generic prompt without usable proof.

Run `python download_models.py`, then `python -m unittest test_engine`. Fixture `testdata/portrait.png` comes from scikit-image v0.25.2 `skimage/data/astronaut.png`, a NASA public-domain image; it is used only for smoke tests, never as an account reference. Tests check embedding extraction, an exposure variant, blank/two-face/malformed/oversize rejection. They do not demonstrate spoof resistance or population-level accuracy.
