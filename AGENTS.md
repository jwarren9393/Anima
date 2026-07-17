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

**Phase:** 0 — Project foundation (complete)

**Last updated:** 2026-07-16  
**Last agent action:** Created private GitHub repo `jwarren9393/Anima`, initial commit pushed to `main`. GitHub CLI installed to `~/.local/bin/gh`; logged in as jwarren9393.

### What works today

- Flutter app named `anima` (`com.anima.anima`) with Android, Linux, and Windows folders
- Welcome / chat placeholder screen
- Settings screen to save / clear NanoGPT API key via `flutter_secure_storage`
- Starter `NanoGptService` that can call NanoGPT (not wired into the chat UI yet)
- Internet permission on Android
- Secrets-safe `.gitignore` entries
- Private GitHub repo at https://github.com/jwarren9393/Anima (`main` branch)

### What does NOT work yet

- Real chat UI (message bubbles, send box, history)
- Character profiles / personality prompts
- Wiring the chat screen to `NanoGptService`
- Streaming replies
- Local message database
- Android SDK / phone deploy on this machine (Flutter doctor: Android toolchain missing)
- Linux desktop build tools (clang, cmake, ninja, pkg-config missing)

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

- [ ] Install Android Studio / Android SDK; fix `flutter doctor` Android issues
- [ ] Connect a phone (USB debugging) or set up an emulator
- [ ] Confirm `flutter run` on Android
- [ ] Optional: install Linux build deps for desktop testing
- [ ] Install `gh` and create a **private** GitHub repo; push initial commit

### Phase 2 — Real chat UI

- [ ] Message list + text input + send button
- [ ] Local in-memory conversation for one session
- [ ] Call `NanoGptService.sendChatMessage` from the chat screen
- [ ] Show loading / error states in plain language
- [ ] Default model setting (editable in Settings)

### Phase 3 — Characters

- [ ] Simple character model (name, system prompt, optional avatar later)
- [ ] Create / edit / select a character
- [ ] Persist characters on device (start simple: local files or lightweight DB)

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
  main.dart                      App entry, themes, home route
  screens/
    chat_screen.dart             Home placeholder + link to Settings
    settings_screen.dart         Paste/save/clear NanoGPT API key
  services/
    api_key_service.dart         flutter_secure_storage wrapper
    nanogpt_service.dart         HTTP client for /chat/completions
```

**Dependencies in use:** `flutter_secure_storage`, `http`

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
| Android SDK | ❌ Not installed yet |
| Chrome | ❌ Not required for this app |
| Linux desktop toolchain | ❌ clang/cmake/ninja/pkg-config missing |
| Git | ✅ installed |
| GitHub CLI (`gh`) | ✅ `~/.local/bin/gh` (logged in as jwarren9393) |

PATH tip for shells:

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
```

---

## Next actions (do these in order)

1. **Phase 1:** Install Android Studio / SDK so the owner can run Anima on their phone.
2. Confirm `flutter run` on a connected Android phone or emulator.
3. **Phase 2:** Build the real chat screen and connect it to NanoGPT.
4. Optional: install Linux build deps for desktop testing on this PC.

---

## How to update this document

When you finish work, edit these sections:

1. **Current status** — phase name, date, last agent action, what works / doesn't
2. **Build phases** — check off completed items
3. **Code map** — if you added/removed files
4. **Next actions** — replace with the true next steps

Do not delete historical phase checklists; mark them done so future agents see progress.
