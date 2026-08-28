# The Newclid comparator (Phase 175)

`docs/PLAN.md` ends Phase 174 with the one measurement that separates
the three surviving explanations for the corpus's 379 quiescent-unproved
goals: **run the reference implementation over the same corpus and diff
the proved sets.** This is the harness for that.

## Setup

Newclid's dependencies are not installed in the checkout, and its
`pyproject.toml` needs Python ≥ 3.11 while this machine's default is
3.14 — too new for the `scipy` / `symengine` / `matplotlib` wheels it
pins. So:

```sh
cd ~/Code/var/Newclid
/opt/homebrew/bin/python3.12 -m venv .venv     # .venv/ is already gitignored there
.venv/bin/pip install ./newclid
```

## Running

`run_newclid.py` takes the corpus directory, an output JSON path, and
optionally a file of `source:name` keys to restrict to — the natural
one being regula2's own built set, which
`dart run benchmark/corpus_bench.dart --verbose` prints (its verbose
lines are source-qualified for exactly this reason).

```sh
dart run benchmark/corpus_bench.dart --verbose > regula.log
grep -oE "^  (proved|unproved|undecided|refuted) +\S+" regula.log \
  | awk '{print $2}' > built_keys.txt
cd ~/Code/var/Newclid && NC_TIMEOUT=30 .venv/bin/python \
  <this dir>/run_newclid.py newclid/problems_datasets out.json built_keys.txt
```

Two decisions in the harness are worth knowing. It splits multi-goal
lines **one goal per problem**, matching regula2's parser, so the two
proved sets are comparable goal by goal. And each problem runs in a
**forked child with a hard timeout**, because Newclid blocks in C for
long stretches and an in-process `SIGALRM` does not bite — one problem
overran a 60 s alarm by 280 s before this was changed.

## The three patches, and why they are not cheating

Newclid 3.0.1 (the latest release, and the checkout's own version)
crashes on a large share of its own corpus. Three of the crashes are
unambiguous bugs with the fix the authors plainly intended, and they are
applied **to the venv's installed copy, never to the checkout**, so that
repository stays clean:

| file | was | is | why it is unambiguous |
|---|---|---|---|
| `deductors/sympy_ar/ar_predicates.py` | `for segment, value in table.expected_lconsts.copy():` | `….copy().items():` | `expected_lconsts` is declared `dict[SympySymbol, float]` and read with `.items()` everywhere else; a `# pyright: ignore` hid it |
| `predicates/__init__.py` | `a, b = names2points(args); Diff(points=(a, b))` | `Diff(points=names2points(args))` | `Diff.points` is already `tuple[Point, ...]`, its check is already pairwise, and its `__str__` already branches on >2 — only this constructor site hardcoded a pair, and their own rules R34–R37 pass `diff A B C` |
| `rule_matching/mapping_matcher.py` | `mapping[arg] for arg in conclusion.variables` | `mapping.get(arg, arg) …` | a conclusion's "variables" include literals like R51's `1/2`, which are not variables to bind |

**Two further crash classes are not one-liners and are left alone**:
`NotImplementedError: LengthEquationPredicate is not implemented`, from
its own AR deductor producing a predicate its own handler lacks, and a
pydantic `ValidationError` from its matcher generating a degenerate
`simtri c b d c b d` its own validator rejects. Repairing those would
mean rewriting the reference implementation's reasoning, at which point
it stops being the reference.

**So read any comparison off this with its bias stated.** A problem that
crashes is excluded, and the crashes are concentrated in AR and in
similarity matching — the harder machinery — so the surviving subset is
biased *toward problems Newclid finds easy*. A result of the form "the
reference proves few of ours" is therefore conservative and safe; one of
the form "it proves many" is inflated and is not evidence on its own.
