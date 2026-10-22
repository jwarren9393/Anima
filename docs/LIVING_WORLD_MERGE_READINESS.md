# Living World — Phase 12 merge readiness

> **Agent rule:** Prepare this package on `experiment/living-world`.  
> **Do not merge to `main`** until **Phase 13 is shipped** and Jakwan explicitly approves after soak.

This is the gate between the Living World experiment and daily-driver Anima.

---

## What “ready” means

| Bar | Passes when |
| --- | --- |
| **Phase 13** | World person → create character / persona + start chat already bound (see [`LIVING_WORLD_ROADMAP.md`](../LIVING_WORLD_ROADMAP.md) Phase 13). Owner blocker 2026-10-21. |
| **Opt-in** | New chats have no `worldId`. Policy default = Manual. Ticks Off. Resolve-before Off. Unbound chat = classic Anima. |
| **Tests** | `flutter analyze` clean + `flutter test` green on the experiment branch. |
| **Docs** | `AGENTS.md`, `PROJECT_REFERENCE.md` §15b, `README.md`, `LIVING_WORLD_ROADMAP.md` Phases 12–13, and this file agree. |
| **Soak** | Owner playtest on **phone and Windows** (multi-session) using [`LIVING_WORLD_PLAYTEST.md`](LIVING_WORLD_PLAYTEST.md) — include create-character-from-person once Phase 13 lands. |
| **Approve** | Owner says merge (exact words like “merge Living World” / “merge to main”). |

---

## Agent checklist

- [x] Phase 12 defaults verified + regression tests (`test/living_world_phase12_test.dart`)
- [x] Playtest checklist linked from living docs
- [x] Merge readiness doc (this file)
- [x] Living docs updated for Phase 12 package
- [x] **Phase 13** world → character / persona bridge — shipped 2026-10-21 (build 79)
- [ ] Owner soak (phone + Windows) — **owner**
- [ ] Owner explicit merge approve — **owner**

---

## Owner soak (phone + Windows)

Run on a build from `experiment/living-world` (debug/`flutter run`, or the `v1.0.0-living-world` prerelease APK/zip — not stable `v1.0.0` until merge).

### Session A — phone (Android)

1. Fresh or normal library. Confirm unbound chats look and feel like classic Anima (no World chips).
2. Settings → Living Worlds → sample harbor (or factory). Bind in a solo chat.
3. Play mode **Auto-apply safe updates**. Leave near-scene ticks **Off**.
4. Play **20+ turns** across **two app sessions** (force-close between).
5. Confirm: quiet **World updated** chip; **Review pending** for relationships; facts survive restart; **Undo last** once; unbind → classic again.
6. Create backup → restore on the same phone (or pull with `scripts/sync_phone_anima.sh`) and confirm `worlds/` returned.

### Session B — Windows

1. Same notebook via backup restore (or recreate sample).
2. Bound chat, auto-safe, **10+ turns**.
3. Worlds hub: Timeline… / Export JSON… / Undo last pack.
4. Group chat bind + one group-react; confirm pack + after-turn still sane.
5. Unbind; confirm no Living World chrome.

### Sign-off

| Device | Date | Notes | Pass? |
| --- | --- | --- | --- |
| Phone (Android) | | | |
| Windows | | | |
| Backup round-trip | | | |
| Unbind = classic | | | |

Owner merge approve: __________________ date: ________

Full evening checklist: [`LIVING_WORLD_PLAYTEST.md`](LIVING_WORLD_PLAYTEST.md).

---

## Merge steps (only after owner approve)

Agents must wait for an explicit merge request. Then:

1. On a clean tree: merge `experiment/living-world` → `main` (PR or local merge — follow owner’s preference).
2. Do **not** force-push. Do **not** overwrite stable `v1.0.0` until a normal `./deploy.sh` after merge.
3. After merge: living docs drop “experiment only / do not merge” language; Living World stays **opt-in** (unbound = classic).
4. Next deploy uses normal `v1.0.0` build bump — not the living-world prerelease tag.

---

## Do **not** merge if

- Silent / unvalidated canon corruption
- `flutter analyze` or `flutter test` red
- Unbound chat regresses (chips, after-turn API, pack injection without bind)
- Owner has not signed the soak table above
