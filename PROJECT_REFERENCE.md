# Anima — Complete Project Reference

> **Purpose:** Single document for external AI assistants (Gemini, ChatGPT, Claude, etc.) and humans who need the **full** picture of Anima — architecture, data, UI, mechanics, and NanoGPT integration.
>
> **Also read for day-to-day coding in Cursor:** [`AGENTS.md`](AGENTS.md) (living status, roadmap, agent rules).  
> **Also read for user-facing feature catalog:** [`README.md`](README.md) (screen-by-screen product guide).

**Last updated:** 2026-07-29 · **Version:** 1.0.0 build **39** · **Tests:** 211 (`flutter test`)

---

## Table of contents

1. [What Anima is](#1-what-anima-is)
2. [Architecture at a glance](#2-architecture-at-a-glance)
3. [Technology stack](#3-technology-stack)
4. [Security and secrets](#4-security-and-secrets)
5. [Repository layout](#5-repository-layout)
6. [Application bootstrap](#6-application-bootstrap)
7. [Data models](#7-data-models)
8. [Persistence and local files](#8-persistence-and-local-files)
9. [NanoGPT backend integration](#9-nanogpt-backend-integration)
10. [Prompt assembly (how a chat turn is built)](#10-prompt-assembly-how-a-chat-turn-is-built)
11. [Chat message types and steering tools](#11-chat-message-types-and-steering-tools)
12. [Regular chat mechanics](#12-regular-chat-mechanics)
13. [Group chat mechanics](#13-group-chat-mechanics)
14. [World Info / lorebooks](#14-world-info--lorebooks)
15. [Memory summary and auto-summarize](#15-memory-summary-and-auto-summarize)
16. [Character cards and personas](#16-character-cards-and-personas)
17. [Creation Center (workshops)](#17-creation-center-workshops)
18. [UI map — every major screen](#18-ui-map--every-major-screen)
19. [Settings hub — complete menu](#19-settings-hub--complete-menu)
20. [AI collaborator utilities](#20-ai-collaborator-utilities)
21. [Theming and chat experience](#21-theming-and-chat-experience)
22. [Backup, restore, and cross-device sync](#22-backup-restore-and-cross-device-sync)
23. [Import and export](#23-import-and-export)
24. [Avatars and image generation](#24-avatars-and-image-generation)
25. [Macros](#25-macros)
26. [Testing and quality](#26-testing-and-quality)
27. [Build, release, and desktop branding](#27-build-release-and-desktop-branding)
28. [Known limits and not implemented](#28-known-limits-and-not-implemented)
29. [Related documents](#29-related-documents)

---

## 1. What Anima is

**Anima** is a **private, personal** AI character roleplay chat app. It is **not** published to app stores.

| Item | Value |
|------|--------|
| Inspiration | **SillyTavern-like** RP on mobile — **not** a full SillyTavern clone |
| UI | **Flutter** (Android primary; Linux + Windows desktop) |
| AI backend | **[NanoGPT](https://nano-gpt.com)** — OpenAI-compatible chat + image APIs |
| Repo | Private: https://github.com/jwarren9393/Anima |
| Owner use | Personal only |

**Product rule:** Prefer high-value SillyTavern concepts that work on a phone. Do not chase full ST parity. Keep architecture simple.

---

## 2. Architecture at a glance

```
┌─────────────────────────────────────────────────────────────┐
│  Flutter app (Anima) — all logic on device                  │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────┐ │
│  │ Screens/UI  │→ │ Services     │→ │ Local JSON + secure │ │
│  │ widgets     │  │ prompt build │  │ storage (no server) │ │
│  └─────────────┘  └──────────────┘  └─────────────────────┘ │
└───────────────────────────┬─────────────────────────────────┘
                            │ HTTPS (user's API key)
                            ▼
              ┌─────────────────────────────┐
              │ NanoGPT API (cloud)         │
              │ /api/v1/chat/completions    │
              │ /api/v1/images              │
              │ model catalogs, credits     │
              └─────────────────────────────┘
```

- **No Anima backend server.** The app is a thick client.
- **No bundled API key.** User enters key in Settings → stored in `flutter_secure_storage`.
- **All chat history, cards, lore** live in app documents directory as JSON (+ avatar images).

---

## 3. Technology stack

| Layer | Choice |
|-------|--------|
| Framework | Flutter 3.x, Dart 3.x |
| State | `StatefulWidget` + services; `AppearanceController` for global theme |
| HTTP | `package:http` — streaming SSE + non-streaming `complete()` |
| Secrets | `flutter_secure_storage` |
| Paths | `path_provider` → app documents directory |
| Files | `file_picker`, `share_plus`, Android `saf` for sync URIs |
| Fonts | `google_fonts` |
| Tests | `flutter_test` — 211 tests |

**Platforms:** Android (primary), Linux desktop, Windows desktop. macOS not targeted.

---

## 4. Security and secrets

| Rule | Detail |
|------|--------|
| API key | **Never** in source, README examples, screenshots in git, or `.anima-backup`. Lives in the user library folder as `api_key.txt`. |
| Storage | User-owned Anima folder (`AppDataRoot`); default `Documents/Anima`. Hidden app storage only keeps a pointer to that folder. |
| Backup | Whitelist JSON export **excludes** API key on purpose (copy the folder if you want the key too) |
| Git | `android/local.properties` gitignored; never commit the Anima library folder |

If a key is ever committed: rotate NanoGPT key immediately and purge git history.

---

## 5. Repository layout

```
Anima/
  lib/                    # All Dart app code
    main.dart             # Entry: AppearanceController + MaterialApp
    models/               # Data classes + presets
    screens/              # Full-screen UI
    widgets/              # Reusable UI + sheets
    services/             # Business logic, API, persistence
    theme/                # ThemeData factory, glass backdrop
    utils/                # Platform, scroll, Windows paste
  test/                   # Unit/widget tests
  assets/branding/        # anima_icon.png (Android + desktop)
  android/ linux/ windows/ # Platform runners
  scripts/
    update_linux.sh       # Linux build + install
    update_windows.ps1    # Windows build + zip + optional gh release
  AGENTS.md               # Cursor agent living doc (status, roadmap)
  README.md               # User feature catalog
  PROJECT_REFERENCE.md    # This file — full encyclopedia
  pubspec.yaml            # version 1.0.0+NN (build number)
```

### `lib/` code map (authoritative paths)

**Models** (`lib/models/`)

| File | Role |
|------|------|
| `chat_message.dart` | Message bubble: `ChatRole` user / assistant / **narrator**; swipes; group speaker |
| `chat_session.dart` | Thread: messages, note, persona, lore picks, memory, opening scene, group cast |
| `character.dart` | ST-compatible card fields + Anima id + embedded lorebook |
| `persona.dart` | Structured {{user}} identity fields |
| `lorebook.dart` | World Info entries (ST import shapes) |
| `global_lorebook.dart` | Standalone lorebook id + enabled flag |
| `character_category.dart` | Anima-only category lists (not ST tags) |
| `world_workshop.dart` | Creation Center workshop state |
| `workshop_hub_models.dart` | Hub: play plan, kit, locations, relationships, scene ideas |
| `saved_opening_scene.dart` | Opening scenes library entries |
| `opening_scene_length.dart` | Short/Medium/Long AI hints (Creation Center) |
| `chat_experience_settings.dart` | Classic vs Storybook, backgrounds, bubble opacity |
| `ui_style_settings.dart` | Theme Studio + `AnimaUiTheme` extension |
| `theme_palette.dart` | Colors, fonts, 8 presets |
| `anima_presets.dart` | Sampling + text presets (Author's Note, guidance) |
| `workshop_chat_import_options.dart` | Toggles when seeding workshop from chat |
| `sync_target.dart` | Desktop path or Android content URI for sync file |

**Screens** (`lib/screens/`)

| File | Role |
|------|------|
| `home_screen.dart` | Chat history, Creation Center row, New FAB |
| `chat_screen.dart` | Main RP UI — largest file (~4000+ lines) |
| `group_chat_setup_screen.dart` | New/edit group cast |
| `characters_screen.dart` | Card list, import/export, categories |
| `character_edit_screen.dart` | Full card editor + lore + wand |
| `personas_screen.dart` | Persona list / pick-for-chat |
| `persona_edit_screen.dart` | Persona editor + wand + avatar |
| `lorebooks_screen.dart` | Global lorebook list |
| `lorebook_edit_screen.dart` | Entry list + entry editor |
| `lore_settings_screen.dart` | Scan depth/budget + link to global books |
| `world_workshop_list_screen.dart` | Creation Center list |
| `world_workshop_chat_screen.dart` | Workshop chat (NOT regular chat) |
| `opening_scenes_screen.dart` | Opening scenes library |
| `settings_screen.dart` | Settings hub |
| `api_settings_screen.dart` | API key, model catalog browser |
| `sampling_settings_screen.dart` | Temperature, context, auto-summarize |
| `collaborator_settings_screen.dart` | Wand, Format, Paths, **Narrator** notes |
| `character_build_settings_screen.dart` | Slim card JSON generation model |
| `global_chat_prompts_screen.dart` | App-wide system + post-history |
| `appearance_settings_screen.dart` | Theme Studio |
| `backup_restore_screen.dart` | Backup + cross-device sync |

**Services** (`lib/services/`)

| File | Role |
|------|------|
| `nanogpt_service.dart` | Streaming chat, `complete()`, catalogs, images, credits |
| `api_key_service.dart` | Secure API key |
| `settings_service.dart` | All preferences + `SamplingSettings` + `CollaboratorSettings` |
| `prompt_builder.dart` | System prompt, post-history, opening scene block, macros |
| `chat_context_service.dart` | History trim, memory summarize prompts |
| `chat_service.dart` | Save/load `anima_chats.json` |
| `character_service.dart` | `anima_characters.json` |
| `persona_service.dart` | `anima_personas.json` |
| `lorebook_service.dart` | Keyword scan, budget, injection |
| `world_info_service.dart` | `anima_lorebooks.json` |
| `narrator_service.dart` | Chat Narrator generate + prompt injection + output cleanup |
| `roadway_service.dart` | Paths brainstorm + combine |
| `roadway_cache_service.dart` | Per-chat cached path options |
| `message_formatter.dart` | Composer ✨ Format |
| `reply_rewrite_service.dart` | Rewrite reply modes |
| `character_collaborator.dart` | Character wand prompts |
| `persona_collaborator.dart` | Persona wand |
| `lore_collaborator.dart` | Lore entry wand + keyword suggest |
| `world_workshop_builder.dart` | All Creation Center AI prompts + JSON parsers |
| `world_workshop_service.dart` | Workshop persistence |
| `workshop_hub_service.dart` | Hub CRUD, bundle import/export |
| `workshop_hub_controller.dart` | Hub AI actions |
| `opening_scene_service.dart` | Opening scenes library |
| `composer_draft_service.dart` | Per-chat composer autosave |
| `chat_transcript_codec.dart` | Chat JSON / plain export |
| `character_card_codec.dart` | ST V1/V2/V3 + PNG chara chunk |
| `app_backup_service.dart` | `.anima-backup` whitelist |
| `sync_service.dart` | Single-file phone ↔ PC sync |
| `avatar_service.dart` | Local avatar files |
| `avatar_prompt_builder.dart` | Image prompt from card/persona text |
| `chat_background_service.dart` | User chat background images |
| `appearance_controller.dart` | Root theme reload |
| `speaker_prefix.dart` | Strip `Name:` from group AI replies |

---

## 6. Application bootstrap

`lib/main.dart`:

1. `AnimaBootstrap` loads `AppDataRoot` (user-owned library folder). First launch shows `DataFolderSetupScreen` if none is chosen.
2. Loads `AppearanceController` / `UiStyleSettings` from `anima_settings.json` in that folder.
3. Builds `ThemeData` via `anima_theme.dart`.
4. `MaterialApp` → `HomeScreen` with injected services (API key, chat, characters, etc.).

No global state management package — services passed as constructor args.

---

## 7. Data models

### `ChatMessage` (`chat_message.dart`)

| Field | Meaning |
|-------|---------|
| `id` | Stable id for edit/delete/swipe |
| `role` | `ChatRole.user`, `ChatRole.assistant`, or `ChatRole.narrator` |
| `text` | Visible text (current swipe for assistants) |
| `swipes` | Alternate AI generations (assistant only) |
| `swipeIndex` | Which swipe is shown |
| `speakerId` / `speakerName` | Group chat — who spoke (assistant) |

**API mapping:** `toApiMap()` → user/assistant only. **Narrator** messages are converted in `chat_screen._buildApiMessages()` to **system** blocks (see §10).

### `ChatSession` (`chat_session.dart`)

| Field | Meaning |
|-------|---------|
| `messages` | Ordered chat log |
| `authorsNote` | Per-chat instructions (post-history injection) |
| `personaId` | Which persona is {{user}} |
| `autoReply` | Send also triggers AI reply (default **off** for new chats) |
| `lorebookIds` | `null` = use global enabled books; list = override |
| `memorySummary` | Long-term folded story text |
| `memoryCoveredCount` | Messages already folded into memory |
| `openingScene` | Fixed narrator prose **above** message list (not in `messages`) |
| `openingSceneInPrompt` | Inject opening scene every turn (default on) |
| `openingSceneInMemory` | Opening scene folded into memory on first summarize |
| `participantIds` | Group cast (2+ = group) |
| `nextSpeakerIndex` | Round-robin / chip selection |
| `sourceWorkshopId` | Provenance from Creation Center |

### `Character` — SillyTavern-compatible card

Key fields: `name`, `description`, `personality`, `scenario`, `first_mes`, `alternate_greetings`, `mes_example`, `system_prompt`, `post_history_instructions`, embedded `character_book` (lore), `avatarFileName`.

### `Persona` — structured {{user}}

Fields: `name`, identity/role, appearance, personality, background, goals → `promptText` for system injection.

### `Lorebook` / entries

Keyword-triggered content; ST JSON import; scan depth, token budget, recursive scan, priority, selective keys.

### `WorldWorkshop` — Creation Center

Workshop chat messages, world summary, linked lorebook, opening scene, hub fields (kit, pins, glossary export, etc.). **Separate** from `ChatSession`.

---

## 8. Persistence and local files

All library files live in **one user-owned folder** (`AppDataRoot`, default `Documents/Anima`). Services resolve it through `appDocumentsDirectory()`. A pointer file in app-support storage remembers the path.

| File / folder | Contents |
|---------------|----------|
| `api_key.txt` | NanoGPT API key |
| `anima_settings.json` | Model ids, sampling, theme JSON, collaborator notes, sync URIs, etc. |
| `anima_active_persona_id.txt` | Default persona id |
| `anima_characters.json` | Character cards |
| `anima_character_categories.json` | Category lists |
| `anima_personas.json` | Personas |
| `anima_chats.json` | All chat sessions + messages |
| `anima_lorebooks.json` | Global lorebooks |
| `anima_world_workshops.json` | Creation Center workshops |
| `anima_composer_drafts.json` | Unsent composer text per chat id |
| `anima_roadway_cache.json` | Cached Paths options per chat |
| `avatars/` | Local avatar images |
| `chat_backgrounds/` | User-picked chat backgrounds |
| `README.txt` | Explains that this folder is the library |

**Backup** (`AppBackupService`): single `.anima-backup` JSON with whitelist above + settings keys + base64 avatars. **No API key.** Copy the whole Anima folder to move the key too.

**Sync** (`SyncService`): one user-chosen file (Google Drive on Android; path on desktop); push overwrites, pull restores.

---

## 9. NanoGPT backend integration

**Service:** `lib/services/nanogpt_service.dart`

### Endpoints

| Use | URL |
|-----|-----|
| Chat (pay-as-you-go) | `https://nano-gpt.com/api/v1/chat/completions` |
| Chat (subscription) | `https://nano-gpt.com/api/subscription/v1/chat/completions` |
| Images | `{base}/images` |
| Model catalog | Detailed text + image catalogs; provider routing stats |

**Auth:** `Authorization: Bearer <API_KEY>`

### Main operations

| Method | Use |
|--------|-----|
| `streamChatCompletion` | Regular chat + Creation Center — SSE streaming |
| `complete()` | One-shot: memory summarize, narrator generate, wands, Paths, JSON export, Format |
| `generateImage` | Avatar generation |
| `fetchTextModelCatalog` | Settings model picker + Browse models sheet |
| `fetchCreditUsage` | Remaining credits display |

### Streaming behavior

- User can **Stop** — partial text kept (`NanoGptCancelledException`).
- Chat list does **not** auto-scroll during streaming.

### Model catalog UI (`api_settings_screen.dart`)

- Category filter (incl. **Uncensored & derestricted (broad)** heuristic).
- Provider filter.
- **Browse models** sheet: context window, max output, params, TPS, TTFT, uptime, description, capabilities, pricing.

---

## 10. Prompt assembly (how a chat turn is built)

**Primary code:** `chat_screen.dart` → `_buildApiMessages()`  
**Helpers:** `prompt_builder.dart`, `lorebook_service.dart`, `chat_context_service.dart`, `narrator_service.dart`

### Order of messages sent to NanoGPT

1. **System:** `PromptBuilder.buildSystemPrompt()`  
   - Mode: `normal`, `continueScene`, or `impersonate`  
   - Card system prompt or Anima default seed  
   - Group: other member summaries  
   - Lore **before character** (keyword hits)  
   - Description, personality, scenario, example dialogue  
   - Lore **after character**  
   - Persona block  
   - Global system prompt (Settings)

2. **System (optional):** Opening scene block — if `openingSceneInPrompt` and text set

3. **System (optional):** Memory summary — clinical bullet facts via `ChatContextService.formatMemoryForPrompt()` (reference only; do not mimic tone)

4. **History:** `ChatContextService.selectHistory()` — recent messages within **history token budget** (skips messages already in `memoryCoveredCount` when possible)

   For each history message:
   - **Narrator** (`ChatRole.narrator`) → **system** block via `NarratorService.formatForPrompt()` (omniscient direction, not user/char speech)
   - **Group assistant** → `SpeakerName: body` (prefix stripped from body if duplicated)
   - **User / solo assistant** → `message.toApiMap()`

5. **Optional:** Rewrite messages (`ReplyRewriteService`) when regenerating with rewrite mode

6. **Optional nudges** (if not rewriting):
   - Greeting nudge (alternate opening)
   - Continue: `(Continue. Write only the next reply as …)`
   - Impersonate: `(Write only User's next message…)`

7. **System:** `PromptBuilder.buildPostHistory()`  
   - Global post-history  
   - Per-card post-history  
   - Author's Note

### Sampling

From **Settings → Generation parameters** (`SamplingSettings`): temperature, top_p, max_tokens, frequency/presence/repetition penalties.

Special tuned sampling for: memory summarize, narrator generate, composer format, some workshop exports.

---

## 11. Chat message types and steering tools

| Mechanism | Where it lives | How model sees it | Purpose |
|-----------|----------------|-------------------|---------|
| **Normal user send** | `ChatRole.user` in history | `role: user` | Player RP as {{user}} |
| **OOC** | User message `(OOC: …)` | `role: user` | Soft player direction (convention, not enforced system rule) |
| **Narrator** (theater icon) | `ChatRole.narrator` in timeline | `role: system` narrator block | Omniscient scene voice + direction |
| **Opening scene** | `ChatSession.openingScene` (above list) | `role: system` opening block | Fixed setup at chat start |
| **Author's Note** | `ChatSession.authorsNote` | Post-history system | Every-turn steer |
| **Memory summary** | `ChatSession.memorySummary` | System before history (clinical bullets; reference-only wrapper) | Long-term facts, not voice |
| **Lore hits** | Injected in system prompt | World info sections | Keyword-triggered facts |
| **Continue** | No new user line | Continue nudge user message | Next char reply |
| **Impersonate** | No user line | Impersonate nudge | AI writes {{user}} line |
| **Rewrite reply** | After AI bubble exists | Extra rewrite messages | Fix/regenerate that bubble only |
| **Paths** | Composer only | Not sent until user sends | Brainstorm {{user}} options |
| **Global prompts** | Settings | System + post-history | App-wide steer |

**Narrator sheet flow** (`narrator_sheet.dart`): optional **nudge** → editable **Narrator line** → **Generate** (AI) or type manually → **Post**. `NarratorService.buildGenerateMessages()` infers **present cast** from the last 10 chat lines (not full group roster); splits **current scene** vs **older background** transcript; direct prose, no sanitizing. Generate uses capped ~420 max tokens + `cleanGeneratedOutput()`.

**Not in Creation Center:** Narrator theater button is solo/group chat only.

---

## 12. Regular chat mechanics

**Screen:** `chat_screen.dart`

### Chrome

- App bar: Close · title · ⋮ menu
- Composer row: **Narrator** (theater) · **OOC** · text field · **✨ Format** · **▶ Continue** · Send/Stop
- Chips: Memory, Note (when set); group speaker chips (hidden when keyboard open)

### Message actions

- **Tap** bubble → edit text
- **Tap narrator card** → reopen narrator sheet
- **Long-press** → menu: Delete, Rewind, Branch, **Narrator**, Continue, Impersonate, Paths, Auto-reply, Rewrite/Regen/Swipe (AI only)
- **Quick swipe** ◀ 1/N ▶ on latest AI message

### Auto-reply

- Default **off**. Off = send only; use Continue or (group) tap name chip.
- On = send (and narrator post) also queue AI reply.

### Paths (Roadway)

- Long-press → **Paths** sheet (`_PathsSheet` in `chat_screen.dart`).
- `RoadwayService.buildMessages()` — first-person options only; recent chat labels player as **You (player):** not persona name.
- `RoadwayService.generateSampling()` — capped tokens + repeat penalties; `parseOptions()` dedupes; `normalizeUserPerspective()` fixes `*Name*` leaks.
- Cached per chat in `anima_roadway_cache.json` until anchor message changes or refresh.
- **Combine selected** — `buildCombineMessages()` merges 2+ picks into one composer draft.

### Auto memory summarize

- Runs in **background** (`_summarizing` flag) — UI stays usable.
- Threshold: Settings “summarize every N messages” since `memoryCoveredCount`.
- No chained back-to-back summarizes.

### Other

- Composer draft autosave per chat
- Lore hit toast overlay
- Context estimate (⋮ menu)
- Export/import transcript
- Manage cast, new/update character from chat

---

## 13. Group chat mechanics

- Storage bucket id separate from solo (`ChatService.groupsKey`).
- **Speaker chips:** pick next speaker; when auto-reply off, tap chip **always generates** that character's reply.
- **Group react** (`GroupReplyService` + sheet): one `complete()` call → parse `Name: reaction` lines → multiple assistant bubbles; capped sampling for brief beats; cast not in recent chat listed as silent.
- Prompt includes short summaries for other members.
- `speaker_prefix.dart` strips leading `Name:` from AI output to avoid duplicate headers.
- Optional custom **Chat name** on Home.

---

## 14. World Info / lorebooks

**Service:** `lorebook_service.dart` + `world_info_service.dart`

- **Global lorebooks** — enable/disable, import ST JSON, per-chat override.
- **Embedded `character_book`** on character cards — always when that character speaks.
- **Scan:** recent messages (depth setting) for keywords.
- **Budget:** token cap; priority ordering.
- **Recursive scan:** matched entry content can trigger further entries (toggle in Settings).
- **Toast:** “Lore Triggered: …” when entries inject.

Entry editor: AI wand on label/keywords/content; suggest keywords from content.

---

## 15. Memory summary and auto-summarize

- **Manual:** ⋮ → Memory summary (Scene + Ledger editor with pins) or Summarize now.
- **Two layers** (one stored string `memorySummary`):
  - **Scene** — Location / Present / Time. Replaced each summarize from the newest chunk (carried forward if the chunk does not mention a new place).
  - **Ledger** — durable Thread / Promise / Secret / Relationship / Goal / Item / Injury / Event. **Merged**, not rewritten. Newest does **not** win. Threads stay until explicitly resolved.
  - **Pins** — `[pin]` ledger lines; editor pin toggle; restored after AI if the model drops them.
- **Parser:** `MemorySummaryDocument` in `lib/models/memory_summary.dart`. Unlabeled old bullets: Location/Present → Scene, everything else → Ledger.
- **Auto:** Settings → summarize every N messages.
- **Injection:** `formatMemoryForPrompt()` wraps stored text as a **reference-only** system block before history — explicitly tells the model not to mimic summary tone/style. Presence filter keeps `##` headers and strips `[pin]` when matching witness tags.
- **Summarize prompt:** `memorySummarizeSystemPrompt` — two-section merge; protect `[pin]` and unresolved `Thread:`; must finish last bullet.
- **Caps:** ledger target grows with covered length (35–90 bullets); Scene ≤ 10. Sampling **1024–4096** (defaults **2048** when chat max_tokens unset/low); temperature ≤ **0.25**.
- **Fold:** older messages (keep recent N raw) via `buildSummarizeMessages()` + `finalizeSummarizeOutput()` (pin restore). Empty model output does **not** advance `memoryCoveredCount`.
- **Background:** does not block chat UI (`_summarizing` vs `_busy`).
- **Existing chats:** old flat bullets are classified on the next parse/summarize; run **Summarize now** to convert to Scene/Ledger.

---

## 16. Character cards and personas

### Characters

- Full ST field set; import/export JSON + PNG (`chara` / `ccv3`).
- **Categories** — Anima-only lists (multi-membership).
- **AI wand** on creative fields — appends text using `character_collaborator.dart`.
- **Consistency check** — read-only AI report.
- **Generate avatar** — NanoGPT image + `avatar_prompt_builder.dart`.
- **Character builds** (Settings) — separate model for **slim JSON** card generation (no scenario/greetings in that template).

### Personas

- Multiple {{user}} identities; default for new chats.
- Per-chat persona override (⋮ menu).
- Structured fields injected labeled in system prompt.

---

## 17. Creation Center (workshops)

**Not the same as regular chat** — `world_workshop_chat_screen.dart`

- Brainstorm worlds; export lorebook, opening scene, characters, persona.
- **World dashboard** hub: summarize, glossary, scene ideas, play plan, bundle import/export.
- **Fix last** chip — in-place correction on previous AI reply.
- **World summary** folding (like memory summarize).
- Workshop chat import from live chat with trim options.
- Linked lorebook in prompts **off by default** after create (toggle in ⋮).
- **No Narrator theater button** here.

Workshops listed on Home horizontal row + Settings → Creation Center.

---

## 18. UI map — every major screen

| Screen | Entry | Purpose |
|--------|-------|---------|
| Home | App start | History, Creation Center tiles, New FAB, Settings |
| Chat | Tap history row | Solo/group RP |
| Group setup | New → Group | Cast, order, lore/scene/note/auto chips |
| Characters | Settings / pickers | CRUD, import/export, categories |
| Character edit | Tap character | All card fields, lorebook tab, wand |
| Personas | Settings | CRUD, default persona |
| Lorebooks | Settings → World Info | Global books list |
| Lorebook edit | Tap book | Entries + wand |
| Lore settings | Settings | Scan depth, budget, recursive |
| Opening scenes | Settings | Saved opening setups |
| Creation Center list | Home / Settings | Workshops |
| Workshop chat | Tap workshop | World building chat |
| Settings hub | Gear | All settings menus |
| API settings | Banner / hub | Key, models, credits |
| Sampling | Settings | Generation parameters |
| AI collaborator | Settings | Wand, Format, Paths, Narrator notes |
| Character builds | Settings | Card JSON model |
| Global chat prompts | Settings | System + post-history |
| Appearance | Settings | Theme Studio |
| Backup & sync | Settings | .anima-backup + sync file |

---

## 19. Settings hub — complete menu

| Menu item | Screen |
|-----------|--------|
| API & connection (banner) | `api_settings_screen.dart` |
| Personas | `personas_screen.dart` |
| Characters | `characters_screen.dart` |
| Opening scenes | `opening_scenes_screen.dart` |
| World Info & lore | `lore_settings_screen.dart` → lorebooks |
| Creation Center | `world_workshop_list_screen.dart` |
| Generation parameters | `sampling_settings_screen.dart` |
| AI collaborator | `collaborator_settings_screen.dart` |
| Character builds | `character_build_settings_screen.dart` |
| Global chat prompts | `global_chat_prompts_screen.dart` |
| Appearance | `appearance_settings_screen.dart` |
| Backup, restore & sync | `backup_restore_screen.dart` |

---

## 20. AI collaborator utilities

**Settings:** `collaborator_settings_screen.dart` — four configurable areas:

| Note | Used by |
|------|---------|
| **Wand guidance** | Character/lore wands, Creation Center creative calls |
| **Composer Format** | Chat ✨ Format (low temperature) |
| **Roadway / Paths** | Paths brainstorm + combine |
| **Narrator** | Chat Narrator **Generate** (capped tokens + cleanup) |

Plus **Enter to send** toggle (desktop).

### One-shot AI helpers (non-streaming `complete()`)

| Feature | Service |
|---------|---------|
| Composer Format | `message_formatter.dart` |
| Paths | `roadway_service.dart` |
| Narrator Generate | `narrator_service.dart` |
| Rewrite reply | `reply_rewrite_service.dart` |
| Memory summarize | `chat_context_service.dart` |
| Character/lore wand | `character_collaborator.dart`, `lore_collaborator.dart` |
| Workshop exports | `world_workshop_builder.dart` |

---

## 21. Theming and chat experience

**Theme Studio** (`appearance_settings_screen.dart` + `ui_style_settings.dart`)

- 8 presets (glass + solid); custom colors/fonts.
- **Classic** vs **Storybook** chat layout.
- Chat background image + blur; bubble opacity.
- Speaker name above messages; side hero portrait (Storybook).
- RP colors: `*actions*` gold italic, `"dialogue"` bolder.
- Avatar shape/size scale.

`AppearanceController` reloads `MaterialApp` theme on save.

---

## 22. Backup, restore, and cross-device sync

See §8. User must **re-enter API key** after restore.

---

## 23. Import and export

| Asset | Format |
|-------|--------|
| Character card | ST JSON, PNG with embedded JSON |
| Chat | `anima_chat_v1` JSON or plain `Name: text` |
| Lorebook | ST World Info JSON |
| Full app | `.anima-backup` |
| Workshop | World bundle (hub) |

---

## 24. Avatars and image generation

- Local files in `avatars/`; referenced by filename on card/persona.
- **Generate avatar** sheet — NanoGPT image model from Settings.
- Prompt built from appearance-focused lines (~1150 char cap).
- Tap avatar → fullscreen viewer; long-press in chat → edit card/persona.

---

## 25. Macros

| Macro | Replaces with |
|-------|----------------|
| `{{user}}`, `<USER>` | Active persona name |
| `{{char}}`, `<BOT>` | Speaking character |
| `{{original}}` | In card system prompt → Anima default seed |

Applied in `PromptBuilder.applyMacros()`.

---

## 26. Testing and quality

```bash
flutter test      # 211 tests
flutter analyze
```

Tests cover: lore scan, prompt builders, card codec, backup, sync, narrator cleanup, model catalog, workshop JSON parsers, etc.

**Agent rule:** Run tests after meaningful changes; update `AGENTS.md` status.

---

## 27. Build, release, and desktop branding

| Platform | Command |
|----------|---------|
| Android APK | `flutter build apk --release` |
| Windows | `.\scripts\update_windows.ps1 -Zip` |
| Linux | `./scripts/update_linux.sh` |

- Version: `pubspec.yaml` → `1.0.0+NN` (NN = build number).
- Releases: GitHub `v1.0.0` tag — APK + Windows zip (assets overwritten per build).
- Icon: `assets/branding/anima_icon.png` → Android, Windows exe, Linux bundle.

---

## 28. Known limits and not implemented

- Not full SillyTavern group orchestration.
- NovelAI / Agnai / Risu lore converters not implemented (ST JSON works).
- No TTS (removed).
- Backup not encrypted.
- PNG export needs PNG avatar for embedded image.
- Windows build requires Windows host.
- Back-burner: undo send, last-chat resume, pinned mood chips, memory preview panel, etc.

---

## 29. Related documents

| File | Audience | Contents |
|------|----------|----------|
| **`PROJECT_REFERENCE.md`** (this file) | External AI, deep onboarding | Full technical encyclopedia |
| **`AGENTS.md`** | Cursor coding agents | Current status, roadmap, code map, machine notes, next actions |
| **`README.md`** | Human owner | Screen-by-screen feature catalog, install, release history |

**How to feed Gemini / external AI:**

1. Attach or paste **`PROJECT_REFERENCE.md`** for full context.
2. Optionally add **`AGENTS.md`** for latest build status and agent conventions.
3. For UI-only questions, **`README.md`** sections 1–4 are enough.

---

*End of PROJECT_REFERENCE.md*
