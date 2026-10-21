# Anima agent handoff — Living World (chat-native continuity)

Copy everything below the line into a **new Agent chat** opened in the **Anima** workspace.

> **Status (2026-10-20):** Phases **1–7 are done** on `experiment/living-world`.  
> For **what to build next**, follow **[`LIVING_WORLD_ROADMAP.md`](LIVING_WORLD_ROADMAP.md)** starting at **Phase 8**.  
> This handoff stays the **philosophy / locked scope** document — do not ignore its out-of-scope list.

---

## Who I am and what this chat is for

I am Jakwan. Anima is my passion project — my first real app. Cursor agents wrote most of the code; I direct product. Treat me as product owner / director, not as someone who can recite every service file. Explore the repo carefully before proposing big changes. Prefer thin, reversible slices over rewrites.

**This conversation is a build handoff for Living World**, not a rewrite of Anima and not a full Dwarf Fortress clone.

**True end-goal (owner):** a DF-**lite** engine **under** Anima’s chat shell — the world updates organically as he plays (validated under-the-hood state), not a frozen factory notebook he must hand-edit every time. See the roadmap.

Your job is to:

1. Understand the locked decision and scope below.
2. Explore Anima’s existing memory / lore / summary / prompt-assembly paths **and** the shipped Living World code on `experiment/living-world`.
3. Work **only on `experiment/living-world`** (or ask before branching) so main/stable Anima stays the daily driver fallback.
4. Build toward the **roadmap** phases — sweet-spot living world: structured canon the app owns, retrieved into chat, **updated through a validated turn pipeline** — AI roleplays from that canon.

Do **not** scrap Anima’s chat-first experience. Do **not** port Chronicle wholesale. Do **not** chase full Dwarf Fortress simulation (fortress UI, fluids, planet ticks).

---

## Decision (locked unless I change it)

| Keep | Do not do |
| --- | --- |
| **Anima** as the app I open and play in | Rewrite chat UI, Theme Studio, or invent a heavy new architecture religion |
| Anima’s glass UI, NanoGPT catalog, SillyTavern-inspired chat loop | Require a board-game / Run Board / map as the only mode |
| Chat-native play (type → characters reply) | 2D/3D maps, fortress builder, graphics-heavy simulation UI |
| Structured world notebook as **source of truth** for tracked canon | Let the AI silently invent or overwrite hard state |
| Genre-open worlds (any setting I create) | Bake in dwarves, fantasy-only, RPG combat, or fortress themes |
| Experiment on a **feature branch** | Commit experimental core changes straight to main |
| Sweet-spot scale (~dozens of named people, places, events) | Full-planet sim, hundreds/thousands of agents, fluids, organs, DF tick rate |

**One-line north star:**  
`App / engine remembers canon. AI narrates and roleplays from retrieved canon — it does not silently invent or overwrite authoritative state.`

**Product phrase (use this so agents don’t build the wrong thing):**  
**Chat-native living world** — Anima is the theater; a world notebook + light engine is the continuity desk; a **world factory** (later) authors big notebooks. Creation Center today is *not* that factory.

---

## Creation Center vs Living World (read this — easy to get wrong)

**Owner clarified this explicitly:**

- Today’s **Creation Center** is a workshop **chat**. It still hits context limits. It can draft cards/lorebooks; it is **not** capable (as-is) of honestly compiling a ~20–50 person structured world notebook in one thread.
- That does **not** mean “rewrite Creation Center on day one.”
- **Critical path first:** Living World **engine** = save/load world JSON, retrieve relevant facts into *play* chat, validated canon updates. That can work with a small sample world, import, or a thin generate-and-save path that never uses Creation Center.
- **World factory later (Phase 4):** multi-pass compile into a notebook on disk (places → people → relationships → events), each step reading/writing the file — not “one smarter workshop chat that remembers everything.” That may become a **new Worlds hub** and/or a **major rethink of Creation Center**. Either is fine; do not block Phase 0–2 on it.
- **Do not** assume “just hook Living World into Creation Center as it exists.”
- **Do not** start by rewriting Creation Center before the warehouse (world notebook + play retrieval) exists.

**Dev vs in-app models (for clarity):**

