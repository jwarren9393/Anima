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
| **Version** | **1.0.0** build **61** — official builds on [GitHub Releases](https://github.com/jwarren9393/Anima/releases) |

### What’s new in recent builds (1.0.0)

| Build | Highlights |
|-------|------------|
| **61** | **Memory overhaul** — Scene (current place/cast) vs Ledger (durable plot); summarize **merges** instead of newest-wins; **pin** ledger lines; open threads kept until resolved. **Narrator scene lock** — old narrator/director cards stay out of API history so long chats don’t rewind. |
| **60** | **Sync/restore fix** — `.anima-backup` may include plain-text library files; phone pull no longer rejects `anima_active_persona_id.txt` as “not valid JSON”. |
| **59** | **Portable data folder** — characters, chats, avatars, settings, and API key live in one visible folder (`Documents/Anima` by default). First-run picker + **Settings → Data folder**. Android uses public Documents instead of locked app storage. |
| **47** | **Presence / scene law** — always-on knowledge boundaries: narrator resets who’s present; opening scene seeds initial cast; unnamed messages only reach **present** characters (not whole cast); memory **witness tags**; per-character history/lore filtering. **Director mode** — replaces OOC; mandatory command for the **next** AI reply (centered card; tap edit, long-press delete). **Temporary characters** — quick NPC (name + note) from chat ⋮ or Manage cast; **Temporary** badge; promote to full card; **Full cards only** filter in Characters and group setup. **Consistency fix** — after AI consistency check on character cards or lorebooks, review changed fields and apply in one tap |
| **46** | **Android keyboard fix** — send dismisses on-screen keyboard so replies stay readable; composer refocus / empty-Enter-continue stay **desktop-only** |
| **45** | **Manual group chat** — Continue uses scene context (last speaker / name mentions), not round-robin chip order; no “next speaker” chip highlight. **Group react** — long-press menu; regenerate avoids copying prior beats verbatim; retries missing cast lines. **Keyboard flow (desktop)** — Enter sends, empty Enter continues; composer stays focused after send. **Creation Center** — character detect rejects JSON template placeholders |
| **44** | **Persona AI builder** — plain English → fill/replace/update persona fields (like character card builder; Settings → Character builds). **Creation Center** — workshop-specific guidance (not card-wand text), lower chat token floor, repeat penalties to reduce long repetition loops |
| **43** | **Group react** — one timeline card for multi-character reactions (not separate bubbles); swipes = alternate full beats. **Creation Center** — red **Stop** while streaming (keeps partial text); **▶ Continue** when your message has no AI reply yet |
| **42** | **Narrator scene scope** — present cast from recent chat only (not full group); current vs background transcript; direct prose; no sanitizing |
| **41** | **Paths fix** — first-person options (`*I…*` not persona name); dedupe + tuned sampling; **memory summarize balance** — clinical bullets finish without mid-line cutoffs (1536 default / 2048 cap) |
| **40** | **Clinical memory summarize** — hard-coded bullet-only facts (no RP voice/metaphors); reference-only injection so memory does not steer character style |
| **39** | **Narrator generate fix** — capped tokens, tighter sampling, cleaner prompt; strips instruction leaks and repetition loops from generated lines |
| **38** | Universal **Narrator** in chat — nudge + edit sheet, AI **Generate**, centered timeline cards, dedicated prompt injection; **Narrator note** in Settings → AI collaborator; solo/group only (not Creation Center) |
| **37** | Auto memory summarize runs **in the background** — chat UI stays usable (menu, composer, messages); progress banner; no back-to-back summarize chains |
| **36** | Desktop **Anima icon** on Windows (embedded in `anima.exe`) and Linux (window + app menu); same asset as Android |
| **35** | API **Category** filter (incl. **Uncensored & derestricted (broad)**); **Browse models** sheet + **selected model card** — context, max output, parameter size, TPS, TTFT, uptime %, description, capabilities, pricing/Included (from NanoGPT catalog + routing API) |
| **34** | **Update lorebook** merges workshop chat immediately (no misleading pre-flight on update); **Update my persona** in workshop ⋮ + World dashboard |
| **33** | **Update workshop cast** (workshop-tied characters only, not whole library); Creation Center collaborator prompt — brainstorm-only, points to real ⋮ menu actions |
| **32** | Creation Center **World dashboard** hub; **Fix last** chip; minimal UI pass (chat/home/group/settings); workshop **world summary** folding; full feature README |

Earlier 1.0.0 builds added Storybook layout, opening scenes library, backup/sync, group chat polish, and the core SillyTavern-style toolkit. **272 tests** at build 48.

API base (pay-as-you-go): `https://nano-gpt.com/api/v1/chat/completions`  
Auth: `Authorization: Bearer <API_KEY>`  
Optional subscription base: `https://nano-gpt.com/api/subscription/v1`

---

## Table of contents

1. [Installation and updates](#installation-and-updates)
2. [Who this README is for](#who-this-readme-is-for)
3. [Feature summary (at a glance)](#feature-summary-at-a-glance)
4. [Home screen](#1-home-screen)
5. [Starting a new chat](#2-starting-a-new-chat)
6. [Chat screen](#3-chat-screen)
7. [Settings hub](#4-settings-hub)
8. [Macros](#5-macros)
9. [What gets sent to NanoGPT](#6-what-gets-sent-to-nanogpt-typical-turn)
10. [Local data](#7-local-data--background-services)
11. [Current limits](#8-current-limits)
12. [Security](#9-security)
13. [For coding agents](#10-for-coding-agents)

---

## Installation and updates

Anima is a personal app, so it is installed directly rather than through an app store. The NanoGPT API key is never included in a GitHub build. On first launch, pick (or accept) your **Anima folder**, then open **Settings → API & connection**, enter the key, and tap **Save**. The key is stored as `api_key.txt` inside that folder.

### Android — easiest installation

Official Android builds are on the private repo’s **[Releases](https://github.com/jwarren9393/Anima/releases)** page.

1. On the phone, open the Releases page and select **v1.0.0**.
2. Download **`Anima-1.0.0.apk`**.
3. Open the downloaded APK. If Android asks, allow your browser or file manager to **install unknown apps**.
4. Tap **Install**, then open Anima.
5. Allow **All files access** if Android asks, then use **Documents/Anima** (or pick another folder).
6. Enter the NanoGPT key under **Settings → API & connection**.

To update Android later, download the newly refreshed APK and install it over the existing app. Your library lives in **Documents/Anima** (or the folder you chose), so it survives app updates. Uninstalling the APK also leaves that folder in place — copy it if you want a spare.

```bash
flutter pub get
flutter build apk --release
# APK: build/app/outputs/flutter-apk/app-release.apk
```

### Linux — Kubuntu/Ubuntu

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libsecret-1-dev
# Flutter SDK + flutter config --enable-linux-desktop
gh repo clone jwarren9393/Anima && cd Anima
./scripts/update_linux.sh
```

Update later: `./scripts/update_linux.sh --pull`

### Windows

```powershell
flutter pub get
flutter build windows --release
# Run: build\windows\x64\runner\Release\anima.exe (keep the whole Release folder)
```

Or: `.\scripts\update_windows.ps1 -Zip` for a zip package (build embeds the Anima icon in `anima.exe`).  
**GitHub Releases (APK + Windows):** `flutter build apk --release` then `.\scripts\update_windows.ps1 -Zip -Release` — uploads one `Anima-1.0.0.apk` (removes stale APK assets first). Or `.\scripts\upload_github_release.ps1` after both builds.

### Moving data between devices

Use **Settings → Backup, restore & sync**:

- **Create backup** — one `.anima-backup` JSON file (no API key).
- **Cross-device sync** — one sync file in Google Drive or a synced desktop folder; **Push to cloud** overwrites it; **Pull from cloud** restores on another device.

---

## Who this README is for

This document is a **complete product catalog**: every screen, menu, chip, sheet, and major background behavior. Use it when you forget what a submenu does.

Living build notes for coding agents: [`AGENTS.md`](AGENTS.md) (status, roadmap, code map).

**Full project encyclopedia for external AI (Gemini, etc.):** [`PROJECT_REFERENCE.md`](PROJECT_REFERENCE.md) — architecture, data, every screen, prompt assembly, mechanics, limits (paste or attach the whole file).

---

## Feature summary (at a glance)

**Chat & roleplay** — Solo and group chats; streaming; swipes; edit / delete / rewind / branch; Continue, Impersonate, Regenerate, **Rewrite reply…**; **Narrator** (nudge + Generate + post); **Director** (commands next reply); **presence / scene law** (always on — who’s present, witness-tagged memory, per-character filtering); Paths (Roadway); auto-reply (default off); ✨ Format; memory summary + auto-summarize (background); Author’s Note; per-chat persona and World Info; opening scene; context estimate; export/import chat; manage cast mid-chat (+ temporary NPCs); fullscreen avatars.

**Characters & personas** — ST V1/V2/V3 JSON + PNG import/export; categories; AI wand; consistency check **+ review-before-apply fix**; **AI card builder** with field split + review sheet; **temporary characters** (quick NPC, promote to full card); **Full cards only** filter; embedded lorebooks; alternate greetings; **Generate avatar**; group speaker chips.

**World & lore** — Global lorebooks + scan depth/budget + recursive scan; keyword triggers + toast; entry AI wand + keyword suggest; **consistency check + fix**; per-chat lore picks.

**Creation Center** — World workshops; import chat/lore/bundle; world dashboard (play, summarize, glossary, scene ideas, export); Fix last; canon pins; create/update lorebook, opening scene, characters, persona; **Update workshop cast** / **Update my persona**; roleplay chats on Home; linked lore off in prompts by default.

**API & models** — NanoGPT key + subscription toggle; **category + provider filters**; **Browse models** with ctx/output/params/TPS/TTFT/uptime; image model picker; credits usage.

**Look & data** — Theme Studio (8 presets, Storybook layout, chat backgrounds, RP colors); backup `.anima-backup` + phone ↔ PC sync (no API key in file).

---

# Complete feature guide

## 1. Home screen

Landing page after launch.

### What you see

- **Chat history** — all saved roleplay chats (solo + group), including chats started from Creation Center; solo = character name; groups = custom name or short default like “Group chat (3)”.
- Each row: avatar, title, last-message preview, message count, last updated time, **Note** badge when Author’s Note is set.
- **Creation Center** horizontal row — world tiles; the most recent workshop is marked **continue**; tap a tile to open that workshop; **+** opens the workshop list.
- App bar: **Settings** (gear).
- **New** FAB → bottom sheet: **Solo chat**, **Group chat**, **Creation Center** (new or list).

### Actions

| Action | Result |
|--------|--------|
| Tap chat row | Open that chat |
| Long-press chat row | Confirm → **Delete** (also clears composer draft + cached Paths for that chat) |
| Pull to refresh | Reload chat list |
| Empty state | **Start a chat** |

---

## 2. Starting a new chat

### Solo

1. **Choose character** (Characters screen in pick mode).
2. Optional **Category** filter (Anima-only lists — not ST card tags).
3. Attaches the **default persona** (or per-chat persona can be changed later).
4. If the character has **multiple greetings** → **Choose opening** sheet (primary + alternates). Chosen greeting starts the chat; others remain as **swipes** on the first AI message.
5. Optional **Opening scene** sheet — pick a saved scene, browse **Opening scene library**, type fresh prose, or **Skip**.
6. New chats default to **Auto-reply off**.

### Group

**New group chat** setup screen:

**Main form**

- Pick at least **two** characters (category filter; checked members stay visible when filter changes).
- Drag **Reply order** (first greets / speaks first; auto turns use round-robin when auto-reply is on).
- Optional **Chat name** field (shown on Home when set).

**Section chips** (open bottom sheets — no long inline forms)

| Chip | Sheet contents |
|------|----------------|
| **Lore** | Which global lorebooks apply (enabled books start selected). Each character’s embedded lorebook still applies when they speak. |
| **Scene** | Optional opening scene for this group chat |
| **Note** | Author’s Note + text presets |
| **Auto** | Auto-reply switch (default **off**) |

Then: greeting picker for the first character → opens the chat.

### Opening scene (narrator)

- Optional prose shown in a **centered narrator card** above messages (not a character bubble).
- **Injected into prompts by default** every turn (separate from card **Scenario**, which also injects).
- Turn off injection: chat ⋮ → **Stop injecting opening scene** (saves tokens).
- Edit: chat ⋮ → **Opening scene** (or **Add opening scene**).
- On **first memory summarize**, the scene is folded into the memory summary for long-term context.
- Works in solo and group.

### Opening scenes library

**Settings → Opening scenes**

- Create / edit / delete saved narrator setups.
- Scenes from Creation Center **auto-sync** when you save or AI-generate an opening scene there.
- Also available when starting a new chat or browsing from the opening-scene picker.
- Included in backup and sync.

---

## 3. Chat screen

Minimal chrome: **Close** · title · **⋮** menu. Composer icon row: **Narrator** (theater) · **Director** (control-camera) · text field · **✨ Format** · **▶ Continue** · **Send** / **Stop**.

### App bar ⋮ menu

| Item | What it does |
|------|----------------|
| **Saved chats** | Switch among chats for this character/group bucket |
| **New chat** | Start another chat (same character or new flow) |
| **Persona: …** / **Switch persona** | Who {{user}} is for **this thread only** (saved on the chat) |
| **Author’s Note** | Per-chat instructions injected after history every turn (+ presets, macros) |
| **World Info: …** | Use Settings default, pick specific global lorebooks, or turn global lore **off** for this thread (character card lore still applies) |
| **Opening scene** / **Add opening scene** | Edit narrator opening prose |
| **Stop injecting opening scene** / **Inject opening scene in prompts** | Toggle whether opening scene text is sent every turn |
| **Memory summary** / **Memory summary (set)** | Scene (now) + Ledger (durable plot); pin facts so summarize never drops them |
| **Summarize now** | Merge older messages into Scene/Ledger (does not wipe pinned lines or open threads) |
| **Context estimate** | Rough token/message gauge vs history budget and model window |
| **Characters** | Pick/switch character (pick mode) |
| **Rename chat** | Groups only — custom name on Home |
| **Manage cast** | Add/remove characters in the **current** chat without starting over; **Add temporary character** (quick NPC) or full character |
| **New character** | Sheet: type a name + **generate from chat** or start blank |
| **Update character from chat** | Revise one saved card from thread context (cast listed first; optional change notes) |
| **Start new group chat** | New group setup from here |
| **Open in Creation Center** | Seed or open a workshop from this chat |
| **Export chat** | Anima JSON (keeps swipes) or plain text |
| **Import chat** | Anima JSON or best-effort `Name: message` text |
| **Settings** | Settings hub |

### Composer chips & shortcuts

| Control | Behavior |
|---------|----------|
| **Narrator** (theater) | Sheet: optional **nudge**, editable line, **Generate** or type, **Post** — omniscient timeline card; resets who’s **present** in the scene; injected as system; solo/group only |
| **Director** (control-camera) | Posts a centered **Director** card that **commands the next AI reply** (mandatory system injection for that generation); tap to edit; long-press to delete; solo/group only |
| **Format (✨)** | AI cleanup + `*action*` / `"dialogue"` markup per **Composer Format** note (Settings → AI collaborator) |
| **Continue (▶)** | Next AI reply without a new user message |
| **Send** | Posts user message; generates reply only if **Auto-reply** is on |
| **Stop** | While streaming — keeps partial text |
| **Memory chip** | Shown when memory summary is set — tap to open summary |
| **Note chip** | Shown when Author’s Note is set — tap to edit |
| **Draft autosave** | Composer text saved per chat (survives leaving chat/app); cleared on send |
| **Enter to send** | Desktop: **Settings → AI collaborator** → **Enter to send** (Enter sends, Shift+Enter newline) |

### Auto-reply

- **Default off** for new chats.
- **Off:** send alone; use **Continue** or (group) tap a name chip.
- **On:** send also generates the next AI reply.
- Toggle: message **long-press** menu → **Auto-reply on/off**.

### Group speaker chips

- Name chips above composer = who speaks next.
- **Auto-reply off:** tap a chip to select next speaker and **always generate** that character’s reply (even re-tapping the same chip).
- **Group react** chip (or ⋮ / long-press → **Group react…**) — pick who reacts; one AI call writes **brief simultaneous reactions** for the same moment (avoids long back-to-back solo replies that shift tone).
- Bubbles store speaker name/id; other members get short summaries in the active speaker’s prompt.
- Chips **hide when the keyboard is open** (more room for typing).

### Message UI

- **Tap bubble** → edit (AI edit changes current swipe only).
- **Tap your avatar** → edit persona; **tap AI avatar** → edit that character card.
- **Long-press avatar** → same edit shortcuts.
- **Tap any avatar** (chat, lists, editors, home) → **full-screen portrait**; tap again or ✕ to close.
- RP styling: `*narration*` soft italic gold; `"dialogue"` bolder; plain text muted.
- Streaming: thinking/typing state; list does **not** auto-scroll during streaming (scroll freely).
- No permanent Swipe/Regen bar under messages — actions live in long-press menu + compact swipe arrows under bubbles.

### Long-press message menu

Scrollable sheet (~55% screen height on wide displays).

| Action | Behavior |
|--------|----------|
| **Delete** | Removes that message only; **4s Undo** SnackBar before disk write |
| **Rewind to here** | Deletes everything after; **4s Undo** SnackBar before disk write |
| **Branch from here** | New chat with history through here (keeps persona, auto-reply, note, lore picks); runs immediately |
| **Narrator** | Same sheet as composer theater icon — nudge, Generate, Post |
| **Director** | Same as composer Director chip — command the next AI reply |
| **Continue** | Generate next reply |
| **Impersonate** | AI drafts the next **user** message as the persona |
| **Paths** | Roadway brainstorm sheet |
| **Auto-reply on/off** | Per-chat toggle |
| **Rewrite reply…** | On AI bubbles — shorten / expand / mood / custom — replace or new swipe |
| **Regenerate** | On AI bubbles — generate again (on non-last messages, removes later messages first) |
| **New swipe** | Another alternate reply |
| **Previous swipe** / **Next swipe** | When multiple swipes exist |

### Swipes

- Under AI bubbles: `◀ 1/N ▶` when applicable.
- On the **latest** AI message, ▶ past the last swipe **generates** a new alternate.
- Older multi-swipe bubbles: arrows browse only.

### Paths (Roadway)

- Long-press → **Paths**.
- ✨ generates ~6 **first-person** next-move options for {{user}} (`*I…*` actions, not persona name in `*asterisks*`).
- Tap a path → composer; edit before send.
- Check **two or more** → **Combine selected** → AI merges into one composer draft.
- Options **stay cached** until the chat’s last message changes, you clear/refresh (↻), or the chat is deleted.
- Uses tuned sampling + dedupe; **Roadway / Paths** note under Settings → AI collaborator.

### Toasts / overlays

- **Lore Triggered: …** — top overlay when World Info entries match and fit the budget.
- **Memory summary optimized** — after successful auto-summarize.

---

## 4. Settings hub

Opened from Home or Chat ⋮ → **Settings**. Top banner: **API & connection** (tap for key, model, catalogs).

### Menu (quick reference)

| Section | Screen | What it covers |
|---------|--------|----------------|
| *(banner)* | **API & connection** | API key, credits, chat model browser, image model, subscription toggle |
| **World** | **Personas** | Multiple {{user}} identities, avatars, default persona |
| **World** | **Characters** | ST-style cards, categories, import/export, AI wand, consistency check |
| **World** | **Opening scenes** | Saved narrator setups for new chats |
| **World** | **World Info & lore** | Global scan settings + global lorebook list |
| **World** | **Creation Center** | World workshops, import chat/lore/bundle, hub dashboard |
| **AI** | **Generation parameters** | Sampling, context size, auto-summarize |
| **AI** | **Global chat prompts** | App-wide system + post-history |
| **AI** | **AI collaborator** | Wand, Format, Paths, **Narrator** notes; Enter-to-send (desktop) |
| **AI** | **Character builds** | Model + sampling for slim card JSON generation |
| **App** | **Data folder** | Visible library location (open / copy / move) |
| **App** | **Appearance** | Theme Studio — presets, layout, colors, fonts, chat experience, avatars |
| **App** | **Backup, restore & sync** | `.anima-backup` export + cross-device sync file |

Detailed sections below follow this order where possible.

### 4.1 API & connection

**NanoGPT API key**

- Enter / replace / show-hide / save / remove.
- Stored as `api_key.txt` in your Anima folder so the library stays portable.

**See remaining credits**

- Wallet balance (USD; NANO when returned).
- Subscription state, weekly/daily/monthly usage, daily image allowance, reset times — as returned by NanoGPT.

**AI model (chat)**

- Live NanoGPT **model catalog** (`detailed=true`).
- **Category** filter first: **All**, **Uncensored & derestricted (broad)** (NanoGPT’s Uncensored category plus any model whose id/name/description contains uncensored, abliterated, derestricted, unfiltered, or unrestricted), then each NanoGPT category (Roleplay, Coding, etc.).
- **Provider** filter second: **Auto** first (`auto-model`, `auto-model-basic`, `auto-model-standard`, `auto-model-premium`), then A–Z — scoped to the category filter.
- Status line shows filtered count (e.g. `54 of 200 models · 12 providers`).
- **Selected model card** — summary for your current pick: stat chips, description, capability chips, pricing/Included; loads **TPS / TTFT / uptime %** from NanoGPT’s providers API when available.
- **Browse models** — searchable sheet for the current provider filter: same stats per row (context, max output, parameter size e.g. 70B, TPS, TTFT, uptime %, description, Included/category); tap to select.
- **Note:** NanoGPT’s website “Intelligence” benchmark (Artificial Analysis) is **not** in the public API — Anima shows what NanoGPT returns on models + providers endpoints.
- Refresh catalog; **custom model id** field still works for ids not in the list.
- Save model separately from API key.

**Image model (avatars)**

- Separate picker for **Generate avatar**.
- **Use subscription API on:** subscription image catalog only (hides paid wallet models).
- **Off:** full catalog with **Included** / **Paid** labels; Paid models ask for confirmation.

**Use subscription API**

- Toggles pay-as-you-go vs subscription base URL; reloads chat + image catalogs.

### 4.2 Personas

Multiple **{{user}}** identities.

**Fields** (all filled fields are labeled and sent on every chat generation)

| Field | Notes |
|-------|--------|
| Name | Required |
| Identity / role (`description`) | AI wand |
| Appearance | AI wand |
| Personality | AI wand |
| Background | AI wand |
| Goals | AI wand |
| Photo | Pick, **Generate avatar**, or clear |

**Actions**

- Create / edit / delete (at least one persona always kept).
- **Set as default** for new chats (long-press on list also works).
- Per-chat persona via chat ⋮ (can differ from default).
- Tap **your** avatar in chat → persona editor.

### 4.3 Characters

**List modes**

- **Manage** (Settings): tap → Edit; list stays open.
- **Pick** (new solo chat / chat switcher): tap selects and returns.

**List actions**

- Import card (JSON / PNG), **New**, export, delete.
- **Full cards only** filter chip — hides temporary NPCs (quick characters not promoted to full cards).
- Starter character **Anima** if library is empty.
- Avatar, description preview, lorebook count, category names on rows; **Temporary** badge on quick NPCs.

**Character categories (Anima-only)**

- Not SillyTavern card tags; do not export on cards.
- Dropdown: **All characters** + custom lists.
- Folder icon → create / rename / delete categories (deleting a list never deletes characters).
- Row ⋮ → **Categories** → multi-check membership (one character in many lists).
- Same filter on Group setup and Characters pick/manage.

**Editor — section chips**

One section visible at a time: **Identity** · **Story** · **Chat** · **Lore** · **Advanced**.

| Section | Typical fields |
|---------|----------------|
| Identity | Name, avatar, tags |
| Story | Description, personality, scenario |
| Chat | First message, alternate greetings, example dialogue |
| Lore | Link to embedded World Info / lorebook editor |
| Advanced | System prompt, post-history instructions |

**⋮ menu**

- **Consistency check** — AI read-only report; does not change the card.
- **Fix inconsistencies** — after a check, review AI-proposed field changes and **Update card** in one tap (card text fields only; lorebook unchanged).
- **Generate avatar** — NanoGPT image sheet.

**AI card builder** (plain-English generate/update slim fields: description, personality, mes_example, tags — not scenario, greetings, or per-card system/post-history).

**Card fields (full)**

| Field | Notes |
|-------|--------|
| Name | Required |
| Description, Personality, Scenario | AI wand |
| First message, Alternate greetings, Example messages | AI wand |
| System prompt (optional) | Blank = Anima default; `{{original}}` inserts default; presets + wand |
| Post-history instructions | Optional; presets + wand |
| World Info / lorebook | Embedded `character_book` |
| Avatar | Pick, Generate avatar, or clear; PNG import uses card image |

**AI wand (sparkle)** on creative fields: sends other filled fields as context; appends text; uses chat model + sampling + **Wand guidance note**.

**Import / export**

- Import: Card V1/V2/V3 JSON; PNG with `chara` / `ccv3`.
- Export: V2 JSON, V3 JSON, PNG (`chara`), PNG V3 (`chara` + `ccv3`).
- JPEG/WebP avatars may use placeholder on PNG export.

Imported creator notes, tags, extensions preserved on save/export even if not shown as edit fields.

**Temporary characters**

- Quick NPC: name + short note only (from chat ⋮ → **Add temporary character**, Manage cast **+**, or group setup).
- **Temporary** badge in Characters list; row ⋮ → **Promote to full character** opens the full editor.
- Temporary NPCs are hidden when **Full cards only** is on (Characters list and group cast picker).

### 4.4 Opening scenes

Saved narrator setups for new chats.

- Create / edit / delete.
- Auto-sync from Creation Center when you save or AI-generate an opening scene there.
- Browse when starting a new chat.
- Included in backup and sync.

### 4.5 World Info & lore

**App-wide scan settings**

- **Scan depth (messages)** — default 4 (1–50).
- **Token budget** — default 512 (approx; 10–4000).
- **Recursive scanning** — matched entry content can pull further active entries (shared budget + priority).
- Link to edit **character** lorebooks via Characters.

**Global lorebooks**

- Create, import ST/Anima JSON, enable/disable whole book, edit entries, export, delete.
- Enabled books inject by default; per-chat and group setup can narrow the set.
- Separate from each card’s embedded book.

**Lorebook list screen**

- Per-book: edit entries, export, delete, on/off toggle.
- **Consistency check** + **Fix inconsistencies** (same review-and-apply flow as character cards).

**Entry editor**

- Search + filter chips; **Advanced** section collapsible on each entry.
- Fields: Enabled, Always on, Label, Keywords, **Suggest keywords from content**, Selective + secondary keywords, Case-sensitive, Lore content, placement (Before/After desc), Insertion order, Priority, Comment.
- AI wand on Label / Keywords / Secondary / Content; keyword suggestions merge comma-separated.

**Matching behavior**

- Recent messages scanned; selective needs both key sets; always-on needs no keyword.
- Global + speaking character’s book merged; budget + priority apply.
- Chat overlay: **Lore Triggered: …** when entries fire.

### 4.6 Creation Center

Hub on **Home** (world tiles) and **Settings → Creation Center**.

#### Workshop list

**Filter chips:** All · Pinned · Has lore · Has cast

**App bar**

- **Import world bundle**
- **Import** → sheet: **Import existing chat**, **Import JSON lorebook file**, link existing World Info book

**Long-press workshop row**

- **Pin** / **Unpin**
- **Duplicate**
- **Delete**

**Import existing chat**

- **Import options** sheet: memory summary + last N recent messages (same N as Summarize “keep recent”, default 10); toggles for character cards, persona, embedded card lore, opening scene, Author’s Note; World Info lorebooks **off by default** and only books **explicitly linked** on that chat when enabled.

#### Workshop chat (minimal chrome)

**Status line** — context estimate snippet (tap banner or menu for details).

**Chip toolbar**

| Chip | Purpose |
|------|---------|
| **Mode** | Workshop chat mode (worldbuilding flavor) |
| **Reply length** | Short (~600 tokens) · Normal (~2K) · Detailed (~4K) — saved per workshop; applied to chat + regenerate |
| **Scene** / **Add scene** | Opening scene one-line bar; tap → editor sheet; **hides while keyboard open** |
| **Import** | When seeded from chat — view import source options |
| **Ideas** | Scene / prompt ideas when available |
| **Stale lore** warning chip | When lorebook needs update |

**Composer**

- Same patterns as chat: tap edit, long-press menu, **Save & regenerate** on your edited messages, **Rewrite reply…**, Regenerate / New swipe, swipe navigation.
- **Fix last** chip when last message is AI — applies a correction to that bubble **in place** (your note + one API call; no new AI bubble).
- **Stop** while streaming; no auto-scroll during stream.

**⋮ workshop menu**

| Item | Purpose |
|------|---------|
| **World dashboard** | Hub overview sheet (see below) |
| **Context estimate** | Detailed breakdown |
| **Start roleplay (pick cast)** | Shortcut to solo/group with workshop opening prefilled |
| **Create/Update lorebook** | NanoGPT → keyword entries → one global lorebook (one workshop ↔ one book). **First create:** optional preview → **Create lorebook**. **Update:** merges immediately from workshop chat (no fake “export anyway” audit). |
| **Create/Update opening scene** | Saves narrator prose; syncs to Opening scenes library |
| **Create AI characters** | Multi-select people from chat + lore → generate cards → review before save |
| **Update workshop cast** | Characters tied to this workshop (`linkedCharacterIds` or created here) → merge chat → review → save (does not scan whole Characters library) |
| **Update my persona** | When a persona is linked → merge workshop chat into persona fields → review → save (⋮ menu + dashboard persona row) |
| **Create my persona** | Pick one person from workshop + lore → player-focused fields → review before save |
| **Include linked lorebook in prompts** | Toggle — **off by default** after create; saves tokens; **Update lorebook** still uses the book |

**Workshop AI behavior** — the chat bot is **brainstorm-only**; it cannot save lore, cards, or scenes. It tells you to use the exact ⋮ menu labels above (no fake “pick A or B” action menus).

**Long-press message menu (workshop)**

| Action | Purpose |
|--------|---------|
| **Pin as canon** / **Unpin canon** | Canon pins preserved in summaries and exports |
| **Fold older chat into summary** | Manual world-summary fold |
| **Delete**, **Rewind**, edit, Continue, Regenerate, swipes, etc. | Same family as roleplay chat |
| **Apply correction** | On AI messages — revise in place with your correction note |

**World summary / token efficiency**

- `worldSummary` + `worldSummaryCoveredCount` — folds old workshop messages like chat memory.
- API sends **trimmed history** via history budget from Generation parameters.
- **Auto-fold** when auto-summarize enabled (same settings as roleplay chats).
- Manual: ⋮ **Summarize workshop** (dashboard), long-press **Fold older chat into summary**.
- Delta-style revision prompts — short corrections without reprinting full overviews.

**Opening scene AI generation**

- Length picker: **Short** / **Medium** / **Long**.
- When scene exists: **Fresh from chat** or **Revise from chat**.

#### World dashboard (hub overview sheet)

**Play this world** — pick cast → start roleplay with workshop opening.

**Status chips:** lorebook state (linked/stale/draft/missing), opening scene, character count, persona linked, canon pins, scene ideas.

**Sections:** source chat (if imported), world summary, world overview, linked characters (tap → **Update workshop cast**), persona (tap → **Update my persona** when linked), **Roleplay chats** started from this workshop (tap opens normal chat on Home list too).

**Actions**

| Action | Purpose |
|--------|---------|
| World Info lorebook | Open linked book editor |
| Opening scene | Editor |
| Summarize workshop | Full-transcript fold into world summary |
| Generate world overview | AI overview prose |
| Glossary → lorebook entries | Extract terms into lore entries |
| Generate scene ideas | AI scene starters |
| Locations & relationships | Edit structured sheets |
| Default chat kit | Default persona, lore, note for **Play this world** |
| Edit world summary | Manual edit |
| Refresh from linked chat | Re-import seed from source chat |
| Export world bundle | Portable workshop export |
| Duplicate workshop | Copy workshop |
| Merge with another workshop | Combine two workshops |

Deleting a workshop does **not** delete an already-created lorebook.

### 4.7 Generation parameters

- Temperature, Top P, Max tokens (optional).
- Frequency / Presence / Repetition penalties.
- Built-in presets (Balanced, Creative, Focused, Short, Long prose, Anti-repeat, Deterministic, Chaotic, Chatty, Mystery, Cozy, …).
- **Context size** in tokens (presets 1K–24K; range ~512–32K) — recent history packed per prompt; full history stays on device.
- **Auto-summarize long chats** — every N messages, keep N recent raw messages.
- Memory is a **Scene** (current place/cast, replaced each run) plus a **Ledger** (durable threads, promises, secrets — merged, not rewritten). Pin ledger lines in ⋮ → Memory summary so summarize never drops them. Open **Thread:** lines stay until the story resolves them. Lower temperature, **1024–4096** token budget (defaults 2048 when chat max is low); auto-tags **witnesses** on private facts; injection wrapper tells the model not to mimic summary style.

### 4.8 Global chat prompts

App-wide prompts merged into **every** chat (on top of each card; per-chat Author’s Note still applies).

- **System prompt** — presets + `{{user}}` / `{{char}}`.
- **Post-history instructions** — presets.

### 4.9 AI collaborator

Four editable guidance notes (presets / reset):

1. **Wand guidance note** — character wands, lore wands, Creation Center.
2. **Composer Format** — chat ✨ Format button.
3. **Roadway / Paths** — Paths brainstorming.
4. **Narrator** — chat **Narrator → Generate** (capped tokens; output cleanup).

**Enter to send** (desktop) — Enter sends, Shift+Enter newline; off = Enter always newline.

Format uses lower temperature to stay close to the draft. Wand uses normal model + sampling.

### 4.10 Character builds

Separate from main chat model — used for **slim card JSON** generation (Creation Center characters, **New character from chat**, AI card builder).

- Use main chat model **or** custom model id.
- Max tokens, temperature, top P.
- Editable **prompt note** for the build template.

### 4.11 Appearance (Theme Studio)

**Category chips:** Presets · Layout · Colors · Fonts · Chat · Avatars — one section at a time.

**Presets (8)**

- Glass: Obsidian Gold (default soft-glow), Midnight Sapphire, Emerald Noir, Rose Aurora.
- Solid: Slate Minimal, Ivory Ink (light), Cyber Violet, Forest Dusk.

**Layout**

- Background mode (solid / gradient / soft-glow).
- Corner roundness, glass opacity/blur.

**Colors**

- Background, accent, header, menu, text, bubble colors.
- **RP action** (`*asterisks*`) and **RP dialogue** (`"quotes"`) text colors.

**Fonts & text scales**

- Font family picks, size sliders for UI and chat.

**Chat experience**

| Option | Purpose |
|--------|---------|
| **Classic** vs **Storybook** layout | Storybook: speaker headers, side hero portraits fading into bubbles |
| **Chat background image** | Pick/upload; blur strength slider |
| **Bubble opacity** slider | See background through messages |
| **Speaker name above messages** | Toggle |
| **Side hero portrait** | Tall portrait beside each bubble (Storybook) |

**Avatars**

- Shape, size tier, fine scale slider for chat avatars.

Live preview; **Save** applies app-wide immediately via `AppearanceController`.

### 4.12 Backup, restore & sync

**Create backup**

- One `.anima-backup` plain JSON file.
- **Includes:** chats, characters, personas, categories, lorebooks, workshops, opening scenes, composer drafts, Paths cache, avatars, settings.
- **Excludes:** API key (re-enter after restore).
- **Desktop:** Save dialog (Downloads suggested).
- **Android:** system share sheet.

**Restore backup**

- Replaces only Anima data (whitelist); returns to Home.

**Cross-device sync**

- Pick one sync file (Google Drive on Android; file path on desktop).
- **Create sync file** / **Choose sync folder/file**.
- **Push to cloud** — overwrites sync file in place.
- **Pull from cloud** — restore from sync file when switching phone ↔ PC.
- **Forget sync file** — stop using saved location.
- Shows last push / pull times.

Not encrypted — treat like a private export.

---

## 5. Macros

In card fields, Author’s Note, examples, global prompts, etc.:

| Macro | Replaces with |
|-------|----------------|
| `{{user}}` / `<USER>` | Active chat persona name |
| `{{char}}` / `<BOT>` | Speaking character (group: current speaker) |
| `{{original}}` | In per-card system prompt — inserts Anima default system prompt |

Persona structured fields (`identity`, appearance, personality, background, goals) are injected into the system prompt when filled.

---

## 6. What gets sent to NanoGPT (typical turn)

Rough assembly order:

1. Global system prompt (if set) + character system prompt or Anima default (+ optional `{{original}}`).
2. Group member summaries when relevant.
3. Triggered lore **before** description.
4. Description, personality, scenario, example dialogue.
5. Triggered lore **after** description.
6. Persona name + structured persona text.
7. Opening scene (if injected; only sent to characters who were present at chat start).
8. Memory summary (if any; filtered per speaking character; private facts need witness tags).
9. Recent history packed to **context size** budget — **filtered per speaking character** by **presence / scene law** (narrator resets who’s present; named messages target only those characters; unnamed messages go only to present cast; character lines visible only to those present when sent; includes **Narrator** and **Director** timeline messages as system blocks).
10. Global post-history + per-card post-history + Author’s Note.

Streaming SSE; Stop cancels but keeps partial. Sampling from Generation parameters.

**Generate avatar** uses image API (`POST /api/v1/images`) with subscription-safe model rules.

---

## 7. Local data & background services

Everything lives in **one folder you can open** (default: `Documents/Anima` on Android, Linux, and Windows). First launch asks where to put it; **Settings → Data folder** can move it later. Copy that whole folder to back up or move Anima.

A tiny pointer file still sits in hidden app storage so the next launch knows which folder you chose. The library itself is not locked in Samsung app storage.

**Nothing uploaded to GitHub.** Do not put the Anima folder inside this git repo — `api_key.txt` is your NanoGPT key.

| Store | Contents |
|--------|----------|
| `api_key.txt` | NanoGPT API key |
| `anima_settings.json` | Model, sampling, theme, lore scan, collaborator notes, etc. |
| `anima_active_persona_id.txt` | Default persona id |
| `anima_characters.json` | Character cards, embedded lorebooks |
| `anima_character_categories.json` | Category lists + memberships |
| `anima_personas.json` | Personas |
| `anima_chats.json` | Sessions, messages, swipes, notes, persona, auto-reply, lore picks, memory |
| `anima_composer_drafts.json` | Unsent composer text per chat |
| `anima_roadway_cache.json` | Cached Paths per chat |
| `anima_lorebooks.json` | Global lorebooks |
| `anima_world_workshops.json` | Creation Center workshops + hub fields |
| `avatars/` | Local portrait files |
| `chat_backgrounds/` | User-picked chat backgrounds |
| `README.txt` | Short note that this folder is the library |
| `.anima-backup` / sync file | Optional shareable export (**no** API key) |

---

## 8. Current limits

- Windows build only on a Windows PC.
- Group chat is simple (chips + round-robin), not full SillyTavern group orchestration.
- No NovelAI / Agnai / Risu lore converters (ST JSON + `character_book` work).
- No TTS (removed).
- Paths only on long-press menu (not permanent composer button).
- Backup/sync plain JSON, not encrypted; API key excluded on purpose.
- PNG card export: JPEG/WebP avatars may use placeholder; PNG avatars embed correctly.
- **Presence / scene law** is always on (no toggle) — uses narrator + opening-scene name mentions; very old memory without witness tags may leak until re-summarized; honorifics don’t match names — use narrator/opening scene to establish who’s present.
- NanoGPT website **Intelligence** scores not available via API (Anima shows catalog + routing stats instead).
- Not yet: undo send, last-chat resume, pinned Author’s Note / mood chips, memory preview panel.
- Private personal app — not for Play Store / App Store.

---

## 9. Security

- Never commit API keys or secrets to Git.
- Use in-app **API & connection**. The key is saved as `api_key.txt` inside your Anima folder.
- `android/local.properties` stays gitignored.

---

## 10. For coding agents and external AI

| Document | Use when |
|----------|----------|
| **[`PROJECT_REFERENCE.md`](PROJECT_REFERENCE.md)** | **Full encyclopedia** — paste/attach for Gemini or any external AI; architecture, models, persistence, every screen, prompt assembly, mechanics |
| **[`AGENTS.md`](AGENTS.md)** | Cursor agents — current build status, roadmap, code map, machine notes, next actions |

Read and update **`AGENTS.md`** after meaningful code changes.

---

## Developer quick start

```bash
cd /path/to/Anima
flutter doctor
flutter pub get
flutter test
flutter analyze
flutter run -d windows   # or android device
```

**API key:** Settings → API & connection → paste key → Save.
