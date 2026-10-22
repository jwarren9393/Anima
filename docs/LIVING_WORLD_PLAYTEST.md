# Living World — owner playtest checklist

Run this after each major Living World phase, and again before merge to `main` (Phase 12).

**Phase 12 soak (phone + Windows + sign-off):** see [`LIVING_WORLD_MERGE_READINESS.md`](LIVING_WORLD_MERGE_READINESS.md). Use this checklist for the evening play; use the merge doc for multi-device soak and the merge gate.

**Goal:** Play an evening with **Auto-apply safe updates** on and only glance at the world timeline — the engine should feel present, not naggy.

---

## Setup (once)

1. Open Anima on the `experiment/living-world` build (or after merge, daily driver).
2. Settings → **Living Worlds** → create **sample harbor** or run **World factory**.
3. On a person (People tab ⋮ or person editor) → **Create character from this person…** (review → save) → **Start chat** so the world is already attached. (Or **Pick card…** to link an existing character, then **Start chat**.)
4. Set play mode to **Auto-apply safe updates** (hub or chat ⋮ → World play mode…).
5. Leave **Near-scene ticks** Off unless you want ambient beats.

---

## Evening with auto-safe (Phase 11 bar)

1. Play **20+ turns** without opening the notebook editor.
2. When safe facts land, confirm a quiet **World updated · N** chip (not a modal every turn).
3. When relationships are proposed, confirm they wait on **Review pending (N)** — one tap opens the review sheet.
4. Tap **World updated** → World timeline shows applied packs (newest first).
5. Chat ⋮ → **Undo last world update** once; confirm the notebook rolled back.
6. Settings → Living Worlds → world ⋮ → **Timeline…** / **Export JSON…** / **Undo last pack**.

---

## Canon survival

1. Make a clear decision in chat (e.g. a promise, a place change, a flag-worthy fact).
2. Confirm it appears as an event/flag/continuity item (Context estimate / World timeline / editor Canon tab).
3. Force-close the app and reopen — the fact is still on disk.

---

## Cast scale

1. Use a larger notebook (~20–50 people) or factory output.
2. Chat ⋮ → **Context estimate** — Living World pack is present but not the whole cast.
3. Group chat: linked speaker + open threads still pin through.

---

## Classic Anima fallback

1. ⋮ → Living World → turn off / unbind.
2. Chat feels like normal Anima (no chips, no after-turn world work).

---

## Backup

1. Settings → Backup → Create backup.
2. Confirm restore brings back `worlds/` notebooks (and log/undo/pending side cars under that folder).

---

## Sign-off

| Check | Date | Notes |
| --- | --- | --- |
| Auto-safe evening (no nagging modals) | | |
| Pending review one-tap works | | |
| Undo last pack (chat + hub) | | |
| Facts survive restart | | |
| Unbind = classic Anima | | |
| Backup includes worlds | | |

Owner sign-off before Phase 12 merge: __________________ date: ________

Also complete the device table in [`LIVING_WORLD_MERGE_READINESS.md`](LIVING_WORLD_MERGE_READINESS.md) (phone + Windows) before saying “merge to main.”
