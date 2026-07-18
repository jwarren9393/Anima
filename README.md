# Anima

**Anima** is a private, personal AI character roleplay / chat app built with [Flutter](https://flutter.dev).  
It talks to the [NanoGPT](https://nano-gpt.com) API (OpenAI-compatible chat completions) for all AI replies.

| | |
|---|---|
| **Inspiration** | SillyTavern-like RP/chat features on a phone — **not** a full SillyTavern clone |
| **Primary platform** | Android |
| **Also builds** | Linux desktop (works); Windows desktop (needs a Windows host) |
| **Distribution** | Personal use only — **not** published to app stores |
| **Repo** | https://github.com/jwarren9393/Anima (private) |
| **Theme** | Fixed dark **Obsidian & Gold** glass UI (no light mode / theme studio) |
| **Version** | `1.0.0` (see [GitHub Releases](https://github.com/jwarren9393/Anima/releases) for the official APK) |

API base (pay-as-you-go): `https://nano-gpt.com/api/v1/chat/completions`  
Auth: `Authorization: Bearer <API_KEY>`  
Optional subscription base: `https://nano-gpt.com/api/subscription/v1`

---

## Download (Android APK)

Official builds are published on the repo’s **[Releases](https://github.com/jwarren9393/Anima/releases)** page (not committed into source).

1. Open the latest release (e.g. **v1.0.0**).
2. Download **`Anima-1.0.0.apk`**.
3. On your phone: allow install from this source if Android asks, then open the APK.
4. First launch → **Settings → API & connection** → paste your NanoGPT key → Save.

This is a **personal / sideload** build (not Play Store). Rebuild locally anytime with:

```bash
flutter build apk --release
# output: build/app/outputs/flutter-apk/app-release.apk
```

---

## Who this README is for

This document is a **full product overview**: every screen, option, and major background store.  
It is written so a person — or an AI assistant given this GitHub link — can understand **everything the app can do today**, without reading the source first.

Living build notes for coding agents live in [`AGENTS.md`](AGENTS.md) (status, roadmap, code map, security). Prefer this README for **user-facing capability**; prefer `AGENTS.md` for **what to build next**.

---

## Quick start (this machine)

```bash
export JAVA_HOME="$HOME/development/jdk-17"
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$HOME/development/flutter/bin:$HOME/.local/bin:$PATH"

cd /path/to/Anima
flutter doctor
flutter devices
flutter run          # phone or Linux desktop
flutter test
flutter analyze
```

**API key (safe):** open the app → **Settings** → **API & connection** → paste NanoGPT key → **Save**.  
The key is stored only in device secure storage — never in source or GitHub.

---

# Complete feature guide

## 1. Home screen

Landing page after launch (`lib/screens/home_screen.dart`).

- Lists **all saved chats** (solo and group), newest first.
- Each row shows: title / character or group names, avatar, last-message preview, message count, last updated time, and a **Note** badge if an Author’s Note is set.
- **Tap** a chat to open it.
- **Long-press** a chat → confirm → **Delete** (also clears that chat’s composer draft and cached Paths).
- Pull to refresh.
- App bar: **Settings**, **New chat**.
- Empty state: **Start a chat**.

---

## 2. Starting a new chat

**New chat** → choose **Solo** or **Group**.

### Solo

1. Opens **Choose character** (Characters screen in pick mode).
2. Optional **Category** filter (see Character categories).
3. Attaches the **default persona**.
4. If the character has multiple greetings → **Choose opening** sheet (primary + numbered alternates). Chosen greeting starts the chat; others remain as **swipes** on the first AI message.
5. New chats default to **Auto-reply off**.

### Group

Opens **New group chat** setup (`group_chat_setup_screen.dart`):

- Need at least **two** characters.
- Same **Category** filter; already-checked members stay visible when you change filters.
- Check who is in the group; drag **Reply order** (first greets / speaks first; later auto turns use round-robin).
- **Auto-reply** switch (default off).
- **World Info / lorebooks** — which global books apply (enabled books start selected). Each speaking character’s **embedded** lorebook still applies when they speak.
- **Author’s Note** (optional) + text presets.
- Greeting picker for the first character, then opens the chat.

---

## 3. Settings hub

Opened from Home or Chat ⋮ → **Settings** (`settings_screen.dart`). Each tile opens its own screen.

### 3.1 API & connection

`api_settings_screen.dart`

**NanoGPT API key**

- Enter / replace / show-hide / save / remove.
- Stored via secure storage only; the field never shows the saved secret again.

**See remaining credits**

- Wallet balance (USD; NANO when returned).
- Subscription state.
- Weekly / daily input credits, daily image allowance, monthly usage, used / remaining / total / %, reset times, period end — as returned by NanoGPT.

**AI model (chat)**

- Live NanoGPT **model catalog**.
- Provider list: **Auto** first, then providers A–Z.
- Auto options include `auto-model`, `auto-model-basic`, `auto-model-standard`, `auto-model-premium`.
- Model dropdown filtered by provider; refresh catalog; optional **custom model id**.

**Image model (avatars)**

- Separate **Image model** picker for NanoGPT image generation (Generate avatar).
- When **Use subscription API** is **on**, Anima loads only NanoGPT’s **subscription image catalog** (`/api/subscription/v1/image-models`) so paid wallet models stay hidden.
- When subscription API is **off**, the full public image catalog appears with **Included** / **Paid** labels (and price when known). Generating with a Paid model asks for confirmation first.
- Generation still uses `POST /api/v1/images` (NanoGPT does not expose a separate subscription image *generation* URL).

**Connection**

- **Use subscription API** toggles pay-as-you-go vs subscription base URL and reloads the matching **chat** and **image** catalogs.

### 3.2 Personas

`personas_screen.dart` / `persona_edit_screen.dart`

- Multiple **{{user}}** identities: **Name**, optional **About this persona** (injected into prompts), optional photo.
- **Generate avatar** — same NanoGPT sheet as characters; prompt is built from name + About (editable); subscription-safe model rules apply.
- Create / edit / delete (at least one persona always kept).
- **Set as default** for new chats (long-press also works).
- Per-chat persona can differ from the default (see Chat ⋮ menu).
- Also reachable by tapping **your** avatar in chat.

### 3.3 Characters

`characters_screen.dart` / `character_edit_screen.dart`

Two modes:

- **Manage** (from Settings / lore link): tap opens **Edit**; does not auto-close.
- **Pick** (Solo new chat / chat switcher): tap selects and returns.

**List features**

- Avatar, description preview, lorebook count, category names.
- Import card (JSON / PNG), **New**, export, delete.
- Starter character **Anima** if the library is empty.
- **Consistency check** (checklist icon on the editor) — AI read-only report; does not change the card.

**Character categories (Anima-only)**

- Not SillyTavern card tags; do not export on cards.
- Dropdown: **All characters** + custom lists.
- Folder icon → create / rename / delete categories (deleting a list never deletes characters).
- Row ⋮ → **Categories** → multi-check membership (one character can be in many lists).
- Same filter on Group setup.

**Card fields you can edit**

| Field | Notes |
|--------|--------|
| Name | Required |
| Description | AI wand available |
| Personality | AI wand |
| Scenario | AI wand |
| First message | AI wand |
| Alternate greetings | One per line; AI wand |
| Example messages | ST `mes_example`; AI wand |
| System prompt (optional) | Blank = Anima default; `{{original}}` inserts default; presets + wand |
| Post-history instructions | Optional; presets + wand |
| World Info / lorebook | Embedded `character_book` |
| Avatar | Pick photo, **Generate avatar** (NanoGPT), or clear; PNG import uses card image |

**Generate avatar** opens a shared sheet (`generate_avatar_sheet.dart`): editable prompt from card text (name, description, personality, scenario, tags), image model picker, preview, **Use as avatar**. Uses the same subscription-safe image rules as API settings.

Imported creator notes, tags, extensions, etc. are **preserved** on save/export even if not shown as edit fields.

**AI wand (sparkle)** on creative fields: sends other filled fields as context; appends NanoGPT text under existing text; uses chat model + sampling + collaborator **Wand guidance note**.

**Import / export**

- Import: Card V1 / V2 / V3 JSON; PNG with `chara` / `ccv3`.
- Export: V2 JSON, V3 JSON, PNG (`chara`), PNG V3 (`chara` + `ccv3`).
- JPEG/WebP avatars may fall back to a placeholder when exporting PNG cards.

### 3.4 World Info & lore

`lore_settings_screen.dart` / `lorebooks_screen.dart` / `lorebook_edit_screen.dart`

**App-wide scan settings**

- **Scan depth (messages)** — default 4 (1–50).
- **Token budget** — default 512 (approx; 10–4000).
- **Recursive scanning** — when on, content from matched entries can pull in further active entries (same shared token budget + priority).
- Link to edit **character** lorebooks via Characters.

**Global lorebooks**

- Create, import ST/Anima JSON, enable/disable whole book, edit entries, export, delete.
- Enabled books inject into chats by default; Group setup can narrow the set.
- Separate from each card’s embedded book.

**Entry editor**

- Enabled, Always on, Label, Keywords, Suggest keywords from content, Selective + secondary keywords, Case-sensitive, Lore content, placement (Before / After desc), Insertion order, Priority, Comment.
- AI wand on Label / Keywords / Secondary / Content; merges keyword suggestions.
- Matching: recent messages scanned; selective needs both key sets; always-on needs no keyword; global + speaking character’s book merged; budget + priority apply.
- When lore fires and fits the budget, chat shows a brief top overlay: **Lore Triggered: …**

### 3.5 Creation Center

`world_workshop_list_screen.dart` / `world_workshop_chat_screen.dart`

- AI workshop chats to invent a world (setting, factions, places, rules, history, people, items…).
- Streaming replies + Stop.
- **Create lorebook** / **Update lorebook** — NanoGPT turns the workshop into keyword entries saved as one **enabled global lorebook** (one workshop ↔ one book).
- **Create characters** (person+ icon) — detects named people in the workshop chat, lets you multi-select, generates each full card one-by-one, and opens **Review generated character** (same editor as Characters, including Generate avatar) before anything is saved. Saving a name that already exists creates a **second** card (no overwrite).
- Deleting a workshop does **not** delete an already-created lorebook.

### 3.6 Generation parameters

`sampling_settings_screen.dart`

- Temperature, Top P, Max tokens (optional).
- Frequency / Presence / Repetition penalties.
- Built-in presets (Balanced, Creative, Focused, Short, Long prose, Anti-repeat, Deterministic, Chaotic, Chatty, Mystery, Cozy, …).
- **Context size** in tokens (presets 1K–24K; range ~512–32K) — how much recent history fits in each prompt; full history stays saved on device.
- **Auto-summarize long chats**, every N messages, keep recent raw messages — folds older turns into per-chat **Memory summary** (extra NanoGPT call).

### 3.7 AI collaborator

`collaborator_settings_screen.dart`

Three editable guidance notes (each with presets / reset):

1. **Wand guidance note** — character wands, lore wands, Creation Center flavor.
2. **Composer Format** — chat ✨ Format button.
3. **Roadway / Paths** — Paths brainstorming.

All use the normal model + sampling (Format uses lower temperature to stay close to the draft).

### 3.8 Appearance

`appearance_settings_screen.dart`

- Theme is fixed Obsidian & Gold.
- Chat avatars only: **shape**, **size tier**, fine **scale** slider (persona + character photos in bubbles).

### 3.9 Backup & restore

`backup_restore_screen.dart` / `app_backup_service.dart`

- One **`.anima-backup`** plain JSON file for the whole app library.
- **Includes:** chats, characters, personas, categories, lorebooks, Creation Center workshops, composer drafts, Paths cache, avatar image files, and non-secret settings.
- **Does not include:** the NanoGPT **API key** (on purpose). Re-enter the key after restore under API & connection.
- Restore replaces only Anima’s known files/settings (whitelist) — not other device data — then returns to Home.
- Not encrypted; treat the file like a private export.

---

## 4. Chat screen

`chat_screen.dart`

### Navigation & chat tools (⋮)

- Close → Home.
- Switch among **Saved chats**; **New chat**.
- **Persona: …** — change who {{user}} is for this thread only.
- **Author’s Note** — per-chat instructions after history every turn (+ presets, macros).
- **Memory summary** — edit the running summary injected into prompts.
- **Summarize now** — force a NanoGPT memory update.
- **Characters** — pick/switch (pick mode).
- **Start group chat**.
- **Export chat** — Anima JSON (keeps swipes) or plain text.
- **Import chat** — Anima JSON or best-effort `Name: message` text.
- **Settings**.

### Composer

- Multi-line input.
- **Draft autosave** per chat (survives leaving chat/app); cleared on send.
- **OOC** — wraps send as `(OOC: …)` unless already tagged.
- **Format (✨)** — AI cleanup + `*action*` / `"dialogue"` markup per Format note.
- **Continue (▶)** — next AI reply without a new user message.
- **Send** — posts user message; generates reply only if **Auto-reply** is on.
- **Stop** — while streaming; keeps partial text.

### Auto-reply

- Default **off** for new chats.
- Off: send alone; use Continue or (group) tap a name chip.
- On: send also generates the next AI reply.
- Toggle from message **long-press** menu.

### Group chips

- Name chips above composer = who speaks next.
- Tap chip to select next speaker; in manual mode after your message, tap can generate that character’s reply immediately.
- Bubbles store speaker name/id; other members get short summaries in the active speaker’s prompt.

### Message UI

- Tap bubble → **edit** (AI edit changes current swipe only).
- Tap **your** avatar → edit persona; tap **AI** avatar → edit that character card.
- RP styling: `*narration*` soft italic gold; `"dialogue"` bolder; plain text muted.
- Streaming shows thinking / typing state.

### Long-press actions

| Action | Behavior |
|--------|----------|
| Delete | Removes that message only; **4s Undo** SnackBar before the change is written to disk |
| Rewind to here | Deletes everything after; **4s Undo** SnackBar before disk write |
| Branch from here | New chat with history through here (keeps persona, auto-reply, note, lore picks); runs immediately |
| Continue | Generate next reply |
| Impersonate | AI drafts the next **user** message as the persona |
| Paths | Roadway brainstorm sheet |
| Auto-reply on/off | Per-chat toggle |
| Regenerate / New swipe | Latest AI message |
| Previous / Next swipe | When multiple swipes exist |

**Toasts / overlays**

- **Lore Triggered: …** — top overlay when World Info entries match and fit the budget.
- **Memory summary optimized** — after a successful auto-summarize.

### Swipes

- Under AI bubbles: `◀ 1/N ▶` when applicable.
- On the **latest** AI message, ▶ past the last swipe **generates** a new alternate.
- Older multi-swipe bubbles only browse.

### Paths (Roadway)

- Long-press → **Paths**.
- ✨ generates ~6 next-move options for {{user}}.
- Tap a path → composer; edit icon / long-press to edit before use.
- Check **two or more** → **Combine selected** → AI merges into one composer draft.
- Clear / refresh; closing the sheet **keeps** options until the chat’s last message changes, you clear/refresh, or the chat is deleted.
- Uses Roadway note + normal model/sampling.

---

## 5. Macros

In card fields, Author’s Note, examples, etc.:

- `{{user}}` / `<USER>` → active chat persona name.
- `{{char}}` / `<BOT>` → speaking character name (group: current speaker).
- Persona **About** text is injected into the system prompt.

---

## 6. What gets sent to NanoGPT (typical turn)

Rough prompt assembly (`prompt_builder.dart`, `lorebook_service.dart`, `chat_context_service.dart`):

1. Character system prompt or Anima default (+ optional `{{original}}`).
2. Group member summaries when relevant.
3. Triggered lore **before** description.
4. Description, personality, scenario, example dialogue.
5. Triggered lore **after** description.
6. Persona name + bio.
7. Memory summary (if any).
8. Recent history packed to **context size**.
9. Post-history instructions + Author’s Note.

Streaming SSE; Stop cancels but keeps partial text. Sampling from Generation parameters.

---

## 7. Local data & background services

Ordinary data lives under the app documents directory unless noted. **Nothing is uploaded to GitHub.**

| Store | What it holds |
|--------|----------------|
| Secure storage (`ApiKeyService`) | NanoGPT API key |
| Secure storage (`SettingsService`) | Model, subscription flag, sampling/context/lore/collaborator/appearance, selected character id, legacy persona migration |
| `anima_characters.json` | Character cards, embedded lorebooks, avatar filenames |
| `anima_character_categories.json` | Category names + character memberships |
| `anima_personas.json` | Personas + avatar filenames (default id in secure storage) |
| `anima_chats.json` | All solo/group sessions, messages, swipes, speakers, notes, persona, auto-reply, lore picks, memory |
| `anima_composer_drafts.json` | Unsent composer text per chat id |
| `anima_roadway_cache.json` | Cached Paths per chat + message anchor |
| `anima_lorebooks.json` | Global lorebooks |
| `anima_world_workshops.json` | Creation Center workshops |
| `avatars/` | Local image files referenced by filename |
| `.anima-backup` export | Full-library backup JSON + embedded avatar bytes (no API key) |

Other services (no separate “user screen”): `NanoGptService` (API/stream/credits/image models/image generate/catalog), `MessageFormatter`, `CharacterCollaborator`, `LoreCollaborator`, `RoadwayService`, `WorldWorkshopBuilder`, `ChatTranscriptCodec`, `CharacterCardCodec`, `AvatarService`, `AvatarPromptBuilder`, `AppBackupService`.

---

## 8. Current limits

- Windows app build only on a Windows PC.
- Group chat is simple (chips + round-robin), not full SillyTavern group orchestration.
- No NovelAI / Agnai / Risu lore converters (ST JSON + `character_book` work).
- No TTS.
- Paths live on the long-press menu (not a permanent composer button).
- Full-app backup is plain JSON (not encrypted) and skips the API key on purpose.
- PNG card export: JPEG/WebP avatars may fall back to a placeholder; PNG avatars embed correctly.
- Not yet: undo send, auto-resume last chat, pinned Author’s Note / mood chips, memory preview panel, light theme.
- Private personal app — not for Play Store / App Store.

---

## 9. Project layout (high level)

```
lib/
  main.dart                 # Entry, Obsidian & Gold theme wiring
  theme/                    # Theme + glass backdrop
  models/                   # Messages, sessions, characters, categories, lore, personas, presets
  screens/                  # Home, chat, settings tree, editors, Creation Center, backup
  widgets/                  # Avatars, Generate avatar sheet, greeting picker, RP text, presets
  services/                 # API (chat + images), persistence, prompts, backup, Paths, drafts
test/                       # Unit / widget tests
AGENTS.md                   # Agent living document (status + next actions)
README.md                   # This product overview
```

---

## 10. Security

- Never commit API keys, `.env` secrets, or keystore passwords.
- Never hard-code secrets in Dart.
- Use in-app **API & connection** + `ApiKeyService` only.
- `android/local.properties` stays gitignored (machine SDK path).

---

## 11. For coding agents

Read and update **[`AGENTS.md`](AGENTS.md)** every session.  
That file tracks phase status, checkboxes, detailed code map, and the next concrete tasks.
