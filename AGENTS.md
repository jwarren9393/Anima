# Anima — Agent Living Document

> **Mandatory for every agent session:** Read this file fully at the start.
> Update it before you finish any meaningful phase of work.
> Keep language clear enough that a coding beginner (the project owner) can follow it.

---

## What Anima is

**Anima** is a private, personal AI character chat app.

| Item | Value |
|------|--------|
| Owner use | Personal only — will **not** be published to app stores |
| UI framework | Flutter |
| AI backend | [NanoGPT API](https://docs.nano-gpt.com/) (OpenAI-compatible chat completions) |
| Primary platform | Android |
| Also target | Windows, Linux |
| Repo | Private: https://github.com/jwarren9393/Anima |

Base chat URL: `https://nano-gpt.com/api/v1/chat/completions`  
Auth header: `Authorization: Bearer <API_KEY>`

---

## Strict project rules

1. Use Flutter.
2. Keep architecture **simple** and Android-friendly — no heavy frameworks unless asked.
3. Act as a **patient mentor**: write the code, explain in plain English, avoid jargon.
4. API keys must be entered in-app Settings and stored with **secure storage** — never committed to Git.
5. Do **not** invent app-store / Play Store requirements; this app stays private.
6. After completing work, **update this file** (status, done, next).

---

## Current status

**Phase:** 3 — Characters ✅

**Last updated:** 2026-07-17  
**Last agent action:** Added create/edit/select/delete characters with JSON file persistence; chat sends each character’s system prompt to NanoGPT. Deployed to SM-S731U. Phase 1–2 previously pushed; Phase 3 ready to commit.

### What works today

- Flutter app named `anima` (`com.anima.anima`) with Android, Linux, and Windows folders
- **Real chat screen** wired to NanoGPT (bubbles, send, Thinking…, plain-English errors)
- **Characters:** name + personality prompt; list / create / edit / delete / select
- Characters saved on-device as `anima_characters.json` (via `path_provider`)
- Selected character’s system prompt is sent with every NanoGPT request
- Switching characters clears the in-memory chat (per-character saved history is Phase 4)
- Settings: API key + model (default `openai/gpt-4o-mini`)
- Private GitHub repo + Android toolchain + runs on Samsung SM-S731U

### What does NOT work yet

- Chat history saved across app restarts / per character (Phase 4)
- Streaming replies (Phase 4)
- Character avatars (optional later)
- Linux desktop build tools (optional; needs sudo apt)

---

## Build phases (roadmap)

Update checkboxes as phases complete.

### Phase 0 — Foundation ✅

- [x] Create Flutter project (android, linux, windows)
- [x] Simple folder layout under `lib/`
- [x] Secure API key Settings screen
- [x] NanoGPT service stub
- [x] Living agent document (`AGENTS.md`)
- [x] Harden `.gitignore` against secrets
- [x] Initialize git + create private GitHub repo (`jwarren9393/Anima`)

### Phase 1 — Dev environment (Android first)

- [x] Install Android SDK + JDK; fix `flutter doctor` Android issues
- [x] Confirm Android debug APK builds (`flutter build apk --debug`)
- [x] Connect a phone (USB debugging) and confirm `flutter run` on Android (SM-S731U)
- [ ] Optional: install Linux build deps for desktop testing
- [x] Install `gh` and create a **private** GitHub repo; push initial commit

### Phase 2 — Real chat UI ✅

- [x] Message list + text input + send button
- [x] Local in-memory conversation for one session
- [x] Call `NanoGptService.sendChatMessage` from the chat screen
- [x] Show loading / error states in plain language
- [x] Default model setting (editable in Settings)

### Phase 3 — Characters ✅

- [x] Simple character model (name, system prompt, optional avatar later)
- [x] Create / edit / select a character
- [x] Persist characters on device (JSON file via `path_provider`)

### Phase 4 — Persistence & polish

- [ ] Save chat history per character
- [ ] Streaming responses (SSE) from NanoGPT
- [ ] Basic theming / nicer mobile layout
- [ ] Windows smoke test; Linux smoke test

### Phase 5 — Nice-to-haves (only if requested)

- [ ] Export / import chats
- [ ] Multiple API base URLs (e.g. subscription endpoint)
- [ ] Offline-friendly error messages

---

## Code map (keep this accurate)

```
lib/
  main.dart                         App entry, themes, wires services → ChatScreen
  models/
    chat_message.dart               One chat bubble (user or assistant)
    character.dart                  Character name + system prompt
  screens/
    chat_screen.dart                Chat UI + NanoGPT send/receive
    characters_screen.dart          List / select / delete characters
    character_edit_screen.dart      Create or edit a character
    settings_screen.dart            API key + model name
  services/
    api_key_service.dart            Secure storage for NanoGPT API key
    settings_service.dart           Model + selected character id
    character_service.dart          Load/save characters JSON on device
    nanogpt_service.dart            HTTP client for /chat/completions + plain errors
```

**Dependencies in use:** `flutter_secure_storage`, `http`, `path_provider`

---

## Security checklist for agents

- [ ] Never write API keys into source, README examples with real keys, screenshots committed to git, or `.env` files that get committed
- [ ] Prefer device secure storage (`ApiKeyService`) over SharedPreferences for secrets
- [ ] If a secret is ever committed by mistake: rotate the NanoGPT key immediately and purge it from git history
- [ ] `android/local.properties` stays gitignored (machine-specific SDK path)

---

## Machine notes (this developer PC)

| Tool | Status |
|------|--------|
| Flutter | ✅ 3.44.6 stable at `~/development/flutter` |
| Dart | ✅ 3.12.2 |
| JDK | ✅ Temurin 17 at `~/development/jdk-17` |
| Android SDK | ✅ `~/Android/Sdk` (platform 36, build-tools 36.0.0) — Flutter doctor Android ✓ |
| Chrome | ❌ Not required for this app |
| Linux desktop toolchain | ❌ clang/cmake/ninja/pkg-config missing (needs sudo apt) |
| Git | ✅ installed |
| GitHub CLI (`gh`) | ✅ `~/.local/bin/gh` (logged in as jwarren9393) |
| Physical Android phone | ✅ Samsung SM-S731U (`R3CYA09N26J`), Android 16 — `flutter run` verified |

PATH tip for shells (also appended to `~/.bashrc`):

```bash
export JAVA_HOME="$HOME/development/jdk-17"
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$HOME/development/flutter/bin:$HOME/.local/bin:$PATH"
```

### Phone USB debugging (owner checklist)

1. On the phone: **Settings → About phone → tap Build number 7 times** (unlocks Developer options).
2. **Settings → Developer options → turn on USB debugging**.
3. Plug phone into this PC with a data-capable USB cable.
4. Accept the “Allow USB debugging?” prompt on the phone.
5. In a terminal, run: `adb devices` — you should see your phone listed (not `unauthorized`).
6. From the Anima folder: `flutter run`

If the phone shows as `unauthorized` or missing, unplug/replug and re-accept the prompt. On some Linux setups a udev rule may be needed later.

---

## Next actions (do these in order)

1. **Phase 4:** Persist chat history per character; optional streaming replies.
2. Commit/push Phase 3 to GitHub when the owner asks (if not already pushed).
3. Optional: `sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev` for Linux desktop runs.

---

## How to update this document

When you finish work, edit these sections:

1. **Current status** — phase name, date, last agent action, what works / doesn't
2. **Build phases** — check off completed items
3. **Code map** — if you added/removed files
4. **Next actions** — replace with the true next steps

Do not delete historical phase checklists; mark them done so future agents see progress.