- **NanoGPT** stays the in-app chat/roleplay model (playtime).
- **Strong models (Grok / Argon / big NanoGPT models)** are optional later for *drafting world data* in chunks; during development they may also help write Anima code in Cursor. They are **not** the live memory during play.
- Living World **code** = one shared engine in the app. Each **world** = data (JSON notebook), not a custom engine per setting.

---

## Why this exists (the itch)

Despite lorebooks, character cards, summarize, presence, and other helpers, Anima still fails on long-running canon:

- Context length limits
- Long-term memory of decisions and events
- Consistency across a long session / multi-session play
- Group chats feeling overloaded at ~3–4 speaking characters

Summarization helps a little. It does **not** replace a real store of “what is true in this world.” Models forget, compress wrong, or invent. That is a **systems** problem, not a “write a better system prompt” problem.

I want the *feeling* of a living world (inspired by how Dwarf Fortress keeps facts outside the storyteller) **inside Anima’s text/chat shell** — without DF graphics, maps, or fortress mechanics.

**Target upgrade that already changes everything for me:**  
Being able to have on the order of **~50 named, real people** in a world (plus places, relationships, event history) — even if only a few speak in a given scene — instead of the AI collapsing when a group chat has more than ~3–4 characters.

I do **not** need a full planet, hundreds of people, fluid dynamics, organ simulation, or console-game scope. Those are out.

---

## Sweet spot (IN SCOPE) — build toward this

### Must feel like this when it works

- I still open Anima and chat the way I do today when the feature flag is off.
- When Living World is on for a chat/world: after many turns, the system can still answer “what did X decide?” / “what happened at Y?” / “how does A feel about B?” from **stored facts**, not vibes.
- Relevant canon is **retrieved selectively** into the prompt (never dump the whole world every turn).
- Off-screen people can still *exist* as data; only present / relevant people need heavy prompt space.
- AI remains voice / roleplay / narration; structured store remains authority for tracked facts.

### Minimum “alive world” kit (first real milestone)

Aim for a small but real world, not a toy stub:

| Concept | Role |
| --- | --- |
| **World** | Named playable world container (id, title, genre-agnostic) |
| **Person** | id, name, short description / personality notes, optional link to Anima character card |
| **Place** | id, name, description, connections to other places (nodes, not a tile map) |
| **Relationship** | A↔B sentiment or tags (−100…100 and/or simple labels) |
| **Event / timeline** | Timestamped or turn-stamped facts (“X decided Y at place Z”) |
| **Flags** | Simple true/false or enum facts (“knows about the letter”, “banished from harbor”) |
| **Live state** | Optional: who is where *right now*, active scene place, maybe simple inventory later |
| **World save** | Versioned JSON under the Anima library folder |

**Scale target for v1 thinking:** roughly **8–20 places**, **20–50 named people**, relationships + event log + flags — enough to feel like a town/region cast, not a planet.

### Play loop (chat-native)

Rough shape (adapt to Anima’s real prompt pipeline; don’t invent a second app):

1. Player acts in chat (normal Anima compose / continue / guide / etc.).
2. App retrieves **relevant** world facts for this speaker / place / recent topics.
3. AI roleplays from chat + retrieved canon.
4. After the turn (or via an explicit “update world” / extract step), candidate fact changes are proposed.
5. **Validate before canon:** typed JSON, schema checks, and/or a review sheet — AI must not silently rewrite hard state.

Invariant:  
`player intent → (optional engine resolve) → persist validated state → AI prose from that state`.

### Integration style (Anima-first)

- Hang off existing patterns: `AppDataRoot` / library folder, services, prompt builder, chat session fields.
- Prefer a **feature flag** (settings or per-chat) so classic Anima remains default.
- Prefer **optional World Memory pack injected into prompt builder** over a full engine-owned action loop as the *first* slice.
- Reuse Anima character cards / personas where it helps (link person → card), but world canon must not depend only on card prose.
- Lorebooks and Memory Summary can stay; Living World is the **authoritative** layer for tracked facts. Do not rip them out in v1.

### Later (still in long-term vision, NOT first coding tasks)

- **World factory:** multi-pass AI compile brainstorm → validated world JSON on disk (new Worlds UI and/or evolved Creation Center — decide after play loop works).
- Light “systems” that update relationships/flags from resolved events (still not DF tick rate).
- Story-time / local simulation (only near the active scene), not full-world every second.

