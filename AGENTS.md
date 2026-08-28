# Anima — Agent Living Document

> **Mandatory for every agent session:** Read this file fully at the start.
> Update it before you finish any meaningful phase of work.
> Keep language clear enough that a coding beginner (the project owner) can follow it.
>
> **Full project encyclopedia (external AI / deep onboarding):** [`PROJECT_REFERENCE.md`](PROJECT_REFERENCE.md)

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
4. API keys must be entered in-app Settings and stored in the user **Anima folder** (`api_key.txt`) — never committed to Git.
5. Do **not** invent app-store / Play Store requirements; this app stays private.
6. After completing work, **update this file** (status, done, next).
7. Prefer **SillyTavern-inspired** features that fit mobile; do not chase full ST feature parity.

---

## Current status

**Phase:** Post-roadmap tweaks

**Last updated:** 2026-08-27  
**Last agent action:** Group chat handoff fix — after another cast member speaks, forced chip replies get a late “write ONLY as X” nudge so the model stops mimicking the previous speaker.

### What works today

- **Data folder** — one visible library folder for characters, chats, avatars, lore, settings, and the API key (`Documents/Anima` by default; change anytime in Settings). Android uses public Documents (My Files), not locked app storage; desktop can also keep `AnimaData` next to the app for a portable zip. First launch copies any older hidden files into that folder.
- **Chat screen** — **minimal chrome**: Close · title · ⋮; **voice row** above composer (You + cast) — **long-press a name** to write that character’s line manually; **Write line** / **Guide AI** toggle when a character is selected (Guide = loose player direction → fresh AI reply for that character only, no Director card); tap **You** to return to your persona; tap a name (when not writing as them) still forces an AI reply in groups; **Android:** **Director** + **Continue** sit above the composer (stay visible with the keyboard); **Director turns the same filled gold as Continue while it’s on**; **+** for Narrator / scene moods; composer row is field + send/stop; **desktop:** moods · Narrator · Director · field · ▶ · send/stop (Director icon fills gold when on). No delete confirmations or bottom toasts in chat (errors use the banner above the composer). **Narrator** / **Director** centered cards — tap to edit, **long-press to delete**; Director commands the next AI reply; solo/group chats only (not Creation Center)
- **Group chat setup** — cast + order on main form; **Lore / Note / Auto-reply** chips open sheets (no inline lore checkboxes or long prose fields)
- **New chat** — choose **Solo** or **Group**; **Solo:** pick character **and persona** on one screen (persona bar at top — tap to change); if the character has several greetings, a **Choose opening** sheet picks which one starts (others stay as swipes); **Group:** cast + lore + note as before
- **Settings hub** — separate menus:
  - **Personas** — create multiple {{user}} identities; **list may be empty**; **~token badges** on list + live count in editor; **Compact persona…** (editor menu, review before apply); **pick persona when starting solo or group chat** (defaults to app default or **Plain User**); per-chat switch in ⋮ menu; **AI persona builder**; **AI wand**; **Generate avatar**; optional default for new chats
  - **Characters** — character cards + **categories**; **list may be empty** (no forced starter card); **temporary characters**; **Full cards only** filter; filter; **consistency check + one-tap fix**; AI card builder; **section chips**; avatar + consistency in ⋮ menu; **~token badges**
  - **World Info & lore** — **global lorebooks** (create / import ST JSON / export / on-off) + **~token badges** on list and per-entry in editor; **Compact lorebook…** / per-entry **Compact entry…** with review sheet; scan depth/budget + link to per-character books; **consistency check + fix** on lorebook editor and Creation Center linked book; **entry AI wand** + **Suggest keywords from content**
  - **Creation Center** — hub on Home + Settings; minimal workshop chrome; composer **▶ Continue** (like main chat) when your last message needs a reply; **Stop** while streaming (keeps partial text); world summary folding; **Fix last** chip applies a correction to the previous AI reply in place (no new AI bubble); long-press → Apply correction; delta-style revision prompts; workshop chat uses dedicated guidance (not character-card wand text) + tuned sampling to reduce repetition loops; **Create lorebook** pre-flight audit (World Info gaps only) with optional **Fill gaps…** → per-entry preview sheet before export; **Create / Update lorebook** → review sheet (pick entries to save) before writing World Info; **Check lorebook consistency** (⋮ when linked) → report dialog → optional fix → review sheet; status banner + progress bar during lore operations; **Create / Update** character + persona pick **Standard** vs **Add more workshop details** merge style; generated card editors pass **Workshop** context to field wands
  - **AI collaborator** — wand guidance note + **auto-wrap dialogue on send** + **Roadway / Paths** + **Narrator** notes
  - **Character builds** — model, max tokens, temperature, top P, and prompt for **slim card JSON** generation (description, personality, mes_example, tags only — no scenario, greetings, or per-card system/post-history; Creation Center + New character from chat); separate from main chat model
  - **Global chat prompts** — app-wide **system prompt** + **post-history** merged into every chat (on top of each card; per-chat Author's Note still applies); preset pickers; `{{user}}` / `{{char}}`
  - **Appearance (Theme Studio)** — live preview + **category chips** (Presets / Layout / Colors / Fonts / Chat / Avatars); one section visible at a time
  - **Backup & restore** — one `.anima-backup` JSON file (chats, characters, personas, categories, lorebooks, workshops, drafts, roadway cache, avatars, settings); **API key is not included in that share file** (it already lives in your Anima folder as `api_key.txt`); on Linux/Windows Create backup opens a **Save** dialog (Downloads suggested); Android still uses the share sheet; restore replaces Anima data only (whitelist), then returns to Home; **Cross-device sync** — pick one sync file in Google Drive (or a synced folder on desktop); **Linux Files → Google Drive** works (Anima maps GNOME’s hidden file ID and **remounts Drive if it went idle**); **Push to cloud** overwrites that file in place; **Pull from cloud** restores from it when switching phone ↔ PC (no delete-and-reupload)
  - API, Generation parameters
- **Look** — Theme Studio with glass and solid presets (default Obsidian Gold soft-glow, no sparkle texture); Ivory Ink light preset + full color/font customization
- **Generation parameters** — detailed help + many sampling presets; **context size in tokens** + presets (1K–24K); **auto-summarize** every N messages
- **Memory summary** — per chat (⋮ → Memory summary); **Scene** (current place/cast, replaced each run) + **Ledger** (durable threads/promises/secrets — merged, not rewritten); **pin** ledger lines so summarize never drops them; unresolved **Thread:** kept until closed; **witness tags** on private facts; filtered per speaking character; auto-updates in background when enabled — **never overwrites chat messages** (swipe/regen stay safe while it runs)
- **Presence / scene law** — **always on for group chats** (solo skips history filtering) — knowledge boundaries:
  - **Narrator** resets who is **physically present**; only those names (+ you) hear private dialogue; **latest narrator scene brief is broadcast to all cast** (off-screen characters know location/situation but not whispered lines); **omniscient secret clauses** (“has no idea that…”, “neither does Ashley”) are **stripped per character** before injection so unaware cast never see the secret in the prompt
  - **Director** — active note sanitized the same way; mandatory direction includes **do not confess secrets** to unaware characters in dialogue
  - **Other characters' *asterisk* blocks** — **visible actions** (handshakes, groans, movement toward someone) stay in history for present cast; segments that read like **private internal monologue** are stripped; supports "alone with Mira", exclusions, **everyone** for full cast
  - **Narrator entrance once** — if anyone already spoke after the latest narrator card, the prompt switches to a **short backdrop** (location / who’s present) instead of re-injecting the full passage as mandatory scene law; older narrator and director cards are **omitted from API history** so long chats don’t rewind to a kitchen from 40 messages ago — use **Director** for beat-by-beat guidance within a scene
  - **Narrator movement deltas** — "Jay leaves" / "Jaisha comes back downstairs" apply on top of the previous scene (other cast stay unless they left); leavers are marked **NOT present**; arrival verbs assign the beat to that character so others must not steal it (e.g. Ashley reacts, Jaisha enacts the return)
  - **Your messages** — naming someone (`Mira, …`) → only they hear it; no names → only whoever is **currently present** in the scene (not the whole cast)
  - **Character lines** — only visible to those present when the line was sent
  - **Memory** — witness tags required on private facts (`Secret (known by …)`, `Event (witnesses: …)`); untagged Event/Secret lines hidden unless you're named
  - **Lore scan** uses filtered history per speaking character
  - Summarize prompt auto-tags witnesses using character names
- **Modern chat tone** — **always on, no settings** — `lol` / `lmao` / emojis from you are reactions or tone, not dialogue for characters to repeat; injected in every chat post-history block
- **Text presets** — expanded Author’s Note / System prompt / Post-history / collaborator guidance sheets
 - **Character AI wand** — sparkle on creative card fields; **tap** = quick expand from card; **long-press** = expansion level + optional **Workshop** or **Chat** transcript source (when opened from Creation Center or chat avatar edit); appends NanoGPT text below what’s already there
 - **Consistency check + fix** — ⋮ menu on character editor: AI report, then **Fix inconsistencies** → review changed fields → **Update card** (all card text fields; lorebook unchanged); **Compact card…** shortens verbose fields with review before apply
- **World Info entry AI wand** — sparkle on Label / Keywords / Lore content (and Secondary keywords when Selective); uses book + sibling entry context; appends (keywords merge comma-separated); same model + collaborator guidance
- **API & connection** — live NanoGPT model catalog: **Category** filter (All · **Uncensored & derestricted (broad)** · Roleplay · …) then **provider**; **Browse models** sheet shows context, max output, parameter size, TPS, TTFT, uptime %, description, capabilities, and pricing/Included — stats from `detailed=true` catalog + providers API; filtered count in status line; refresh; custom model id; subscription toggle reloads catalog; **image model** picker; **See remaining credits**
- **Chat stop** — while a reply streams, the send button becomes a red **Stop** button (keeps any partial text); status banner shows “Generating… tap Stop to cancel” in Creation Center; the list does **not** auto-scroll during streaming — scroll freely while a reply types in (regular chat + Creation Center)
- **Composer shortcuts** — **Android:** Director + Continue above the composer; **+** tools sheet (Narrator, scene moods, group react). **Desktop:** Narrator · Director · field · ▶ Continue · Send/Stop. **Character voice:** long-press cast chip → **Write line** (manual bubble) or **Guide AI** (loose direction → fresh reply for that character). **auto-wrap dialogue on send** (default on) wraps plain text in `"quotes"` between `*actions*` locally — no Format button; Memory/Note/Moods chips hide while the keyboard is open on mobile; **desktop only:** Enter to send; toggle auto-wrap in **Settings → AI collaborator**
- **Draft autosave** — composer text saved per chat (survives leaving chat/app); cleared on send
- **Character categories** — Anima-only lists (not ST card tags); **All characters** master view + custom categories; filter in Characters (manage/pick) and Group setup; membership via row menu → Categories
- **Paths (Roadway)** — long-press → **Paths**; first-person options (`*I…*` not persona name); dedupe + tuned sampling; tap → composer; **Combine selected**; cached until chat moves on or refresh; note under AI collaborator
- **Auto-reply** — long-press → toggle; **new chats default to off** (send alone; Continue or tap a name for a reply)
- **RP message look** — bubbles style `*narration*` in soft italic gold and `"spoken lines"` in bolder text
- **Message actions** — **tap** a bubble to edit; **long-press** for Delete, Rewind, Branch, Continue, Impersonate, Paths, Auto-reply, **Rewrite reply…** (custom, explicit / buildup / afterglow, moods, style — always new swipe), Regenerate / New swipe on **any** AI bubble (Delete / Rewind / regenerate run immediately with no confirm dialog)
- **Lore toast** — when keywords match and entries fit the budget, a brief **top** overlay shows “Lore Triggered: …” (does not cover the composer)
- **Recursive lore scanning** — Settings toggle works: matched entry content can pull further active entries; shared token budget + priority still apply
- **Quick swipe** — on the **latest** AI message, ◀ **1/N** ▶ always shows; ▶ on the last version generates a new swipe (older multi-swipe bubbles still show arrows to browse only)
- **Clean chat chrome** — no Swipe/Regen/Continue bar under messages (those live in the long-press menu; compact swipe arrows under bubbles)
- **Per-chat persona** — in a chat, ⋮ menu → **Persona: …** to switch who you are for that thread (saved on the chat)
- **Per-chat World Info** — ⋮ menu → **World Info: …** to use Settings default, pick specific global lorebooks, or turn global lore off for this thread (character card lore still applies)
- **Group chat controls** — **manual mode (default):** your message only; **Continue** and implicit generation pick the speaker from scene context (last reply, name in your text, etc.) — **no** round-robin “next in order” chip highlight; tap a name chip to **force** that character’s reply; **Group react** — composer **+** menu / cast chip / long-press message — one AI call → **one centered group-react card** with each character’s line + avatar; long-press for Delete/Rewind/etc.; regenerate avoids copying prior beats verbatim; auto-reply (optional, long-press toggle) still round-robins when on; leading `Name:` is stripped from solo replies
- **Manage cast (mid-chat)** — ⋮ → **Manage cast** (rename groups, add/remove cast); **+ menu → Add temporary character** (quick NPC) or full character; ⋮ → **Add temporary character**; ⋮ → **New character** / **Update character from chat**; manage screen **+** uses full or temporary flow
- **Avatars** — persona + character photos; **Generate avatar** saves each accept as history (`{id}_{timestamp}.png`) — **Avatar history…** (⋮ menu / History button) to reuse; changing avatar no longer deletes older files; accept also **exports a copy** (Gallery on Android · `Downloads/Anima Avatars` on desktop); long-press history tile to export/delete; **tap avatar** for fullscreen
- **Context estimate** — chat ⋮ → **Context estimate** shows full next-reply breakdown (speaker card, group snippets, World Info hits, persona/globals, memory, history) plus model window; Creation Center shows a live banner estimate
- **Character token badges** — ~token count beside names in **Characters**, character editor (live), group setup, and Creation Center cast pickers (≈1 token per 4 chars; color hints when large)
- **Persona + lorebook token badges** — same style on **Personas** list + editor; **global lorebooks** list; lorebook editor shows enabled-book total and per-entry content size
- **AI Compact** — character card, **persona**, whole lorebook, and individual lore entries; review sheet before apply
- **Chat screen** — Close returns home; bubbles use the chat’s persona avatar; **Scene moods** (mood icon + **+** menu) — includes **Intimate build-up**, **Explicit / graphic**, **Afterglow** with hard-coded **vocabulary law** (plain adult words; bans LLM euphemisms/tropes when those moods are on); **Chat copies** — per-chat character/persona overrides + **Chat lore** (thread-only World Info merged with global picks); long-press avatar edits chat copy (library unchanged)
- **Linux install/update** — `./scripts/update_linux.sh` builds and installs the desktop app; add `--pull` to download GitHub changes first
- **Smoke:** `flutter test` (341) + `flutter analyze` pass; Android + Windows + Linux desktop debug work

### What does NOT work yet / limits

- Linux desktop ✅ (F5 with device **Linux**); Windows desktop ✅ (`flutter run -d windows` on this PC)
- Group chats are manual-first (auto-reply optional); not full ST group orchestration
- PNG export uses the character’s PNG avatar when available; JPEG/WebP avatars still fall back to the teal placeholder on PNG export
- NovelAI / Agnai / Risu lorebook converters not implemented (ST JSON + character_book shapes work)
- No TTS (removed — Speak was not useful enough to keep)
- Paths open from the long-press menu (not always on the composer chrome)
- Full-app backup is plain JSON (not encrypted) and skips the API key on purpose
- Back-burner QoL not started: undo send, last-chat resume, pinned Author’s Note / mood chips, etc.
- Presence filtering uses narrator name mentions; very old memory without witness tags may leak until re-summarized; honorifics ("Your Majesty") don't match names — use narrator to establish who's present

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
    chat_message.dart             Bubble + swipes + optional speaker + groupBeat lines
    group_beat_part.dart          One character line inside a group-react card
    chat_session.dart             Thread + authorsNote + group + lorebookIds + autoReply + memorySummary + activeSceneMoodIds + characterOverrides + personaOverride + chatLorebook
    memory_summary.dart           Scene + Ledger parse/encode + [pin] restore after summarize
    character.dart                ST-compatible card fields (+ Anima id)
    character_category.dart       Anima-only category lists + memberships
    new_chat_pick.dart            Character + persona bundle for solo new chat
    lorebook.dart                 CharacterBook / World Info entries (+ ST import aliases)
    global_lorebook.dart          Standalone global lorebook (id + enabled + book)
    world_workshop.dart           Creation Center workshop + hub fields (summary, kit, sheets, pins)
    workshop_hub_models.dart      Modes, chat kit, locations, relationships, scene ideas
    chat_experience_settings.dart Classic vs Storybook layout + background + bubble opacity + hero portrait
    chat_background_service.dart User-picked chat background images (chat_backgrounds/)
    sync_target.dart              Sync file location (desktop path or Android URI)
    ui_style_settings.dart        Theme Studio settings + AnimaUiTheme extension + avatars
    theme_palette.dart            VisualStyle / BackgroundMode / fonts + 8 ThemePresets
    scene_mood_presets.dart       Built-in per-chat scene mood presets (drunk, tense, explicit, buildup, afterglow, …)
    explicit_scene_guidance.dart  Vocabulary law for explicit scene moods + rewrites (anti–LLM-trope)
    field_wand_options.dart       Field wand expansion levels + workshop merge depth enums
    chat_session_resolver.dart    Merge library characters/personas/lore with per-chat overrides
    authors_note_composer.dart    Merges active scene moods + manual Author's Note for prompts
    chat_overrides_sheet.dart     Reset chat-only character/persona/lore copies
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
    world_workshop_chat_screen.dart Workshop chat + lorebook/characters/persona + start roleplay
    settings_screen.dart          Settings hub (Data folder + Personas + Characters + Creation Center + AI collaborator + Backup)
    data_folder_setup_screen.dart First-run visible library folder picker
    data_folder_settings_screen.dart View / move the Anima library folder
    api_settings_screen.dart      API key, model catalog, subscription URL + remaining credits
    lore_settings_screen.dart     Global books + scan/budget + character books link
    sampling_settings_screen.dart ST-style generation parameters
    collaborator_settings_screen.dart AI wand + auto-wrap + Roadway notes
    character_build_settings_screen.dart Full card build model + sampling + prompt
    global_chat_prompts_screen.dart App-wide system prompt + post-history for all chats
    appearance_settings_screen.dart Theme Studio (presets + colors/fonts + avatars)
    backup_restore_screen.dart    Full-app backup / restore + cross-device sync (.anima-backup JSON; no API key)
    settings_ui.dart              Shared settings form helpers
 widgets/
  ai_field_changes_sheet.dart Review sheet for AI-proposed field changes (before/after)
  text_model_catalog_widgets.dart Model browse sheet + summary card (ctx, TPS, …)
    anima_avatar.dart             Local-file / initial avatar (circle or rect via style); tap → fullscreen
    avatar_fullscreen.dart        Full-screen portrait viewer (tap to dismiss)
    chat_hero_portrait.dart Tall side portrait with fade into storybook bubbles
    chat_image_background.dart Cached blurred image behind chat messages
    chat_composer_field.dart      Chat composer with optional Enter-to-send (Shift+Enter newline)
    chat_composer_tools_sheet.dart Mobile composer + sheet (moods, narrator, director, continue, …)
    avatar_history_sheet.dart     Grid picker for past portrait generations
    generate_avatar_sheet.dart    Shared NanoGPT Generate avatar sheet (characters + personas)
    keyboard_inset.dart           Lift UI above keyboard (chat composers)
    rp_rich_text.dart             *action* / "dialogue" styled message text
    greeting_picker.dart          Multi-greeting sheet when starting a chat
    narrator_bubble.dart          Centered narrator card (chat Narrator lines)
    group_reply_sheet.dart          Group react — multi-select cast + nudge sheet
    group_beat_bubble.dart          Centered multi-character group-react card
    group_beat_edit_sheet.dart      Per-character edit sheet for group-react lines
    narrator_sheet.dart           Narrator sheet — nudge, edit, Generate, Post
    workshop_overview_sheet.dart  Workshop dashboard bottom sheet
    minimal_chip_button.dart        Shared MinimalChipButton + MinimalChipRow
    workshop_compact_toolbar.dart   Workshop chip row (mode, length, import, ideas)
    field_wand_icon_button.dart     Tap = quick expand; long-press = expansion + source menu
    field_wand_menu_sheet.dart      Field wand long-press picker (card / workshop / chat)
    workshop_card_merge_sheet.dart  Standard vs enrich merge before workshop create/update
    lorebook_gap_fill_sheet.dart      Per-gap World Info preview before lorebook export
    character_token_badge.dart      Compact ~1.2K label beside character names
    new_chat_persona_bar.dart       Persona picker strip on solo new-chat character list
    workshop_chat_import_sheet.dart Import-options sheet when seeding workshop from chat
    chat_lorebook_picker.dart     Per-chat global lorebook picker (chat ⋮ menu)
    character_category_controls.dart Category filter + manage / assign sheets
    preset_picker.dart            Preset button + bottom sheets (sampling / text)
    create_character_from_chat_sheet.dart Scan/generate character card from live chat context
    update_character_from_chat_sheet.dart Pick saved card + optional notes → merge update from chat
    scene_mood_sheet.dart         Per-chat scene mood toggle sheet (composer mood icon + ⋮ menu)
    memory_summary_sheet.dart     Scene/Ledger editor with pin toggles (chat ⋮ → Memory summary)
    reply_rewrite_sheet.dart      Rewrite reply mode picker (custom first + moods / style options)
  utils/
    platform_utils.dart           Desktop platform detection (Windows / Linux / macOS)
    composer_markup.dart          Auto-wrap dialogue on send (*actions* + "quotes")
    rp_observable_text.dart       Visible vs private *asterisk* filtering for other characters' history
    scroll_to_end.dart            Retry scroll-to-bottom for lazy chat lists
    windows_paste_handler.dart    Windows Ctrl+V / Shift+Insert paste + modifier cleanup
  services/
    api_key_service.dart          Secure storage for NanoGPT API key
    ai_field_changes.dart         Compare character/lorebook fields for AI fix review
    settings_service.dart         Model, image model, sampling, context, lore, Theme Studio, collaborator (+ legacy persona migrate)
    appearance_controller.dart    Root appearance state — save/reload notifies MaterialApp
    persona_service.dart          Multi-persona load/save + default active id
    avatar_service.dart           Local avatar files under documents/avatars (+ history per stem)
    avatar_export_service.dart    Export portrait copies to Gallery / Downloads
    avatar_prompt_builder.dart    Text prompt for NanoGPT character/persona avatar generation
    character_service.dart        Load/save characters JSON on device
    character_category_service.dart Anima-only category lists (multi-membership)
    character_token_service.dart    Per-character prompt / lore token estimates
    persona_token_service.dart    Per-persona promptText token estimates
    lorebook_token_service.dart   Lorebook enabled-total + per-entry content estimates
    character_card_codec.dart     ST Card V1/V2/V3 + PNG import/export
    character_collaborator.dart   Field-aware prompts + consistency check/fix for character cards (+ wand expansion/source)
    field_wand_context_builder.dart Workshop/chat transcript blocks for field wand long-press
    persona_collaborator.dart     Field-aware prompts for persona AI wand
    lore_collaborator.dart        Field-aware prompts + keyword suggest + lorebook consistency check/fix
    reply_rewrite_service.dart    Rewrite-reply prompts for regen / new swipe
    roadway_service.dart          Paths / Roadway brainstorm + combine prompts + parse
    group_reply_service.dart      Group react — coordinated multi-character beat prompts + parse
    group_speaker_inference.dart  Manual group Continue — infer speaker from last reply / mentions
    group_beat_codec.dart         Flatten / prompt format / swipe JSON for group-react messages
    director_service.dart         Director notes — mandatory next-reply scene control
    character_guide_service.dart  Character voice Guide AI — fresh reply from player direction
    presence_service.dart         Automatic scene presence + memory/history filtering + staging sanitization
    chat_style_rules.dart         Hard-coded modern chat tone (slang/emoji as reactions, not dialogue)
    temporary_character_sheet.dart Quick NPC create sheet + Temporary badge widget
    narrator_service.dart       Universal chat Narrator — generate + prompt injection
  roadway_cache_service.dart    Per-chat cached Path options (survive sheet close)
  composer_draft_service.dart   Per-chat composer draft autosave
  speaker_prefix.dart           Strip leading "Name:" from AI replies (group immersion)
  chat_service.dart             Chats per character + group bucket (+ personaId, autoReply, lorebookIds)
    chat_context_service.dart     History trim + Scene/Ledger memory merge helpers
    prompt_builder.dart           System prompt, modes, group, authors note
    lorebook_service.dart         Keyword scan, budget, merge global + character books
    world_info_service.dart       Persist global lorebooks (anima_lorebooks.json)
    world_workshop_service.dart   Persist Creation Center workshops + last-opened id
    workshop_hub_service.dart     Hub ops: play plan, bundle, duplicate, merge, status
    workshop_hub_controller.dart  AI hub actions (summarize, glossary, scenes, export)
    sync_service.dart             Push / pull one sync file for phone ↔ desktop handoff
    world_workshop_builder.dart   Workshop prompts + hub JSON parsers
    chat_transcript_codec.dart    Chat JSON / plain-text import/export
    app_backup_service.dart       Full-app backup/restore (whitelist JSON + avatars; no API key)
    app_data_root.dart            User-owned library folder (Documents/Anima or next to the app)
    app_paths.dart                Resolves the active library directory for all services
    android_storage.dart          Android public Documents + All files access
    settings_store.dart           Settings JSON in the library folder (migrates from secure storage)
    nanogpt_service.dart          Streaming + text/image model catalogs + image generate + credit usage + sampling + plain-English errors
scripts/
  update_linux.sh                 One-command Linux build/install + launcher; optional Git pull
  update_windows.ps1              Windows build + optional zip / GitHub Release upload (`-Zip`, `-Release`)
  upload_github_release.ps1       Upload APK + Windows zip; deletes stale .apk assets first
  setup_windows_dev.ps1           Fresh-PC install: Flutter, JDK 17, Android SDK, VS Build Tools, env vars
  install_windows_atl.ps1         Add C++ ATL to existing VS Build Tools (Windows desktop builds)
```

**Dependencies in use:** `flutter_secure_storage` (legacy migration), `http`, `path_provider`, `path`, `file_picker`, `share_plus`, `google_fonts`, `saf` (Android sync file access), `gal` (export portraits to Gallery), `permission_handler` (Android All files access for Documents/Anima)  
**Dev / branding:** `flutter_launcher_icons` (Android + Windows from `assets/branding/anima_icon.png`; Linux bundles the same PNG beside `data/`); master icon at `assets/branding/anima_icon.png`. Release scripts run icon generation before desktop builds.

---

## Security checklist for agents

- [ ] Never write API keys into source, README examples with real keys, screenshots committed to git, or `.env` files that get committed
- [ ] The NanoGPT key lives in the user Anima folder as `api_key.txt` so the library is portable — never copy that folder into the git repo
- [ ] If a secret is ever committed by mistake: rotate the NanoGPT key immediately and purge it from git history
- [ ] `android/local.properties` stays gitignored (machine-specific SDK path)

---

## Machine notes (this developer PC)

### Windows (this PC)

| Tool | Status |
|------|--------|
| Flutter | ✅ 3.44.9 stable at `C:\src\flutter` |
| Dart | ✅ 3.12.2 |
| JDK | ✅ Temurin 17 at `C:\Program Files\Eclipse Adoptium\jdk-17.0.20.8-hotspot` |
| Android SDK | ✅ `%LOCALAPPDATA%\Android\Sdk` (platform 36, build-tools 36.0.0) — licenses accepted |
| Android Studio | ❌ Not installed (SDK via cmdline-tools only — enough for `flutter build apk`) |
| Visual Studio | ✅ Build Tools 2022 17.14 + C++ + ATLMFC |
| Git | ✅ `C:\Program Files\Git\cmd\git.exe` — repo linked to `origin` `https://github.com/jwarren9393/Anima.git` |
| GitHub CLI (`gh`) | ✅ installed — run `gh auth login` once after a PC reset |
| Chrome | ❌ Not required for this app |
| Developer Mode | ✅ Enabled (required for Flutter plugin symlinks on Windows) |
| Physical Android phone | Plug in + USB debugging → `flutter devices` / `flutter run` |

User env (set for this account): `JAVA_HOME`, `ANDROID_HOME`, `ANDROID_SDK_ROOT`, and `PATH` include Flutter, JDK, Android tools, and GitHub CLI. **Restart Cursor / open a new terminal** after setup so PATH updates apply.

Fresh install / re-run anytime:

```powershell
cd D:\AI\Anima
powershell -ExecutionPolicy Bypass -File .\scripts\setup_windows_dev.ps1
flutter doctor
flutter pub get
flutter run -d windows
```

### Linux (alternate host)

| Tool | Status |
|------|--------|
| Flutter | ✅ 3.47.0 stable at `~/development/flutter` |
| Dart | ✅ 3.13.0 |
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

1. Run the app: **`flutter run -d linux`** (desktop) or plug in your Android phone + **`flutter run`**.
2. First launch: use **Documents/Anima** (or pick a folder). On Android, allow **All files access** so My Files can open it.
3. Enter your NanoGPT API key in **Settings → API** (saved in that folder as `api_key.txt`).
4. Optional on Windows: if Dart extension can't find Flutter, set user-level `"dart.flutterSdkPath": "C:\\src\\flutter"` (workspace no longer hardcodes a path).
5. **Release rule:** keep `pubspec.yaml` at **`1.0.0+<build>`** — only increment the number after `+`. Upload to the existing **`v1.0.0`** GitHub release (not a new tag per build). Current phone APK is **build 62**.

---

## Related documents

| File | Purpose |
|------|---------|
| [`PROJECT_REFERENCE.md`](PROJECT_REFERENCE.md) | Complete encyclopedia for external AI — architecture, data, UI, prompts, mechanics |
| [`README.md`](README.md) | User-facing feature catalog and install guide |
| [`AGENTS.md`](AGENTS.md) | This file — agent status, roadmap, code map |

---

## How to update this document

When you finish work, edit these sections:

1. **Current status** — phase name, date, last agent action, what works / doesn't
2. **Build phases** — check off completed items
3. **Code map** — if you added/removed files
4. **Next actions** — replace with the true next steps

Do not delete historical phase checklists; mark them done so future agents see progress.
