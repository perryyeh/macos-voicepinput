---
name: macos-swiftpm-menu-bar-voice-input
description: Build and iterate on a macOS SwiftPM menu-bar push-to-talk voice input app using Apple Speech, optional Local mlx-whisper, optional External LLM, configurable hotkeys, and clipboard text injection.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [macos, swiftpm, speech, apple-speech, mlx-whisper, menu-bar, accessibility, privacy]
---

# macOS SwiftPM Menu-Bar Voice Input App

Use this when creating or modifying a lightweight macOS voice input / dictation utility built with Swift Package Manager, especially one that records while a hotkey is held, transcribes speech, optionally refines text with an LLM, then inserts text into the focused app.

## Proven Architecture

- SwiftPM package with:
  - library target for core logic
  - executable target for the AppKit app entrypoint
  - Swift Testing target for model/policy tests
- Manual `.app` bundle packaging via `Makefile`:
  - copy release binary into `Contents/MacOS/`
  - copy `Info.plist` into `Contents/`
  - copy resources such as `AppIcon.icns` into `Contents/Resources/`
  - ad-hoc sign with `codesign --force --sign -`
- `Info.plist` should include:
  - `LSUIElement=true` for menu-bar-only app/no Dock icon
  - `NSMicrophoneUsageDescription`
  - `NSSpeechRecognitionUsageDescription`
  - `CFBundleIconFile` if app icon is present

## Recognition Engine and Settings Policy

Expose explicit user-facing engine choices rather than only a backend list:

1. `Auto` — Apple Speech → Local mlx-whisper → External LLM
2. `Apple Speech` — system Speech framework only; good default
3. `Local mlx-whisper` — local recording followed by local transcription
4. `External LLM` — user-configured external transcription/LLM backend only

Default engine should be Apple Speech when the user asks for “default use macOS/system recognition”. Keep Auto as an option, not the default, unless requested.

Current preferred menu/settings shape for this app:

- Remove `Local-only Mode` unless the user explicitly asks to restore a privacy toggle.
- Use a top-level `LLM Settings…` item, not an `LLM Refinement` submenu.
- Do not include an `Enable LLM Refinement` toggle. If LLM config is complete (API base URL, Keychain API key, and model), use it; otherwise fall back to the original transcript.
- Add a top-level `Hotkey Settings…` item for push-to-talk shortcut selection.

Tests should verify:

- all engine options exist and are ordered as expected
- default engine is Apple Speech, not Auto
- Auto fallback order
- explicit Apple Speech uses only Apple Speech
- explicit Local mlx-whisper uses only mlx-whisper
- explicit External LLM uses only the external backend
- settings no longer expose `localOnlyMode`
- hotkey settings default to Fn and include the supported fallback choices

## Apple Speech Path

- Use `SFSpeechRecognizer(locale:)` with default language `zh-CN` when the user prefers Simplified Chinese.
- Request Speech Recognition permission only when needed or at startup if acceptable.
- Use `AVAudioEngine` and `SFSpeechAudioBufferRecognitionRequest` for streaming partial transcript.
- Store final/partial transcript and update a floating panel in real time.
- Apple Speech is a system framework; local-only mode can ensure the app does not call its own external APIs, but cannot independently guarantee Apple’s framework never uses network. Be explicit about this.

## mlx-whisper Path

- For local-only/self-hosted transcription, record an audio file locally first, then pass it to a helper such as:

```bash
~/.local/bin/local-transcribe <audio-file> [model]
```

- Default model for this user is `mlx-community/whisper-medium` / medium-class mlx-whisper.
- Verify environment without installing anything unless approved:

```bash
test -x "$HOME/.local/bin/local-transcribe"
"$HOME/.hermes/asr-venv/bin/python" - <<'PY'
import mlx_whisper
print('ok')
PY
test -x "$HOME/.local/bin/ffmpeg"
test -d "$HOME/.cache/huggingface/hub/models--mlx-community--whisper-medium"
```

- A quick no-speech smoke test can be done by generating 1s silence with ffmpeg and running `local-transcribe`; empty output with exit 0 is acceptable for silence.

## Removed Local-only Mode

Earlier versions used `Local-only Mode` as a privacy switch that disabled external STT/API backends and LLM refinement. The current preferred UX removes this toggle to reduce menu complexity. If privacy needs reappear, prefer an explicit engine choice (`Local mlx-whisper`) and clear External LLM configuration state rather than reintroducing a broad local-only switch by default.

If the user explicitly asks for the strongest local-only behavior, recommend:

```text
Recognition Engine = Local mlx-whisper
External LLM config = empty/unused
```

Apple Speech’s own network behavior is controlled by macOS/Apple, not by the app.

## LLM Settings Safety

- Send only transcript text to the LLM, never audio.
- API key belongs in macOS Keychain, not UserDefaults.
- Keep non-sensitive fields such as base URL/model in UserDefaults.
- Current preferred UX is `LLM Settings…` without an `Enable LLM Refinement` toggle.
- Treat complete LLM config (base URL + Keychain API key + model) as enabled; incomplete config means fall back to original transcript.
- Use a short timeout such as 2.5s and fall back to original transcript on failure.
- Prompt should be conservative: only fix obvious ASR mistakes; never rewrite, polish, summarize, add, remove, or change intent.
- Logs should not include transcript by default.

## Hotkey Settings

Provide `Hotkey Settings…` so the push-to-talk trigger can be changed without editing code. Use Fn as the default, but include fallbacks because Fn/Globe handling varies by macOS version, keyboard hardware, and system settings.

Proven preset choices:

- `Fn`
- `Right Option`
- `Control + Space`
- `Command + Shift + Space`