---

## Out of scope (DO NOT build)

Push back hard if a plan drifts here:

- Porting / merging the Chronicle Flutter app wholesale
- Run Board / map / fortress / graphics as required UI
- Dwarf / fantasy / RPG combat / resource-gathering theme baked into types
- Full-planet simulation, hundreds/thousands of simultaneous agents
- Fluids, weather engines, organ/material simulation, DF-style fortress engineering
- Big-bang rewrite of chat, settings, Theme Studio, or NanoGPT integration
- **Rewriting Creation Center as the first milestone** (factory comes after the notebook + play retrieval work)
- **Treating current Creation Center workshop chat as sufficient** for large world authoring
- “Procedural generation theater” that doesn’t fix memory / canon
- Replacing lorebooks/summarize overnight with an all-or-nothing rewrite
- Silent AI writes to inventory/location/relationships/flags without validation
- Committing experimental breakage to **main**

---

## Related prior thinking (optional context)

- An earlier side experiment (“Chronicle”) explored engine-owned state + AI narration only. **Do not port that app.** Living World in Anima is the product path. If a Chronicle folder still exists on disk, it is philosophy/reference at most — never a merge mandate.
- Dwarf Fortress inspiration = **method** (facts outside the storyteller, consequences stick), not theme or graphics.

---

## What I love about Anima (do not break this)

- Daily-driver chat / RP workflow after months of iteration
- Glass Theme Studio, NanoGPT catalog / favorites / credits / filters
- Solo + group chat tools: Director, Narrator, presence, Paths, Guide, swipes, etc.
- Creation Center, cards, lorebooks, backup/restore, library folder model

If a proposal makes Anima feel like a different app, push back and offer a **chat-native** design.

---

## Git / branch / safety rules

Anima is on GitHub. Experimental work must stay off my stable daily build until I merge.

Before any large change set:

1. Check `git status` / current branch.
2. Create and switch to something like:  
   `experiment/living-world`  
   (or a better name we agree on — ask me if unsure).
3. Keep commits focused; **I decide when to merge.**
4. **Ask before commits / PRs / destructive git.** My usual rule: only commit when I explicitly ask.
5. Feature-flag new behavior; classic Anima play remains default on the branch too where practical.
6. Keep `flutter analyze` clean and `flutter test` green (or fix what you break).
7. Never commit API keys. Device / Anima folder storage only.

---

## Phase plan (do these in order)

### Phase 0 — Orient (do this first; little or no product code)

1. Map where Anima **already** stores or injects memory-ish things:
   - character cards, personas
   - lorebooks / World Info
   - memory summary (Scene + Ledger) + auto-summarize
   - chat history trim / context size
   - presence / narrator / director
   - Creation Center workshop data
   - any RAG/embeddings (likely none — confirm)
2. Summarize back to me in **plain English**: what exists, what fails for long-running canon, where a structured world store could hang with **minimal coupling**.
3. Propose **2–3 integration options** ranked by invasiveness. Example poles:
   - **A (thinnest):** optional World Memory JSON + retrieve-and-inject into prompt builder; manual or AI-assisted fact capture with review
   - **B (medium):** per-chat/world live state (who/where/relationships) updated after turns with validation
   - **C (heavier):** engine-resolves-actions-first loop (closer to Chronicle) — only if A/B clearly aren’t enough
4. **Recommend the thinnest slice that still addresses the itch.** Ask for my go-ahead before creating the branch / writing substantial code.

### Phase 1 — Safe experiment branch + thinnest vertical slice

Only after I agree on an approach:

- Create/use the dedicated branch.
- Add models + JSON persistence under the Anima library folder (e.g. `worlds/` or similar — fit existing `AppDataRoot` patterns).
- Feature flag: Living World off by default.
- Wire **retrieve relevant facts → inject into existing prompt assembly** for one chat path (solo or group — pick the smallest useful path and say why).
- Include tests for parse/validate/retrieve; keep analyze/tests green.
- Update living docs when architecture lands (`AGENTS.md`, `PROJECT_REFERENCE.md`, `README.md` if user-visible).

### Phase 2 — Canon write path (still thin)

