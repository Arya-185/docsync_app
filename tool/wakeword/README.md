# Training the "Hey DocSync" wake word

The app ships openWakeWord's stock **"Hey Jarvis"** model so the wake word works today. A trained
`hey_docsync.onnx` placed in `assets/wakeword/` replaces it automatically — the app checks for
that file at start-up (`WakeModel.heyDocSync` in `lib/features/voice/model/wake_word_engine.dart`),
and the Voice screen and Settings then say "Hey DocSync" instead. No code change needed.

## 1. Indian-voice clips (on this PC, ~2 minutes, a few rupees of Sarvam credit)

```bash
SARVAM_API_KEY=<the speech key> dart run tool/wakeword/gen_samples.dart tool/wakeword/out --negatives
```

- `out/positive/` — 300 clips: 25 Sarvam voices × 3 paces × 4 spellings of the phrase.
- `out/negative/` — 600 near-misses ("Hey Doc", "DocSync", "hey dog sink", "Hey Siri"…) that
  must *not* wake it.
- 16 kHz mono WAV. Reruns skip clips that exist. `out/` is git-ignored — it is training data, not
  source.

## 2. Train (Google Colab, GPU runtime, ~45–60 min)

1. Open openWakeWord's **automatic model training** notebook:
   `https://github.com/dscripka/openWakeWord` → `notebooks/automatic_model_training.ipynb`
   → "Open in Colab". Runtime → Change runtime type → **T4 GPU**.
2. Set `target_word = "hey doc sync"` (spelled as it sounds, so its Piper voices say it right).
3. Before the "generate clips" step, upload `out/positive/*.wav` into the notebook's positive
   training folder and `out/negative/*.wav` into its negative folder, so the Indian voices are
   trained alongside the Piper ones.
4. Keep the defaults for everything else (≈ 50k steps) and run all.
5. Download the resulting `hey_doc_sync.onnx`.

## 3. Ship it

```bash
cp ~/Downloads/hey_doc_sync.onnx assets/wakeword/hey_docsync.onnx
```

Rebuild the APK. Then, on a real phone, check both failure modes before trusting it:

- **Misses:** say it 20 times at arm's length, in a quiet room and with a fan/AC on. It should
  wake ≥ 18 times at the default sensitivity.
- **False wakes:** leave the Voice tab open during 10 minutes of normal office talk and a video
  playing. Any false wake → lower the sensitivity in Settings, or retrain with more negatives.

Detection runs entirely on the phone and only while the app is open on the Voice tab; nothing
leaves the phone until the phrase is heard.
