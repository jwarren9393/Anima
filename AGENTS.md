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
9. Later / optional: group chats, advanced prompt templates, regex

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

**Phase:** Post-roadmap tweaks

**Last updated:** 2026-07-29  
**Last agent action:** Published **v1.0.0 build 32** — Creation Center hub, minimal UI pass, workshop folding/Fix last, comprehensive README.

### What works today

- **Home screen** — chat history; **Creation Center** row (continue tile merged into horizontal world tiles); **New** FAB opens sheet (solo / group / workshop); chat rows show preview + date when available
- **Chat screen** — **minimal chrome**: Close · title · ⋮ (saved chats + new chat in menu); composer icon row (OOC · field · ✨ · ▶ · send/stop); Memory/Note chips when set; group speaker chips hide when keyboard open
- **Group chat setup** — cast + order on main form; **Lore / Scene / Note / Auto-reply** chips open sheets (no inline lore checkboxes or long prose fields)
- **New chat** — choose **Solo** or **Group**; if the character has several greetings, a **Choose opening** sheet picks which one starts (others stay as swipes); then an optional **Opening scene** sheet — pick a saved scene, browse **Opening scene library**, type fresh prose, or skip
- **Opening scene (narrator)** — per-chat optional prose in a centered narrator card above messages (not a character bubble); **always injected into prompts by default** (turn off via ⋮ → **Stop injecting opening scene** to save tokens); on the **first memory summarize**, the scene is folded into the memory summary so it stays in long-term context; edit via ⋮ → **Opening scene**; works in solo and group; separate from card **Scenario** (still injects every turn)
- **Opening scenes library** — **Settings → Opening scenes** lists saved narrator setups (create / edit / delete); scenes from Creation Center **auto-sync** when you save or AI-generate an opening scene there; also imported when starting a new chat or opening the library; included in backup
- **Settings hub** — separate menus:
  - **Personas** — create multiple {{user}} identities with separate identity/role, appearance, personality, background, goals, and photo fields; **AI wand** on creative fields (appends text like Characters); **Generate avatar** from persona details; set a default for new chats; all filled fields are labeled and sent on every chat generation
  - **Characters** — character cards + **categories**; filter; consistency check; AI card builder; **section chips** (Identity / Story / Chat / Lore / Advanced); avatar + consistency in ⋮ menu
  - **World Info & lore** — **global lorebooks** (create / import ST JSON / export / on-off) + scan depth/budget + link to per-character books; **entry AI wand** + **Suggest keywords from content**
  - **Opening scenes** — saved narrator setups for new chats (manual + synced from Creation Center workshops)
  - **Creation Center** — hub on Home + Settings; minimal workshop chrome; world summary folding; **Fix last** chip applies a correction to the previous AI reply in place (no new AI bubble); long-press → Apply correction; delta-style revision prompts
  - **AI collaborator** — wand guidance note + **Composer Format** note + **Roadway / Paths** note
  - **Character builds** — model, max tokens, temperature, top P, and prompt for **slim card JSON** generation (description, personality, mes_example, tags only — no scenario, greetings, or per-card system/post-history; Creation Center + New character from chat); separate from main chat model
  - **Global chat prompts** — app-wide **system prompt** + **post-history** merged into every chat (on top of each card; per-chat Author's Note still applies); preset pickers; `{{user}}` / `{{char}}`
  - **Appearance (Theme Studio)** — live preview + **category chips** (Presets / Layout / Colors / Fonts / Chat / Avatars); one section visible at a time
  - **Backup & restore** — one `.anima-backup` JSON file (chats, characters, personas, categories, lorebooks, workshops, opening scenes, drafts, roadway cache, avatars, settings); **API key is not included** — re-enter after restore; on Linux/Windows Create backup opens a **Save** dialog (Downloads suggested); Android still uses the share sheet; restore replaces Anima data only (whitelist), then returns to Home; **Cross-device sync** — pick one sync file in Google Drive (or a synced folder on desktop); **Push to cloud** overwrites that file in place; **Pull from cloud** restores from it when switching phone ↔ PC (no delete-and-reupload)
  - API, Generation parameters
- **Look** — Theme Studio with glass and solid presets (default Obsidian Gold soft-glow, no sparkle texture); Ivory Ink light preset + full color/font customization
- **Generation parameters** — detailed help + many sampling presets; **context size in tokens** + presets (1K–24K); **auto-summarize** every N messages
- **Memory summary** — per chat (⋮ → Memory summary to edit; Summarize now); injected into prompts; auto-updates when enabled; **smarter folding** — revises stale facts, tracks key changes, uses a lower temperature + **2048-token floor** for summarize calls; **first summarize** also folds the opening scene into memory when one is set
- **Text presets** — expanded Author’s Note / System prompt / Post-history / collaborator guidance sheets
- **Character AI wand** — sparkle icon on creative card fields; sends all filled fields as context; appends NanoGPT text below what’s already there (uses chat model + sampling)
- **World Info entry AI wand** — sparkle on Label / Keywords / Lore content (and Secondary keywords when Selective); uses book + sibling entry context; appends (keywords merge comma-separated); same model + collaborator guidance
- **API & connection** — live NanoGPT model catalog: **Auto** provider (auto-model / basic / standard / premium) listed first, then providers A–Z; refresh; custom model id; subscription toggle reloads catalog; model dropdown shows **context window** when NanoGPT reports `context_length`; **image model** picker uses NanoGPT’s subscription image catalog when **Use subscription API** is on (hides paid models); otherwise full catalog with Paid/Included labels; **See remaining credits** shows wallet USD/NANO + weekly/daily/monthly + daily images allowance data returned by NanoGPT
- **Chat stop** — while a reply streams, the send button becomes **Stop** (keeps any partial text); the list does **not** auto-scroll during streaming — scroll freely while a reply types in (regular chat + Creation Center)
- **Composer shortcuts** — **OOC**, **Format** (✨), **Continue** (▶), Send/Stop; Format has its own collaborator note; **desktop:** Enter sends (Shift+Enter = new line; toggle in **Settings → AI collaborator**)
- **Draft autosave** — composer text saved per chat (survives leaving chat/app); cleared on send
- **Character categories** — Anima-only lists (not ST card tags); **All characters** master view + custom categories; filter in Characters (manage/pick) and Group setup; membership via row menu → Categories
- **Paths (Roadway)** — long-press a message → **Paths** (sheet + ✨ generate); tap a tile → composer; check **two or more** + **Combine selected** to AI-merge them into one composer draft; options **stay cached** until the chat moves on, or you clear / refresh; note under AI collaborator
- **Auto-reply** — long-press → toggle; **new chats default to off** (send alone; Continue or tap a name for a reply)
- **RP message look** — bubbles style `*narration*` in soft italic gold and `"spoken lines"` in bolder text
- **Message actions** — **tap** a bubble to edit; **long-press** for Delete, Rewind, Branch, Continue, Impersonate, Paths, Auto-reply, **Rewrite reply…** (shorten / expand / mood / custom — replace or new swipe), Regenerate / New swipe on **any** AI bubble (Delete / Rewind save immediately; branch still runs immediately)
- **Lore hit toast** — when keywords match and entries fit the budget, a brief top overlay shows “Lore Triggered: …”
- **Memory toast** — auto-summarize success shows “Memory summary optimized”
- **Recursive lore scanning** — Settings toggle works: matched entry content can pull further active entries; shared token budget + priority still apply
- **Quick swipe** — on the **latest** AI message, ◀ **1/N** ▶ always shows; ▶ on the last version generates a new swipe (older multi-swipe bubbles still show arrows to browse only)
- **Clean chat chrome** — no Swipe/Regen/Continue bar under messages (those live in the long-press menu; compact swipe arrows under bubbles)
- **Per-chat persona** — in a chat, ⋮ menu → **Persona: …** to switch who you are for that thread (saved on the chat)
- **Per-chat World Info** — ⋮ menu → **World Info: …** to use Settings default, pick specific global lorebooks, or turn global lore off for this thread (character card lore still applies)
- **Group chat controls** — tap a character name chip to choose who speaks next and **always generate their reply** when auto-reply is off (even re-tapping the same chip); auto-reply off by default (send only; tap a name or Continue for a reply; toggle via long-press); leading `Name:` is stripped from replies so the bubble header isn’t duplicated
- **Manage cast (mid-chat)** — ⋮ → **Rename chat** (groups) or **Manage cast** adds/removes characters in the **current** chat (solo or group) without starting over; group setup includes an optional **Chat name** field; ⋮ → **New character** opens a sheet to **type a name + generate from chat** or start blank; ⋮ → **Update character from chat** revises one saved card from the thread (cast listed first; optional change notes); manage screen **+** uses the same flow when editing cast
- **Avatars** — persona + character photos; **Generate avatar** on character and persona create/edit (and Creation Center character review) uses NanoGPT image models + an **auto prompt** that keeps the portrait framing but pulls only appearance-relevant lines from the card (skips scenario, backstory, and long personality blocks; stays under ~1,150 chars); prompt is still editable in the sheet; **tap any avatar** (chat, character list, editor, home) for a **full-screen portrait** — tap again (or ✕) to close; in chat, **long-press** an avatar to edit persona / character card; PNG card import still grabs the card image; chat bubble shape/size via Appearance
- **Context estimate** — chat ⋮ → **Context estimate** shows ~message/token gauges vs history budget and model window; Creation Center shows a live banner estimate
- **Chat screen** — Close returns home; bubbles use the chat’s persona avatar
- **Linux install/update** — `./scripts/update_linux.sh` builds and installs the desktop app; add `--pull` to download GitHub changes first
- **Smoke:** `flutter test` (190) + `flutter analyze` pass; Android + Linux desktop debug work

### What does NOT work yet / limits

- Linux desktop ✅ (F5 with device **Linux**); Windows build still needs a Windows host
- Group chats support manual next-speaker chips + auto-reply off (still simple, not full ST group orchestration)
- PNG export uses the character’s PNG avatar when available; JPEG/WebP avatars still fall back to the teal placeholder on PNG export
- NovelAI / Agnai / Risu lorebook converters not implemented (ST JSON + character_book shapes work)
- No TTS (removed — Speak was not useful enough to keep)
- Paths open from the long-press menu (not always on the composer chrome)
- Full-app backup is plain JSON (not encrypted) and skips the API key on purpose
- Back-burner QoL not started: undo send, last-chat resume, pinned Author’s Note / mood chips, memory preview, etc.

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
- [x] Structured user personas (identity, appearance, personality, background, goals injected into prompts)
- [ ] Optional avatar image per character (local file) — deferred
- [x] Import Character Card V1/V2/V3 JSON + PNG (`chara`/`ccv3`) *(pulled forward from Phase 7)*
- [x] Export Anima characters to ST-compatible V2/V3 JSON *(pulled forward from Phase 7)*
- [x] Local avatar images for persona + characters (pick photo; PNG import uses card image)

### Phase 6 — Lorebooks / World Info (ST signature feature) ✅

Goal: keyword-triggered lore so long worlds don’t dump everything into every prompt.

- [x] Lorebook entries: keys, content, on/off, order
- [x] Bind a lorebook to a character (embedded `character_book`)
- [x] **Global lorebooks** (standalone World Info — create / import / export / enable; apply across chats)
- [x] Scan recent messages for keys and inject matching entries (global + character books merged)
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
- [x] TTS (optional device voice via `flutter_tts`) — later removed; not in current build


---

## Code map (keep this accurate)

```
lib/
  main.dart                       App entry — AppearanceController + runtime ThemeData
  theme/
    anima_theme.dart              Settings-driven ThemeData factory
    glass_backdrop.dart           Configurable solid/gradient/soft-glow backdrop
  models/
    chat_message.dart             Bubble + swipes + optional speaker
    chat_session.dart             Thread + authorsNote + group + lorebookIds + autoReply + memorySummary + openingScene + openingSceneInMemory
    character.dart                ST-compatible card fields (+ Anima id)
    character_category.dart       Anima-only category lists + memberships
    lorebook.dart                 CharacterBook / World Info entries (+ ST import aliases)
    global_lorebook.dart          Standalone global lorebook (id + enabled + book)
    world_workshop.dart           Creation Center workshop + hub fields (summary, kit, sheets, pins)
    workshop_hub_models.dart      Modes, chat kit, locations, relationships, scene ideas
    opening_scene_length.dart     Short / Medium / Long hints for Creation Center opening-scene AI
    chat_experience_settings.dart Classic vs Storybook layout + background + bubble opacity + hero portrait
    chat_background_service.dart User-picked chat background images (chat_backgrounds/)
    saved_opening_scene.dart      Saved opening scene (title, text, optional workshop link)
    sync_target.dart              Sync file location (desktop path or Android URI)
    ui_style_settings.dart        Theme Studio settings + AnimaUiTheme extension + avatars
    theme_palette.dart            VisualStyle / BackgroundMode / fonts + 8 ThemePresets
    anima_presets.dart            Built-in sampling + text presets (Author’s Note, prompts, guidance)
    workshop_chat_import_options.dart Chat-import toggles (trimmed history, lore, cards)
  screens/
    home_screen.dart              Default landing — chat history + New chat Solo/Group
    chat_screen.dart              Chat UI + ST actions + group + persona switch
    group_chat_setup_screen.dart  New group: members, order, auto-reply, lore, note
    characters_screen.dart        List / categories / import / export (JSON + PNG)
    character_edit_screen.dart    Full card field editor (+ lorebook + avatar + AI wand)
    personas_screen.dart          Persona list / default / pick-for-chat
    persona_edit_screen.dart      Create/edit/review generated persona fields (+ AI wand + Generate avatar)
    lorebook_edit_screen.dart     World Info entry list + entry editor (+ AI wand)
    lorebooks_screen.dart         Global lorebook list / create / import / export
    world_workshop_list_screen.dart Creation Center list + import chat / lorebook (file / World Info)
    world_workshop_chat_screen.dart Workshop chat + opening scene + lorebook/characters/persona + start roleplay
    opening_scenes_screen.dart    Opening scenes library (Settings + browse from new-chat picker)
    settings_screen.dart          Settings hub (Personas + Characters + Creation Center + Opening scenes + AI collaborator + Backup)
    api_settings_screen.dart      API key, model catalog, subscription URL + remaining credits
    lore_settings_screen.dart     Global books + scan/budget + character books link
    sampling_settings_screen.dart ST-style generation parameters
    collaborator_settings_screen.dart AI wand + Format + Roadway notes
    character_build_settings_screen.dart Full card build model + sampling + prompt
    global_chat_prompts_screen.dart App-wide system prompt + post-history for all chats
    appearance_settings_screen.dart Theme Studio (presets + colors/fonts + avatars)
    backup_restore_screen.dart    Full-app backup / restore + cross-device sync (.anima-backup JSON; no API key)
    settings_ui.dart              Shared settings form helpers
  widgets/
    anima_avatar.dart             Local-file / initial avatar (circle or rect via style); tap → fullscreen
    avatar_fullscreen.dart        Full-screen portrait viewer (tap to dismiss)
    chat_hero_portrait.dart Tall side portrait with fade into storybook bubbles
    chat_image_background.dart Cached blurred image behind chat messages
    chat_composer_field.dart      Chat composer with optional Enter-to-send (Shift+Enter newline)
    generate_avatar_sheet.dart    Shared NanoGPT Generate avatar sheet (characters + personas)
    keyboard_inset.dart           Lift UI above keyboard (chat composers)
    rp_rich_text.dart             *action* / "dialogue" styled message text
    greeting_picker.dart          Multi-greeting sheet when starting a chat
    opening_scene_picker.dart     Optional opening-scene sheet when starting a chat (+ library browse)
    narrator_bubble.dart          Centered narrator card for per-chat opening scene
    workshop_overview_sheet.dart  Workshop dashboard bottom sheet
    minimal_chip_button.dart        Shared MinimalChipButton + MinimalChipRow
    workshop_compact_toolbar.dart   Workshop chip row (mode, length, scene, import, ideas)
    workshop_chat_import_sheet.dart Import-options sheet when seeding workshop from chat
    chat_lorebook_picker.dart     Per-chat global lorebook picker (chat ⋮ menu)
    character_category_controls.dart Category filter + manage / assign sheets
    preset_picker.dart            Preset button + bottom sheets (sampling / text)
    create_character_from_chat_sheet.dart Scan/generate character card from live chat context
    update_character_from_chat_sheet.dart Pick saved card + optional notes → merge update from chat
    reply_rewrite_sheet.dart      Rewrite reply mode picker (shorten / expand / mood / custom)
  utils/
    platform_utils.dart           Desktop platform detection (Windows / Linux / macOS)
    scroll_to_end.dart            Retry scroll-to-bottom for lazy chat lists
    windows_paste_handler.dart    Windows Ctrl+V / Shift+Insert paste + modifier cleanup
  services/
    api_key_service.dart          Secure storage for NanoGPT API key
    settings_service.dart         Model, image model, sampling, context, lore, Theme Studio, collaborator (+ legacy persona migrate)
    appearance_controller.dart    Root appearance state — save/reload notifies MaterialApp
    persona_service.dart          Multi-persona load/save + default active id
    avatar_service.dart           Local avatar files under documents/avatars
    avatar_prompt_builder.dart    Text prompt for NanoGPT character/persona avatar generation
    character_service.dart        Load/save characters JSON on device
    character_category_service.dart Anima-only category lists (multi-membership)
    character_card_codec.dart     ST Card V1/V2/V3 + PNG import/export
    character_collaborator.dart   Field-aware prompts + consistency-check report
    persona_collaborator.dart     Field-aware prompts for persona AI wand
    lore_collaborator.dart        Field-aware prompts + keyword-from-content suggest
    message_formatter.dart        Composer AI format (*actions* / "dialogue")
    reply_rewrite_service.dart    Rewrite-reply prompts for regen / new swipe
    roadway_service.dart          Paths / Roadway brainstorm + combine prompts + parse
  roadway_cache_service.dart    Per-chat cached Path options (survive sheet close)
  composer_draft_service.dart   Per-chat composer draft autosave
  speaker_prefix.dart           Strip leading "Name:" from AI replies (group immersion)
  chat_service.dart             Chats per character + group bucket (+ personaId, autoReply, lorebookIds)
    chat_context_service.dart     History trim + memory summarize helpers
    prompt_builder.dart           System prompt, modes, group, authors note
    lorebook_service.dart         Keyword scan, budget, merge global + character books
    world_info_service.dart       Persist global lorebooks (anima_lorebooks.json)
    world_workshop_service.dart   Persist Creation Center workshops + last-opened id
    workshop_hub_service.dart     Hub ops: play plan, bundle, duplicate, merge, status
    workshop_hub_controller.dart  AI hub actions (summarize, glossary, scenes, export)
    opening_scene_service.dart    Persist opening scenes library (anima_opening_scenes.json)
    sync_service.dart             Push / pull one sync file for phone ↔ desktop handoff
    world_workshop_builder.dart   Workshop prompts + hub JSON parsers
    chat_transcript_codec.dart    Chat JSON / plain-text import/export
    app_backup_service.dart       Full-app backup/restore (whitelist JSON + avatars; no API key)
    nanogpt_service.dart          Streaming + text/image model catalogs + image generate + credit usage + sampling + plain-English errors
scripts/
  update_linux.sh                 One-command Linux build/install + launcher; optional Git pull
  update_windows.ps1              Windows build + optional zip / GitHub Release upload (`-Zip`, `-Release`)
```

**Dependencies in use:** `flutter_secure_storage`, `http`, `path_provider`, `file_picker`, `share_plus`, `path`, `google_fonts`, `saf` (Android sync file access)  
**Dev / branding:** `flutter_launcher_icons`; master icon at `assets/branding/anima_icon.png`

---

## Security checklist for agents

- [ ] Never write API keys into source, README examples with real keys, screenshots committed to git, or `.env` files that get committed
- [ ] Prefer device secure storage (`ApiKeyService`) over SharedPreferences for secrets
- [ ] If a secret is ever committed by mistake: rotate the NanoGPT key immediately and purge it from git history
- [ ] `android/local.properties` stays gitignored (machine-specific SDK path)

---

## Machine notes (this developer PC)

### Windows (this PC)

| Tool | Status |
|------|--------|
| Flutter | ✅ 3.44.8 stable at `C:\src\flutter` |
| Dart | ✅ 3.12.2 |
| JDK | ✅ Temurin 17 at `C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot` |
| Android SDK | ✅ `%LOCALAPPDATA%\Android\Sdk` (platform 36, build-tools 36.0.0) — licenses accepted |
| Android Studio | ✅ Installed (SDK also set up via cmdline-tools) |
| Visual Studio | ✅ Build Tools 2022 + C++ workload |
| Git | ✅ `C:\Program Files\Git\cmd\git.exe` |
| GitHub CLI (`gh`) | ✅ installed — run `gh auth login` if not signed in |
| Chrome | ❌ Not required for this app |
| Developer Mode | ⚠️ Turn on in **Settings → System → For developers** (Flutter plugin symlinks on Windows) |
| Physical Android phone | Plug in + USB debugging → `flutter devices` / `flutter run` |

User env (set for this account): `JAVA_HOME`, `ANDROID_HOME`, `ANDROID_SDK_ROOT`, and `PATH` include Flutter, JDK, and Android tools. **Restart Cursor / open a new terminal** after setup.

```powershell
cd F:\AI\Anima
flutter doctor
flutter pub get
flutter run -d windows   # after Developer Mode is on
```

### Linux (alternate host)

| Tool | Status |
|------|--------|
| Flutter | ✅ 3.44.6 stable at `~/development/flutter` |
| Dart | ✅ 3.12.2 |
| JDK | ✅ Temurin 17 at `~/development/jdk-17` |
| Android SDK | ✅ `~/Android/Sdk` (platform 36, build-tools 36.0.0) |
| Linux desktop toolchain | ✅ cmake/ninja/clang/GTK + `libsecret-1-dev`; F5 (device: Linux) |
| GitHub CLI (`gh`) | ✅ `~/.local/bin/gh` (logged in as jwarren9393) |
| Physical Android phone | ✅ Samsung SM-S731U (`R3CYA09N26J`), Android 16 |

PATH tip for Linux shells:

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

1. Spot-check **Creation Center hub** on device: World dashboard, Play this world, canon pins, glossary → lorebook, world bundle import/export.
2. Spot-check **workshop Fix last** and **Fold older chat into summary** on a long workshop thread.
3. Spot-check **minimal UI** on phone: chat ⋮ menu, home New sheet, group setup Lore/Scene chips.

---

## How to update this document

When you finish work, edit these sections:

1. **Current status** — phase name, date, last agent action, what works / doesn't
2. **Build phases** — check off completed items
3. **Code map** — if you added/removed files
4. **Next actions** — replace with the true next steps

Do not delete historical phase checklists; mark them done so future agents see progress.