- After turns or via an explicit control: propose fact updates (events, relationship deltas, flags, location).
- **Review before apply** (sheet or confirm) OR strict schema validation with rejection — no silent overwrite.
- Prove the product win: a long chat still recalls a decision stored as an event/flag without relying on raw history.

### Phase 3 — Cast scale (the “~50 people” win)

- Support a world cast much larger than who fits in the prompt.
- Scene/presence already helps; Living World should make “many exist, few speak” natural.
- Retrieval by place, name mentions, relationship to speaker, recent events — stay inside context budget.
- Optional: link world people to Anima character cards for richer voice when they speak.

### Phase 4 — Authoring / world factory (only after play loop works)

- Multi-pass compile: brainstorm → chunked AI drafts → validate → merge into world JSON on disk (not one endless workshop chat).
- Import/export a world file; simple editors/lists for people/places/events beat a giant chat thread.
- May be a **new Worlds hub** and/or a **major Creation Center rethink** — propose tradeoffs then; owner is fine with a rewrite *when it serves this goal*, but not as Phase 0–1.
- Do not block Phase 1–2 on a full world factory UI. Sample/import worlds are enough to prove play.

---

## Design constraints & principles (carry these)

1. **Anima first.** Chat shell stays; Living World feeds it.
2. **Notebook/DB is source of truth for tracked canon; AI is not.**
3. **Chat-native.** No required map/board mode.
4. **Offline core where possible.** Local JSON in the Anima library; network only for completions / optional authoring.
5. **Genre-agnostic types.** No dwarf/fantasy assumptions in schemas or transition logic.
6. **Uncensored narrator/roleplay policy** stays; do not add moralizing guardrails to app-owned prompts.
7. **Thin slices + feature flags + tests.**
8. **Living docs** stay current when mechanics/architecture/user-visible behavior change.
9. **Secrets:** never commit API keys.
10. **I approve merges and philosophy shifts.** If something touches “the app’s very core,” pause and explain tradeoffs before coding a mountain.
11. **Simulate local / on story beats**, not a full-world tick forever.
12. **Plain English** with me — I’m the director, not a career programmer.

---

## Success / failure

### Success looks like

- Flag off → Anima feels like today’s app.
- Flag on → world facts persist and come back correctly days later.
- I can maintain a cast far beyond 3–4 speaking roles because most people live in the notebook, not in every prompt.
- I can build cool worlds and *play* them inside Anima without the AI rewriting history.
- Main branch stays untouched until I merge.

### Failure looks like

- Big-bang rewrite
- Silent AI canon edits
- Map/board-required play
- DF-scope systems early
- Breaking main
- Fancy procedural demos that don’t fix “the world forgot”

---

## How I work with agents

- I prefer **working directly in code**: explore, propose, implement, iterate.
- Communicate directly and concisely; use longer design writeups when the decision is architectural.
- Ask me before git commits / PRs / anything destructive.
- When confused about product intent, ask — don’t invent a second product inside Anima.
- Read `AGENTS.md` at session start; follow Anima’s existing security and living-doc rules.

---

## Your first reply in the new chat should

**If Phases 1–4 are already in the tree (they are):**

1. Confirm you understood the end-goal: **organic validated world updates under Anima chat (DF-lite method)** — not a frozen notebook and not a fortress clone.
2. Confirm you’ll work on **`experiment/living-world`** and follow **[`LIVING_WORLD_ROADMAP.md`](LIVING_WORLD_ROADMAP.md)** from the first unchecked phase (likely **Phase 5**).
3. Briefly state what Phase 5 will deliver in plain English.
4. Ask for go-ahead before large coding / commits.

**Only if starting from scratch on main with no Living World code:** do Phase 0 exploration first, then follow the original Phase 1–4 plan in this file before the roadmap.

---

## Short paste if you need a TL;DR later

> Keep Anima. Living World = structured JSON canon the app owns; retrieve into chat; AI roleplays; **no silent unvalidated overwrites**. Phases 1–4 shipped (notebook, retrieve, reviewed writes, cast scale, factory). End-goal = DF-lite **under** chat: world changes as you play via a turn pipeline — see `LIVING_WORLD_ROADMAP.md` Phase 5+. Not a planet, not DF graphics/maps/fortress systems. Creation Center ≠ living engine. Work on `experiment/living-world`. Ask before commits/merge. Adults; uncensored app prompts.
