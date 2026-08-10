# Status Log

Append-only journal of working sessions. Newest entries on top. Each entry should answer three questions in 5–15 lines: **what was done**, **what's next**, **gotchas / open questions**.

Write a fresh entry at the end of every session, before stopping. Do not edit older entries — if something turned out wrong, note it in the next entry.

Rotation: keep roughly the last 10 sessions here; move older entries to `docs/archive/` every 20–30 sessions. V1's log lives in `docs/archive/STATUS-sessions-01-88.md` and `STATUS-sessions-89-98.md`.

---

## Session 99 (V2 Session 1) — 2026-08-10

**Done**
- **Phase 100 — repo seeded.** regula2 created by history-preserving `git clone` of regula (457 commits; branch point `7ef44db` tagged `v1-final`; `origin` remote removed so the repo is independent — `git blame`/`bisect` work across the V1/V2 boundary).
- The V2 assessment archived as `docs/V2-assessment.md` (it was untracked in regula).
- Docs reset for V2: old PLAN/STATUS/TODO rotated to `docs/archive/` (`PLAN-v1.md`, `STATUS-sessions-89-98.md`, `TODO-v1-final.md`); new `docs/PLAN.md` (projective-canonical/affine-as-view migration strategy, kernel-track table, M-CK/M-P/M-3D milestone outlines, risks, reuse contract) and `docs/TODO.md` (Phases 100–122 checklists). `CLAUDE.md` gained the V2 kernel invariants; `README.md` gained the V2 statement.
- Deferred decisions recorded in PLAN: package stays `regula` for now (174 `package:regula/` imports); no GitHub remote yet, CI workflows ride along until one is added.

**Next**
- Phase 101 (SPIKE 1): `Complex` type + benchmark harness — boxed vs `Float64List` SoA on VM/dart2js/dart2wasm; exit with the compile-target policy and the SoA API shape recorded here.

**Gotchas**
- Verification of the seeded tree passed: `flutter analyze` clean; 1587 tests + 26 goldens green; `flutter run -d web-server` serves HTTP 200; `git blame` on `construction.dart` traces to the original "Phase 2: Construction DAG" commit.
- `~/.config/git/ignore` has a global `cl-*` pattern — that's why the assessment was untracked in regula; it's archived here as `docs/V2-assessment.md` (no `cl-` prefix) to dodge it.
- Branch-ordering tests are load-bearing: the canonical-order compatibility rule in PLAN §Migration exists so they stay green until Phases 116–117 deliberately change dynamic behaviour. Don't "fix" them earlier.
