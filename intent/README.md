# Intents

One folder per change, following Anthropic's AI-native SDLC playbook: `intent.md` (what is asked for), then `spec.md` (what was decided), then `plan.md` (how it is built and proved, and how far it has got). The user accepts an intent before its spec is written, and approves a plan before code.

| # | Intent | Status | Depends on |
|---|---|---|---|
| 001 | [Docs follow the intent → spec → plan method](001-docs-method/intent.md) | done 2026-11-23; [spec](001-docs-method/spec.md), [plan](001-docs-method/plan.md) | — |
| 002 | [regula2 becomes regula again](002-fold-into-regula/intent.md) | draft, awaiting review | 001 |
| 003 | [Prover is experimental, off by default](003-prover-flag/intent.md) | draft, awaiting review | 002 (so it ships to the final URL) |
| 004 | [Stereometry](004-stereometry/intent.md) | draft, awaiting review | 001; after 003 |
| 005 | [CI is green again on Flutter stable](005-toolchain-3-50/intent.md) | part 1 done (workflows pinned to Flutter 3.47.2); part 2, the upgrade to Flutter 3.50 and `material_ui`, is next | — |

## Where the next session starts

**Intent 005, part 2, first** (the user's decision, 2026-11-23): the upgrade to Flutter 3.50 and the `material_ui` migration. Its intent is accepted; write `spec.md` and `plan.md`, get the plan approved, then do it. Start by trying the migration, since whether `find.byTooltip` still matches is what sizes the work.

Then 002, 003, 004 in order: the user reviews each intent, then spec and plan, then code.

## Parked

Open items from the old checklist that are not intents yet. Each becomes an intent when its trigger fires, and not before.

| Item | Trigger |
|---|---|
| Android emulator smoke; iOS simulator smoke and `flutter build ios` | Intent 004's first milestone, which requires a phone. Needs an AVD with a system image, and a complete Xcode install with CocoaPods |
| The Newclid comparison (old Phase 176) | Newclid ships past 3.0.1, or fixes either crash class (`LengthEquationPredicate is not implemented`; the pydantic error on degenerate `simtri`). Check with `pip index versions newclid` |
| Prover carries (old Phase 186): `readFact` on a listed `eqangle` can read magnitude-false; the re-glance on old `entails`-based zeros; `regular_hexagon#2`'s quiescence asterisk | The prover comes back out from behind intent 003's flag |
| The proof sheet looked at on a narrow window (old Phase 154) | Folded into intent 003's proof. Take Chrome out of macOS fullscreen before resizing |

Dropped: hand-written SVG export (a stretch item since V1 Phase 19).

The full text of each item is in `docs/archive/TODO-final.md`.
