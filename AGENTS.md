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

**Phase:** 5 — Richer character cards + ST import/export ✅

**Last updated:** 2026-07-17  
**Last agent action:** Committed and pushed Phases 4–5 (persistence/chat controls + ST card fields/import-export) to GitHub `main`.

### What works today

- SillyTavern-inspired chat app (saved chats, streaming, swipes, regenerate, edit/delete)
- **Character cards** with ST fields: description, personality, scenario, first_mes, mes_example, system_prompt, post_history_instructions, alternate_greetings, tags, creator notes, etc.
- **Import** SillyTavern / site cards: `.json` (V1/V2/V3) and `.png` (embedded `chara` / `ccv3` chunk)
- **Export** Card V2 or V3 JSON (share sheet) — lorebook + extensions preserved
- **Persona** in Settings (`{{user}}` name + about-you text)
- **Macros** `{{user}}` / `{{char}}` in card text and greetings
- Alternate greetings become first-message swipes on new chats
- Embedded `character_book` kept for later Phase 6 lore playback

### What does NOT work yet

- Lorebook / World Info playback (Phase 6) — books are stored but not injected yet
- PNG *export* with embedded card (JSON export works; PNG import works)
- Optional local avatar image UI
- Sampling knobs / chat transcript import (rest of Phase 7)

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

### Phase 6 — Lorebooks / World Info (ST signature feature)

Goal: keyword-triggered lore so long worlds don’t dump everything into every prompt.

- [ ] Lorebook entries: keys, content, on/off, order
- [ ] Bind a lorebook to a character (and/or to a chat)
- [ ] Scan recent messages for keys and inject matching entries
- [ ] Simple token/entry budget so prompts stay small on mobile
- [ ] Play back embedded `character_book` already stored on imported cards

### Phase 7 — Import / export & sampling

Goal: bring characters in/out of the SillyTavern ecosystem; tune generation.

- [x] Import Character Card V2/V3 JSON (PNG-with-embedded-JSON supported)
- [x] Export Anima characters to ST-compatible JSON
- [ ] Export/import chat transcripts
- [ ] Sampling settings: temperature, max tokens, top_p (saved in Settings)
- [ ] Optional NanoGPT subscription base URL toggle
- [ ] Optional: export PNG with embedded `chara` chunk

### Phase 8 — Nice-to-haves (only if requested)

- [ ] Group chats
- [ ] Continue / impersonate
- [ ] Author’s Note / chat-level instructions
- [ ] Basic theming / nicer mobile layout polish
- [ ] Windows / Linux smoke tests
- [ ] TTS or other ST-like extensions (lowest priority)

---

## Code map (keep this accurate)

```
lib/
  main.dart                         App entry, themes, wires services → ChatScreen
  models/
    chat_message.dart               Bubble + swipe variants
    chat_session.dart               Saved chat thread
    character.dart                  ST-compatible card fields (+ Anima id)
  screens/
    chat_screen.dart                Chat UI, streaming, swipes, persistence
    characters_screen.dart          List / import / export / select characters
    character_edit_screen.dart      Full card field editor
    settings_screen.dart            API key + model + persona
  services/
    api_key_service.dart            Secure storage for NanoGPT API key
    settings_service.dart           Model, selected character, persona
    character_service.dart          Load/save characters JSON on device
    character_card_codec.dart       ST Card V1/V2/V3 + PNG import/export
    prompt_builder.dart             System prompt + {{user}}/{{char}} macros
    chat_service.dart               Load/save chats JSON per character
    nanogpt_service.dart            Streaming + plain-English errors
```

**Dependencies in use:** `flutter_secure_storage`, `http`, `path_provider`, `file_picker`, `share_plus`, `path`

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

1. **Phase 6:** World Info / lorebook playback (including embedded `character_book` from imports).
2. Optional: avatar images; PNG card export; sampling settings; Linux desktop deps.

---

## How to update this document

When you finish work, edit these sections:

1. **Current status** — phase name, date, last agent action, what works / doesn't
2. **Build phases** — check off completed items
3. **Code map** — if you added/removed files
4. **Next actions** — replace with the true next steps

Do not delete historical phase checklists; mark them done so future agents see progress.
