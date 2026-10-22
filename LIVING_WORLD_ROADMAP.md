# Living World roadmap — toward a true “living” under-the-hood world

> **For every agent:** Read this **after** [`LIVING_WORLD_HANDOFF_PROMPT.md`](LIVING_WORLD_HANDOFF_PROMPT.md).  
> Phases **1–11 + Phase 13** are shipped; **Phase 12 agent package** (defaults + docs + soak guide) is on `experiment/living-world` (build 79+).  
> **Next:** owner soak on phone + Windows, then explicit **merge Living World** / **merge to main**.  
> Phase 12 **soak + merge** still need owner sign-off. Update checkboxes when a phase lands.  
> Keep plain English. **Do not merge to `main` until the owner explicitly approves after soak.**

---

## When the owner says “go ahead with next phase” (mandatory playbook)

This is the **default standing order** for local Cursor agents in this repo. No cloud agents.

### Trigger phrases (treat as the same command)

- “go ahead with next phase”
- “next phase”
- “continue the roadmap”
- “go”

### What you do (in order — every time)

1. **Branch:** `git checkout experiment/living-world` and `git pull` (or fetch + fast-forward). All Living World coding stays on this branch.
2. **Read:** this file → find the **first agent-build phase whose deliverable checkboxes are not all done**. Skip 1–4 (shipped). **Skip Phase 12 owner-only boxes** (soak / merge approve) — those are not agent coding. As of 2026-10-21 Phase **13 is shipped**; remaining work is **owner soak + merge approve** (not agent coding). Also skim `AGENTS.md` current status.
3. **Implement that one phase only** (do not start the next phase in the same session unless the owner explicitly says to continue after you finished and pushed).
4. **Verify:** `flutter analyze` clean + `flutter test` green (fix what you break).
5. **Living docs (required before commit):**
   - Check off completed boxes in **this file** for that phase
   - Update **`AGENTS.md`** (date, last agent action, what works, next actions, code map if new files)
   - Update **`PROJECT_REFERENCE.md` §15b** (and any other sections you touched)
   - Update **`README.md`** if anything user-visible changed
6. **Commit + push (standing owner permission for roadmap phases):**
   - Commit on `experiment/living-world` with a clear message like `Phase N Living World: …`
   - `git push origin experiment/living-world`
   - Do **not** push to `main` / do **not** overwrite stable `v1.0.0` unless the owner asks
7. **Stop and report:** Tell the owner the phase number, what changed in plain English, that it is committed+pushed, and that the next phrase is still “go ahead with next phase.”

### Standing permissions (owner, 2026-10-20)

- ✅ Commit and push **after each completed roadmap phase** on `experiment/living-world`
- ✅ Update all living documents as part of that phase
- ❌ Merge to `main` without explicit ask
- ❌ Skip analyze/tests
- ❌ Silent unvalidated canon writes (even in later phases)

### If blocked

Stop, commit nothing half-baked (or commit a WIP only if the owner asked), and explain the blocker in plain English.

---

## End-goal (owner’s true intention)

Jakwan wants Anima to feel like a **Dwarf Fortress–lite engine under a chat shell**:

- He **acts in the world** (normal Anima chat: send, Continue, Guide, Narrator, Director…).
- The **world moves with him** — places, people, relationships, decisions, and “what is true” change **organically after turns**, not only when he opens a manual editor.
- Something **under the hood** (app-owned state + light resolution) writes and rewrites durable facts in **real time relative to play**, the way a game keeps a save state — while Anima remains the **theater** (prose, cards, Theme Studio, NanoGPT voice).

**Product phrase:**  
**Chat-native living world** — Anima is the stage; a structured notebook + turn engine is the continuity desk; the AI narrates from (and proposes against) engine-owned canon.

**Success feeling (playtest bar):**  
After many turns and days later, asking “what did X decide?”, “where is Y?”, “how does A feel about B?” is answered from **stored facts that evolved during play**, not from vibes or a frozen factory dump he never updated.

