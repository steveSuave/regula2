"""Repair Newclid 3.0.1 enough to run its own corpus (Phase 175).

The three fixes below are unambiguous bugs — in each case the type
declaration and every sibling call site agree, and one line disagrees
with them. They are applied to an **installed copy inside a venv**,
never to a source checkout, so the upstream repository stays clean.

Idempotent: reports each fix as applied, already-present, or NOT FOUND.
A NOT FOUND on a fresh install means the line moved or upstream fixed
it — check the version before assuming the patch is still needed.

    python3 benchmark/comparator/patch_newclid.py ~/Code/var/Newclid/.venv

Two further crash classes are deliberately NOT patched, because fixing
them means writing new reasoning rather than correcting a typo:

  * NotImplementedError: LengthEquationPredicate is not implemented
    — its AR deductor emits a predicate its own handler lacks.
  * pydantic ValidationError on `simtri c b d c b d` — its matcher
    generates a degenerate triangle pair its own validator rejects.

Those two are what cap the comparator at a verdict on ~11% of the
corpus. **Before re-running the comparison, check whether upstream has
fixed them** (`pip index versions newclid`, or the Newclid repo); if a
release past 3.0.1 exists, try it unpatched first.
"""

import sys
from pathlib import Path

FIXES = [
    (
        "deductors/sympy_ar/ar_predicates.py",
        "for segment, expected_length_value in table.expected_lconsts.copy():",
        "for segment, expected_length_value in "
        "table.expected_lconsts.copy().items():",
        "expected_lconsts is a dict[SympySymbol, float], read with "
        ".items() everywhere else; a # pyright: ignore hid this one",
    ),
    (
        "predicates/__init__.py",
        "            a, b = points_registry.names2points(canonical_args)\n"
        "            return Diff(points=(a, b))",
        "            return Diff("
        "points=points_registry.names2points(canonical_args))",
        "Diff.points is already tuple[Point, ...] with a pairwise check "
        "and a >2 branch in __str__; rules R34-R37 pass `diff A B C`",
    ),
    (
        "rule_matching/mapping_matcher.py",
        "            conclusion_args = tuple("
        "mapping[arg] for arg in conclusion.variables)",
        "            conclusion_args = tuple(\n"
        "                mapping.get(arg, arg) for arg in "
        "conclusion.variables\n            )",
        "a conclusion's 'variables' include literals such as R51's 1/2, "
        "which are not variables to bind",
    ),
]


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    venv = Path(sys.argv[1]).expanduser()
    roots = sorted(venv.glob("lib/python3.*/site-packages/newclid"))
    if not roots:
        print(f"no newclid installed under {venv}")
        return 2
    root = roots[0]
    failures = 0
    for relative, old, new, why in FIXES:
        path = root / relative
        text = path.read_text()
        if new in text:
            print(f"  already patched  {relative}")
        elif old in text:
            path.write_text(text.replace(old, new, 1))
            print(f"  patched          {relative}  ({why})")
        else:
            print(f"  NOT FOUND        {relative}  — check the version")
            failures += 1
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
