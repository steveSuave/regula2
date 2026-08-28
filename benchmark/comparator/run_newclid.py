"""Phase 175: Newclid over the corpus, as the comparator regula2 lacks.

One goal per problem, matching regula2's parser (several goals after one
`?` are several problems), so the proved sets are comparable goal by
goal. Auxiliary sections are not built, matching both defaults.

Each problem runs in a forked child with a hard timeout: Newclid blocks
in C for long stretches, so SIGALRM in-process does not bite (one
problem overran a 60 s alarm by 280 s). The fork inherits the imports,
so a restart is free.

Results stream to the output file, so a kill keeps what has run.
"""
import json
import multiprocessing as mp
import os
import sys
import time
from pathlib import Path

import numpy as np

from newclid.api import GeometricSolverBuilder
from newclid.jgex.formulation import JGEXFormulation
from newclid.jgex.problem_builder import JGEXProblemBuilder

CORPUS = Path(sys.argv[1])
OUT = Path(sys.argv[2])
ONLY_FILE = Path(sys.argv[3]) if len(sys.argv) > 3 else None
TIMEOUT = int(os.environ.get("NC_TIMEOUT", "60"))

wanted = None
if ONLY_FILE is not None:
    wanted = {
        ln.strip() for ln in ONLY_FILE.read_text().splitlines() if ln.strip()
    }


def _solve(text, q):
    try:
        problem = JGEXFormulation.from_text(text)
        rng = np.random.default_rng(998244353)
        setup = JGEXProblemBuilder(rng=rng, problem=problem).build()
        solver = GeometricSolverBuilder(rng).build(setup)
        q.put("proved" if solver.run() else "unproved")
    except BaseException as exc:  # noqa: BLE001
        q.put(f"error:{type(exc).__name__}")


def solve(text):
    ctx = mp.get_context("fork")
    q = ctx.Queue()
    child = ctx.Process(target=_solve, args=(text, q))
    child.start()
    child.join(TIMEOUT)
    if child.is_alive():
        child.terminate()
        child.join(5)
        if child.is_alive():
            child.kill()
        return "timeout"
    try:
        return q.get_nowait()
    except Exception:  # noqa: BLE001
        return "crash"


rows = []
files = sorted(p for p in CORPUS.iterdir() if p.suffix == ".txt")
for path in files:
    lines = [ln.rstrip("\n") for ln in path.read_text().splitlines()]
    i = 0
    while i + 1 < len(lines):
        name, body = lines[i].strip(), lines[i + 1].strip()
        i += 2
        if not name or not body or "?" not in body:
            continue
        head, goals_str = body.split("?", 1)
        goals = [g for g in goals_str.strip().split(";") if g.strip()]
        for gi, goal in enumerate(goals):
            label = name if len(goals) == 1 else f"{name}#{gi + 1}"
            key = f"{path.name}:{label}"
            if wanted is not None and key not in wanted:
                continue
            started = time.time()
            verdict = solve(f"{label}\n{head.strip()} ? {goal.strip()}")
            rows.append(
                {
                    "key": key,
                    "goal": goal.strip().split()[0],
                    "verdict": verdict,
                    "ms": int((time.time() - started) * 1000),
                }
            )
            print(f"{key} {verdict} ({rows[-1]['ms']} ms)", flush=True)
            OUT.write_text(json.dumps(rows, indent=1))

tally = {}
for r in rows:
    k = r["verdict"].split(":")[0]
    tally[k] = tally.get(k, 0) + 1
print("")
print(f"{len(rows)} goals")
for k, v in sorted(tally.items(), key=lambda kv: -kv[1]):
    print(f"  {k:<10} {v}")