---

## What “DF-lite” means here (method, not clone)

| Take from Dwarf Fortress | Do **not** build |
| --- | --- |
| Facts live **outside** the storyteller | Fortress / map / 2D–3D graphics as required UI |
| Consequences **stick** across time | Fluids, organs, materials, weather engines |
| Off-screen life can still **exist as data** | Full-planet sim; hundreds/thousands of concurrent agents |
| Systems nudge state; prose explains it | Dwarf/fantasy/RPG combat baked into schemas |
| Local “story time” near the player | Real-time continuous tick forever |

**Invariant (never drop):**  
`player intent → (engine resolve / propose) → persist **validated** state → AI prose from that state`

Silent, unvalidated AI overwrites of hard canon are **always** out of scope — even at the end-goal. “Organic” means **automatic turn pipeline**, not “model may invent anything into the save file.”

---

## Where we are now (Phases 1–11 — DONE through invisible-engine UX)

Shipped on `experiment/living-world` (see [`AGENTS.md`](AGENTS.md) / [`PROJECT_REFERENCE.md`](PROJECT_REFERENCE.md) §15b):

| Phase | What it delivered |
| --- | --- |
| **1** | World notebook JSON under `worlds/`; per-chat bind; retrieve-and-inject into prompts |
| **2** | Explicit **Update world from chat…** → propose → **review sheet** → save |
| **3** | Cast-scale scoring/caps; group retrieve; card-link boosts |
| **4** | Worlds hub + multi-pass **world factory** + notebook editor/export |
| **5** | After-turn propose / auto-safe + undo |
| **6** | Resolve-before-narrate spine + World log |
| **7** | Relationship drift, narrator presence sync, routineHints, flag recipes |
| **8** | Near-scene ticks (active place + connected radius); manual Advance a beat |
| **9** | Schema v2: threads / promises / secrets / inventory-lite + retrieve + ops |
| **10** | Card-link picker UX; hard-pin linked speaker + threads; group-react pack + after-turn; `.anima-backup` includes `worlds/`; context estimate pack tokens; factory seed from Creation Center (one-way) |
| **11** | Ambient World-updated chip; disk-backed Review pending; hub timeline/undo/export; plain-English policies; cancel-on-leave + queued after-turn; playtest checklist |

**Honest gap vs end-goal:**  
Invisible UX is in. Phase 12 **agent package** (opt-in defaults verified, docs, soak/merge guide) is ready. Remaining: **owner soak on phone + Windows**, then **explicit merge approve**.

Creation Center remains a workshop chat — **not** the living engine. Do not rewrite it as a substitute for this roadmap.

---

## Architecture target (evolve toward this)

```
┌─────────────────────────────────────────────────────────────┐
│  Anima chat UI (unchanged shell: bubbles, moods, presence…) │
└───────────────────────────┬─────────────────────────────────┘
                            │ each player/AI turn
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Turn pipeline (NEW over time)                              │
│  1. Retrieve relevant canon pack (exists)                   │
│  2. Generate reply from pack + chat (exists)                │
│  3. Extract / resolve candidate state deltas (Phase 5–7)    │
│  4. Validate schema + id integrity (exists; harden)         │
│  5. Apply per world policy: review / auto-safe / undo log   │
│  6. Persist notebook; optional light off-screen tick (8+)   │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Living World notebook (source of truth)                    │
│  people · places · relationships · events · flags · live    │
│  (+ later: threads, inventories-lite, schedules, factions)  │
└─────────────────────────────────────────────────────────────┘
```

**Roles:**

- **Notebook / engine** — what is true.  
- **AI** — voice, improvisation inside bounds, help proposing deltas.  
- **Player** — intent in chat; optional review; can always edit the notebook.

---

## Phase plan (build these in order)

Update checkboxes as phases complete. Each phase must leave `flutter analyze` clean and tests green (or fix what it breaks). Stay on `experiment/living-world` until the owner merges.

