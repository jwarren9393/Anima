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
| Inspiration | **SillyTavern-like** experience on mobile (core RP/chat features), **not** a full SillyTavern clone |
| UI framework | Flutter |
| AI backend | [NanoGPT API](https://docs.nano-gpt.com/) (OpenAI-compatible chat completions) |
| Primary platform | Android |
| Also target | Windows, Linux |
| Repo | Private: https://github.com/jwarren9393/Anima |

Base chat URL: `https://nano-gpt.com/api/v1/chat/completions`  
Auth header: `Authorization: Bearer <API_KEY>`

### Product direction (read this every session)

Anima should feel **reminiscent of SillyTavern**: rich character roleplay, persistent chats, editable messages, swipes, lorebooks, personas, and card import — optimized for a **simple Android-first Flutter app**.

**Do not try to rebuild all of SillyTavern.** Prefer the highest-value ST features in small phases. Keep architecture simple. When choosing between “perfect ST parity” and “works great on a phone,” choose the phone.

High-value SillyTavern concepts to aim for over time:

1. Richer character cards (description, personality, scenario, first message, examples, greetings)
2. Per-character (and eventually multi-chat) persistent history
3. Chat controls: edit / delete / continue / regenerate / swipes
4. Streaming replies
5. User persona + simple macros (`{{user}}`, `{{char}}`)
6. World Info / lorebooks (keyword-triggered context)
7. Import/export Character Card V2/V3 (JSON/PNG) when feasible
8. Sampling controls (temperature, max tokens, etc.)
9. Later / optional: group chats, TTS, advanced prompt templates, regex

---

## Strict project rules

1. Use Flutter.
2. Keep architecture **simple** and Android-friendly — no heavy frameworks unless asked.
3. Act as a **patient mentor**: write the code, explain in plain English, avoid jargon.
4. API keys must be entered in-app Settings and stored with **secure storage** — never committed to Git.
5. Do **not** invent app-store / Play Store requirements; this app stays private.
6. After completing work, **update this file** (status, done, next).
7. Prefer **SillyTavern-inspired** features that fit mobile; do not chase full ST feature parity.

---

## Current status

**Phase:** 8 — Nice-to-haves ✅

**Last updated:** 2026-07-17  
**Last agent action:** Completed Phase 8 — group chats, Continue/Impersonate, Author's Note, theme polish, TTS, desktop smoke notes.

### What works today

- Full SillyTavern-inspired core through Phase 7 (cards, lore, sampling, import/export)
- **Continue** — generate the next character line without typing
- **Impersonate** — AI writes your next line as {{user}}
- **Author's Note** — per-chat instructions injected each turn
- **Group chats** — pick 2+ characters; round-robin replies with speaker labels
- **Theme** — system / light / dark in Settings; rounded mobile UI polish
- **TTS** — optional “Speak” on long-press (device voice); enable in Settings
- **Smoke:** `flutter test` + `flutter analyze` pass; Android debug APK builds

### What does NOT work yet / limits

- Linux desktop build needs apt packages (cmake/clang/ninja/pkg-config) — not installed on this PC
- Windows build only on a Windows host (this machine is Linux)
- Group chats are simple round-robin (not full ST group orchestration)
- Avatar image UI still deferred (PNG export uses teal placeholder)
- Recursive lore scanning still off

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

### Phase 4 — Persistence & chat controls (ST core feel) ✅

Goal: chats that stick around and feel controllable like SillyTavern’s basics.

- [x] Save chat history **per character** on device
- [x] Optional: multiple named chats per character (ST “new chat”)
- [x] Streaming responses (SSE) from NanoGPT
- [x] First message / greeting when starting a chat
- [x] Basic message actions: edit, delete, regenerate last reply
- [x] Swipes (alternate generations for the last AI message)

### Phase 5 — Richer character cards (ST card fields) ✅

Goal: characters closer to SillyTavern cards, still simple to edit on phone.

- [x] Split fields: description, personality, scenario, first message, example dialogue
- [x] Alternate greetings (pick/swipe opening)
- [x] Simple macros: `{{user}}`, `{{char}}`
- [x] User persona (your name + short description injected into prompts)
- [ ] Optional avatar image per character (local file) — deferred
- [x] Import Character Card V1/V2/V3 JSON + PNG (`chara`/`ccv3`) *(pulled forward from Phase 7)*
- [x] Export Anima characters to ST-compatible V2/V3 JSON *(pulled forward from Phase 7)*

### Phase 6 — Lorebooks / World Info (ST signature feature) ✅

Goal: keyword-triggered lore so long worlds don’t dump everything into every prompt.

- [x] Lorebook entries: keys, content, on/off, order
- [x] Bind a lorebook to a character (embedded `character_book`; chat-level books deferred)
- [x] Scan recent messages for keys and inject matching entries
- [x] Simple token/entry budget so prompts stay small on mobile
- [x] Play back embedded `character_book` already stored on imported cards

### Phase 7 — Import / export & sampling ✅

Goal: bring characters in/out of the SillyTavern ecosystem; tune generation.

- [x] Import Character Card V2/V3 JSON (PNG-with-embedded-JSON supported)
- [x] Export Anima characters to ST-compatible JSON
- [x] Export/import chat transcripts
- [x] Sampling settings: temperature, max tokens, top_p (saved in Settings)
- [x] Optional NanoGPT subscription base URL toggle
- [x] Optional: export PNG with embedded `chara` chunk

### Phase 8 — Nice-to-haves ✅

- [x] Group chats (simple multi-character round-robin)
- [x] Continue / impersonate
- [x] Author’s Note / chat-level instructions
- [x] Basic theming / nicer mobile layout polish
- [x] Windows / Linux smoke tests (documented; Linux needs deps, Windows needs Windows host)
- [x] TTS (optional device voice via `flutter_tts`)

---

## Code map (keep this accurate)

```
lib/
  main.dart                         App entry, AnimaTheme, theme refresh
  theme/
    anima_theme.dart                Light/dark Material 3 polish
  models/
    chat_message.dart               Bubble + swipes + optional speaker
    chat_session.dart               Thread + authorsNote + group participants
    character.dart                  ST-compatible card fields (+ Anima id)
    lorebook.dart                   CharacterBook / World Info entries
  screens/
    chat_screen.dart                Chat UI + ST actions + group + TTS
    characters_screen.dart          List / import / export (JSON + PNG)
    character_edit_screen.dart      Full card field editor (+ lorebook button)
    lorebook_edit_screen.dart       World Info entry list + entry editor
    settings_screen.dart            API, sampling, persona, theme, TTS
  services/
    api_key_service.dart            Secure storage for NanoGPT API key
    settings_service.dart           Model, persona, sampling, theme, TTS flag
    character_service.dart          Load/save characters JSON on device
    character_card_codec.dart       ST Card V1/V2/V3 + PNG import/export
    prompt_builder.dart             System prompt, modes, group, authors note
    lorebook_service.dart           Keyword scan, budget, before/after blocks
    chat_service.dart               Chats per character + group bucket
    chat_transcript_codec.dart      Chat JSON / plain-text import/export
    nanogpt_service.dart            Streaming + sampling + plain-English errors
    tts_service.dart                Optional flutter_tts wrapper
```

**Dependencies in use:** `flutter_secure_storage`, `http`, `path_provider`, `file_picker`, `share_plus`, `path`, `flutter_tts`

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
| Linux desktop toolchain | ❌ clang/cmake/ninja/pkg-config missing (needs `sudo apt install cmake ninja-build clang libgtk-3-dev pkg-config`) — `flutter build linux` fails until then |
| Windows desktop | ❌ Build only on a Windows host (`flutter build windows` refused on Linux) |
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

1. Use the app on your phone (`flutter run`) and try Continue / Impersonate / group chat / TTS.
2. Optional later: local avatar images, richer group orchestration, Linux desktop deps if you want desktop builds.

The core SillyTavern-inspired roadmap (Phases 0–8) is complete for a private Android-first app.

---

## How to update this document

When you finish work, edit these sections:

1. **Current status** — phase name, date, last agent action, what works / doesn't
2. **Build phases** — check off completed items
3. **Code map** — if you added/removed files
4. **Next actions** — replace with the true next steps

Do not delete historical phase checklists; mark them done so future agents see progress.
