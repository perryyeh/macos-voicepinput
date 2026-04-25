# VoiceInput

A lightweight macOS 14+ menu-bar push-to-talk dictation app.

Default engine: **Apple Speech Recognition** (`zh-CN` by default).

Selectable recognition engines:

1. **Auto** — Apple Speech → Local mlx-whisper → External LLM.
2. **Apple Speech** — system Speech framework only. This is the default.
3. **Local mlx-whisper** — record locally, then transcribe with `~/.local/bin/local-transcribe`.
4. **External LLM** — reserved for user-configured external LLM testing.

Optional **OpenAI-compatible LLM refinement** conservatively fixes only obvious ASR mistakes before inserting text.

Hold **Fn** to record; release to paste the final text into the currently focused input field. Use **Hotkey Settings…** to change the push-to-talk shortcut.

## Features

- Menu-bar-only app (`LSUIElement`, no Dock icon).
- Default language: Simplified Chinese (`zh-CN`).
- Language menu: English, Simplified Chinese, Traditional Chinese, Japanese, Korean.
- Recognition Engine menu: Auto, Apple Speech, Local mlx-whisper, External LLM. Apple Speech is selected by default.
- Bottom-center frameless capsule panel with live partial transcript and RMS-driven waveform bars.
- Clipboard + simulated Cmd+V injection.
- CJK input-source detection; switches to ABC/US before paste and restores original input source afterwards.
- LLM Settings window for API Base URL, API Key, and Model.
- Hotkey Settings window: Fn, Right Option, Control + Space, or Command + Shift + Space. Fn is selected by default.
- API key stored in macOS Keychain; clearing the field deletes it from Keychain.
- LLM timeout defaults to 2.5s and falls back to original transcript on error/timeout.
- Logs to `~/Library/Logs/VoiceInput/voiceinput.log` without transcript contents by default.

## Build / Run

```bash
make test
make build
make run
make install
make clean
```

The app bundle is ad-hoc signed by `make build`.

## Permissions

On first run, grant:

- Microphone
- Speech Recognition
- Accessibility for global Fn detection and paste simulation

If Fn detection or paste does not work, open:

```text
System Settings → Privacy & Security → Accessibility
```

Input Monitoring is not required by the current build; it is normal if VoiceInput does not appear in the Input Monitoring list.

## mlx-whisper fallback

The fallback expects the existing local helper:

```bash
~/.local/bin/local-transcribe <audio-file> [model]
```

Default model used by the app:

```text
mlx-community/whisper-medium
```

If the helper is absent, the app simply skips mlx-whisper fallback.

## LLM Settings

Menu bar → `LLM Settings…`:

- Configure API Base URL, API Key, Model.
- API Key is stored in macOS Keychain.

The app calls:

```text
<API Base URL>/chat/completions
```

with an OpenAI-compatible request. The system prompt is intentionally conservative: only obvious speech-recognition mistakes are fixed; no rewriting, polishing, summarizing, or content removal.

## Current caveats

- Fn/Globe handling differs across macOS versions and keyboards; Accessibility permission is required. If Fn conflicts with macOS, change it in Hotkey Settings.
- Apple Speech is the default real-time engine.
- Auto mode falls back from Apple Speech to Local mlx-whisper, then to External LLM.
- Local mlx-whisper mode records first, then transcribes after release.
- External LLM is scaffolded for user testing/configuration.
- Clipboard restoration preserves pasteboard items, but clipboard-manager apps may still observe transient text.