### Phase 5 — Organic write loop (auto after turn) ✅ foundation for “it changes as I play”

**Goal:** After play turns, the notebook can update **without** hunting a menu — still validated; never silent garbage.

**Owner feeling:** “I played a scene; the world recorded what mattered.”

**Deliverables:**

- [x] App-wide policy setting (Settings → Living Worlds + chat ⋮ → World play mode…):
  - **Manual only** (⋮ → Update world from chat…)
  - **Propose after turn** (review sheet after each successful reply)
  - **Auto-apply safe ops** (events, flags, who/where, active place) + review for relationships
- [x] Hook into post-reply path (`_streamAssistantReply` success): after persist, `_maybeLivingWorldAfterTurn` (solo + group; skip if unbound / manual / no key).
- [x] Guard: `_livingWorldAfterTurnBusy` so overlapping proposes don’t stack; soft-fail errors don’t break chat.
- [x] Undo buffer: `LivingWorldUndoService` (last 5 snapshots under `worlds/<id>.undo.json`); chat ⋮ → Undo last world update; manual Update also pushes undo.
- [x] Tests: policy storage, safe/risky partition, undo restore.
- [x] Living docs + README (user-visible policy).

**Acceptance:**

- Bound chat, policy “propose after turn”: finish a beat → proposals appear without opening the old menu.
- Auto-safe mode: a clear decision in chat becomes an event/flag on disk; next retrieve sees it.
- Classic Anima (unbound / policy off) unchanged.

**Agent notes:** Prefer extending Phase 2 services over a second write path. Keep review UI mobile-friendly (sheet, not desktop modal hell).

**Shipped:** 2026-10-20 on `experiment/living-world`.

---

### Phase 6 — Turn resolution spine (engine before prose when it matters) ✅

**Goal:** Separate **what changed in the world** from **how it was narrated**. Move toward the handoff invariant with a real resolve step.

**Owner feeling:** “The app decided the fact; the AI described it — not the other way around.”

**Deliverables:**

- [x] `TurnResolution` model: structured deltas (wraps typed `LivingWorldCanonUpdate` ops) + kind (resolve-before / after-turn / manual).
- [x] Optional **two-step generation** behind Settings / chat ⋮ **Resolve before reply (Living mode)**:
  1. Resolve/propose deltas from player intent + prior pack + last messages  
  2. Persist validated **safe** deltas (relationships deferred)  
  3. Generate roleplay **with the updated pack** + optional “as of this turn” block  
- [x] Fallback: single-call reply + post-hoc extract (Phase 5) when two-step is off or fails.
- [x] Logging: `LivingWorldLogService` (`worlds/<id>.log.json`) + chat ⋮ → **World log…**
- [x] Tests for ordering: persist-before-narrate when two-step on (`living_world_phase6_test.dart`).

**Acceptance:**

- With two-step on: a location change applied mid-turn is visible in the same reply’s retrieved pack (or an explicit “as of this turn” block).
- With two-step off: Phase 5 behavior still works.

**Agent notes:** Don’t break streaming UX — either resolve before stream starts, or stream then reconcile carefully. Prefer resolve-before-stream for correctness when two-step is on.

**Shipped:** 2026-10-20 on `experiment/living-world`. Living mode is opt-in (extra API call); needs Propose or Auto-safe play mode to write. Resolve runs before stream; relationships still review after the reply when deferred.

---

### Phase 7 — Light world systems (relationships, presence, schedules) ✅

**Goal:** Some state changes come from **rules + events**, not only LLM extraction — closer to DF “systems.”

**Owner feeling:** “Trust and presence drift even when nobody dumped a paragraph about it.”

**Deliverables (genre-agnostic):**