Implementation notes:

- Store hotkey settings separately from transcription/LLM settings.
- Restart the hotkey monitor after saving settings, for example via a `NotificationCenter` notification.
- For CGEvent-based detection, common key codes are Fn/Globe `63`, Right Option `61`, and Space `49`; verify on real hardware when possible.
- Detect modifier-only triggers with `.flagsChanged`; detect Space combinations with `.keyDown` start and `.keyUp` release.

## Text Injection

- Clipboard + simulated Cmd+V is broad and reliable.
- Preserve and restore pasteboard items after insertion.
- For CJK input methods, temporarily switch to ABC/US before paste, then restore the original input source.
- Warn that clipboard managers may still observe transient clipboard text.

## Permissions: Important Distinction

For the current AppKit/CGEvent-style approach, do not tell the user that Input Monitoring is required unless the code actually requests/uses APIs that trigger it.

Usually required:

- Microphone — recording
- Speech Recognition — Apple Speech
- Accessibility — global hotkey/event tap and simulated paste

Input Monitoring:

- Not required by builds that only rely on Accessibility for event tap/paste.
- It is normal for the app not to appear in System Settings → Privacy & Security → Input Monitoring if the app never requests that permission.
- Permission UI should say “Accessibility”, not “Accessibility/Input Monitoring”, unless Input Monitoring is truly implemented.

If the app is not listed under Accessibility, instruct the user to add the built `.app` manually with the `+` button.

## Migrating a Scratch VoiceInput Project Into a New GitHub Repo

When the app was first developed in a local scratch directory and the user later creates a real GitHub repo, use this safe sequence:

1. Clone the new repo into the desired final directory, usually under `/Users/yeh/code/`:

```bash
cd /Users/yeh/code
git clone git@github.com:OWNER/REPO.git macos-voiceinput
```

2. Copy the scratch project into the clone with `rsync`, excluding transient/build artifacts and the old `.git` directory:

```bash
rsync -a --delete \
  --exclude='.git/' \
  --exclude='.build/' \
  --exclude='VoiceInput.app/' \
  /Users/yeh/code/voiceinput/ /Users/yeh/code/macos-voiceinput/
```

3. If the new GitHub repo was initialized with files such as `LICENSE` and `rsync --delete` removed them, restore intentionally kept tracked files before committing:

```bash
cd /Users/yeh/code/macos-voiceinput
git checkout -- LICENSE  # only if desired and tracked
```

4. Copy this skill into the repo if the user asks to keep project-specific procedural knowledge with the source:

```bash
mkdir -p skills/macos-swiftpm-menu-bar-voice-input
cp ~/.hermes/skills/apple/macos-swiftpm-menu-bar-voice-input/SKILL.md \
  skills/macos-swiftpm-menu-bar-voice-input/SKILL.md
```

5. Verify before commit/push:

```bash
make test && make build
git status --short
```

6. Commit and push, then confirm local and remote state:

```bash
git add .
git commit -m "Initial macOS voice input app"
git push -u origin main
git status --short --branch
git log --oneline -1
git ls-remote --heads origin main
```

7. Only after successful push and final sanity checks, remove the old scratch directory if explicitly requested:

```bash
test -d /Users/yeh/code/macos-voiceinput
test -f /Users/yeh/code/macos-voiceinput/Package.swift
rm -rf /Users/yeh/code/voiceinput
```

Pitfalls:

- `rsync --delete` can remove tracked files from the newly initialized repo; inspect `git status --short` and restore files like `LICENSE` if they should be preserved.
- A `git push` can time out locally after the commit succeeds; check `git status --short --branch` and `git ls-remote --heads origin main`, then retry `GIT_TERMINAL_PROMPT=0 git push -u origin main` if local is still ahead.
- Do not delete the scratch directory until tests/build pass and the commit is confirmed pushed.

## Verification Commands

From the project root:

```bash
swift test
make build
```

Verify Apple Speech recognizer availability:

```bash
swift -e 'import Speech; let r = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")); print("recognizer=\(r != nil), available=\(r?.isAvailable ?? false), auth=\(SFSpeechRecognizer.authorizationStatus().rawValue)")'
```

`auth=0` means not determined; first actual run still needs user authorization.

Verify bundle resources and signing when app icon/resources change:

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' VoiceInput.app/Contents/Info.plist
test -f VoiceInput.app/Contents/Resources/AppIcon.icns
codesign --verify --deep --strict VoiceInput.app
```

If the user wants a directly downloadable app artifact in the repository root, keep `VoiceInput.app/` ignored as a build product and commit a zip archive instead:

```bash
make build
rm -f VoiceInput.app.zip
ditto -c -k --sequesterRsrc --keepParent VoiceInput.app VoiceInput.app.zip
unzip -t VoiceInput.app.zip
```

Document direct use in README: download `VoiceInput.app.zip`, unzip it, move or run `VoiceInput.app`, grant Microphone/Speech Recognition/Accessibility permissions, and if Gatekeeper blocks the ad-hoc signed app, right-click → Open or allow it from System Settings → Privacy & Security.

## Pitfalls

- SwiftPM alone does not create a complete macOS `.app`; manual bundle resource copying matters.
- If the project is entirely untracked in git, `git diff` may show nothing; use `git status --short` and direct file verification.
- Fn/Globe key handling varies by macOS version and keyboard settings; provide a fallback hotkey if possible.
- Finder icon caching can show stale/blank icons after adding `.icns`; rebuilding, copying to a new path, or installing to `/Applications` usually refreshes.
- Do not test or configure external APIs with the user’s secrets unless explicitly instructed; never reveal API keys in summaries.