- [x] Relationship drift hooks: applying an event with person ids can nudge scores by tags (aid / betrayal / promise) with clamps.
- [x] Presence sync: Narrator / liveState / “who is where” stay consistent; leavers/arrivals update `personLocations` via validated ops.
- [x] Simple **schedules** optional on people (`routineHints` or time-of-day intents) — soft, not a full calendar sim.
- [x] Flag recipes: e.g. event text/types can set known keys (`knows_X`, `banished_from_Y`) through explicit rule tables + AI propose, not freeform silent edits.
- [x] Tests for drift clamps and id validation.

**Acceptance:**

- Applying “A helped B” style events moves relationship scores predictably.
- Moving a person in liveState shows up in retrieve without hand-editing JSON.

**Out for this phase:** combat engines, economy, hunger/thirst sims.

**Shipped:** 2026-10-20 on `experiment/living-world`. Systems run after validated `applyUpdates`; Narrator presence sync when play mode is non-manual; relationships still reviewable when proposed explicitly.

---

### Phase 8 — Story-local simulation (near-scene “ticks”) ✅

**Goal:** Between or after turns, **only near the active place / cast**, run a small tick so the world isn’t frozen off-screen — still tiny vs DF.

**Owner feeling:** “While I was in the pier scene, the market didn’t have to be simulated in full, but something nearby could have shifted.”

**Deliverables:**

- [x] `LivingWorldSimulator`: input = notebook + active place + radius (connected places, bidirectional) + last N events.
- [x] Tick outputs = validated ops only (short events / soft who-where from routineHints), capped count — no relationship invent; systems may still drift from new events.
- [x] Trigger options: Settings **Near-scene ticks** Off / After each turn / Every N turns; manual **Advance world a beat…** in Worlds hub ⋮ and chat ⋮.
- [x] Hard caps: max people, max ops, radius hops (settings); rules-first so no API required for ticks.
- [x] Off-screen people: **short** ambient event lines from routineHints — never full card prose; near-scene roster formatter for any future AI assist.
- [x] Tests: radius / 40-person caps / empty world / apply→retrieve / TurnResolution `nearSceneTick`.

**Acceptance:**

- A 40-person world: tick touches a handful near the scene, not everyone.
- Unbound chats never tick.

**Out:** global every-second real-time sim; weather/fluids.

**Shipped:** 2026-10-21 on `experiment/living-world`. Default trigger = **off** (manual Advance only). Auto ticks run after the Phase 5 after-turn pipeline when enabled.

---

### Phase 9 — Continuity objects (threads, promises, secrets, inventory-lite) ✅

**Goal:** Long-run play remembers **open loops**, not only atomic events.

**Owner feeling:** “The letter, the promise, the secret — the world still knows.”

**Deliverables:**

- [x] Schema bump (versioned): `threads` / `promises` / `secrets` with ids, status (open/closed), witness person ids, optional place.
- [x] Real types (not flag conventions) — schema **v2**.
- [x] Inventory-lite: `WorldPerson.inventory` list of short item names (no crafting tree).
- [x] Retrieve scores these when mentioned / witnessed by speaker (prefer open).
- [x] Update ops (`upsert*` / `close*` / `setInventory`) + factory seedCanon + editor Canon tab.
- [x] Migration from schema v1 → v2 in `LivingWorld.fromJson` (empty continuity; next save upgrades).

**Acceptance:**

- A promise recorded mid-arc is retrieved sessions later until closed.
- Schema migration doesn’t wipe existing harbor/factory worlds.

**Shipped:** 2026-10-21 on `experiment/living-world`. Continuity ops are auto-safe (like events/flags); relationships still review-only.

---

### Phase 10 — Deeper play integration (cards, groups, backup) ✅

**Goal:** Living World feels native to Anima’s best tools, not a side folder.

**Deliverables:**

- [x] Stronger person ↔ character card linking UX (pick card from editor; auto-suggest by name).
- [x] When a linked card speaks, pack always prioritizes that person + their threads.
- [x] Group: optional shared world log; per-speaker retrieve already exists — harden so group-react doesn’t skip world updates.
- [x] Include `worlds/` in `.anima-backup` / restore whitelist.
- [x] Context estimate includes Living World pack tokens.
- [x] Optional: seed factory from Creation Center export (one-way) — **do not** make workshop chat the engine.

**Acceptance:**

- Backup/restore brings notebooks to another device.
- Context estimate shows pack size.

**Shipped:** 2026-10-21 on `experiment/living-world`. World log already shared by `worldId`; sheet copy notes that. Group-react injects pack + runs after-turn pipeline. Factory **Seed from Creation Center…** prefills pitch only.

---

### Phase 11 — “Invisible engine” UX polish ✅

**Goal:** The under-the-hood world is felt more than managed.

**Deliverables:**

- [x] Ambient “World updated” chip / subtle log (not modal every turn when auto-safe).
- [x] One-tap “Review pending world changes.” (`LivingWorldPendingService` → `worlds/<id>.pending.json`)
- [x] Worlds hub: timeline of applied packs; revert; export.
- [x] Policies explained in plain English in Settings.
- [x] Performance: don’t block typing; queue resolves; cancel on leave chat.
- [x] Playtest checklist for owner: [`docs/LIVING_WORLD_PLAYTEST.md`](docs/LIVING_WORLD_PLAYTEST.md) (owner sign-off table — run before Phase 12 merge).

**Acceptance:**

- Owner can play an evening with auto-safe on and only glance at the world log.
- Manual editor still available for surgery.

**Shipped:** 2026-10-21 on `experiment/living-world`.

---

### Phase 12 — Merge readiness ⏳ agent package + Phase 13 done; await owner soak + approve

**Goal:** Living World is good enough to become part of daily-driver Anima on `main`.

**Deliverables:**

- [x] Feature still **off by default** (unbound chat = classic Anima) — verified; regression tests in `test/living_world_phase12_test.dart`.
- [x] Docs: README, PROJECT_REFERENCE §15b, AGENTS status, this roadmap, [`docs/LIVING_WORLD_MERGE_READINESS.md`](docs/LIVING_WORLD_MERGE_READINESS.md).
- [x] **Phase 13 shipped** (world → character / persona bridge — 2026-10-21).
- [ ] Prerelease soak: multi-session play on **phone + Windows** (owner — see merge readiness doc + [`docs/LIVING_WORLD_PLAYTEST.md`](docs/LIVING_WORLD_PLAYTEST.md)).
- [ ] Owner explicit approve → merge `experiment/living-world` → `main` → normal `v1.0.0` deploy.

**Do not merge** if: silent corruption bugs, analyze/tests red, unbound chat regresses, or soak table unsigned.

**Agent package shipped:** 2026-10-21 on `experiment/living-world`. Merge stays **blocked** until Jakwan soak + explicit merge phrase.

---

### Phase 13 — World → character / persona bridge ✅

**Goal:** Fix the missing link: after making a Living World notebook, Jakwan can turn notebook **people** into real Anima **character cards** (and optionally a **persona**), then start a chat already bound to that world — without hand-retyping everything.

**Why:** Owner feedback 2026-10-21 — “I attach a world to a chat, but what chat if I don’t have characters/persona yet?” **Pick card…** only links an *existing* card. Creation Center → world seed already exists (keep it). This phase is the **other direction**: world → cards → chat.

**Plain-English player flow:**

1. Settings → Living Worlds → open a notebook (sample / factory / import).
2. On a **person** row (People tab ⋮ or person editor): **Create character from this person…** and/or **Create persona from this person…**.
3. AI drafts a normal Anima character (or persona) from that person’s name + summary + personalityNotes + optional relationships/place hints — **review sheet before save** (same spirit as other AI card flows). Fallback: notebook fields only if AI fails.
4. After save: person gets `characterCardId` automatically when they confirm a character.
5. **Start chat with this character…** (solo) → persona pick → greeting pick → chat already bound to this `worldId`.
6. Bulk helper deferred (nice-to-have; not required for acceptance).

**Deliverables:**

- [x] **Create character from person** — `LivingWorldCardBridge` + `LivingWorldPersonCardActions` on person editor / people list. Uses Character & persona **build** model/settings. Review before apply. Sets `WorldPerson.characterCardId` on accept.
- [x] **Create persona from person** — same idea for player stand-in. Review before apply. Pick card… unchanged.
- [x] **Start chat bound to this world** — `ChatService.startNewChat(..., worldId:)` + persona/greeting pickers.
- [x] Keep **Seed from Creation Center…** unchanged (workshop → factory pitch only; one-way).
- [x] Keep **Pick card…** for linking cards that already exist.
- [x] Tests: `test/living_world_phase13_test.dart` (brief / seed / link / bind helper).
- [x] Living docs: this file, `AGENTS.md`, `PROJECT_REFERENCE.md` §15b, `README.md`, merge readiness.

**Acceptance:**

- Owner can: factory or sample world → create character from a person → start chat → world already attached → play. No manual retyping of the person’s blurb into the character editor.
- Unbound chats stay classic. No silent canon writes. Creation Center is still not the living engine.

**Out of scope for Phase 13:**

- Two-way sync that rewrites the notebook whenever the character card edits (link is enough; optional “pull card into person” later).
- Auto-creating the entire cast of 40 people in one unattended shot without review.
- Map / fortress UI.

**Shipped:** 2026-10-21 on `experiment/living-world` (build 79).

---

## Playtest checklist (owner — run after Phase 5 and again before merge)

1. Factory (or sample) → bind → play 20+ turns with **propose after turn**.  
2. Confirm a decision appears as event/flag and survives app restart.  
3. Large cast world: only relevant people appear in prompts (Context estimate / debug log).  
4. Auto-safe on: play without opening the editor; skim world log; revert once.  
5. Unbind Living World: chat feels like classic Anima.  
6. Backup/restore (after Phase 10) includes the notebook.

---

## Complexity is allowed — chaos is not

Agents **may** add substantial new services, schema versions, and pipelines to reach the end-goal. That is expected.

Agents **must not**:

- Replace Anima’s chat shell with a map/fortress client  
- Port Chronicle wholesale  
- Drop validation / review policy entirely  
- Simulate the whole planet every second  
- Bake dwarves/fantasy into types  
- Commit experimental breakage to `main` without owner merge  
- Pretend Creation Center workshop chat is the living engine  

If a design forks from this roadmap, **pause and ask Jakwan**.

---

## Suggested implementation order (cheat sheet)

| Order | Phase | One-line |
| --- | --- | --- |
| Done | **5–11** | Write loop → systems → ticks → continuity → backup/cards → invisible UX |
| Agent ✅ | **12** | Merge-readiness package (defaults + soak docs) — owner soak/merge still open |
| Done | **13** | World person → create character / persona + start chat already bound |
| **Now** | **12 soak** | Owner phone + Windows playtest → explicit “merge Living World” |

Phases 7–9 can overlap slightly **after** 5–6 are solid, but do not start ticks (8) before a reliable write loop (5).

---

## Document maintenance

When finishing a Living World phase:

1. Check boxes in **this file**  
2. Update **`AGENTS.md`** (status, what works, next actions, code map)  
3. Update **`PROJECT_REFERENCE.md` §15b** (mechanics)  
4. Update **`README.md`** if players see new UI/settings  
5. Keep **`LIVING_WORLD_HANDOFF_PROMPT.md`** as the philosophy brief; point newcomers here for **post–Phase-4 build order**

---

## Short paste for a new agent

> Living World Phases 1–11 + Phase 13 + Phase 12 **agent package** are on `experiment/living-world` (build 79+). **No further agent build phases** before merge — next is **owner soak** (phone + Windows) then explicit “merge Living World”. Skip Phase 12 soak/merge boxes (owner-only). End-goal: DF-lite under Anima chat. Keep Creation Center → **Seed from Creation Center…** as-is (one-way). Never silent unvalidated canon writes. Do not merge to `main` without owner approve.
