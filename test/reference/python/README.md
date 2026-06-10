# Python Reference Fixtures

Default Julia tests read committed fixtures from `fixtures/`; they do not call
Python or require `../dynesty`.

Regenerate fixtures from the read-only source checkout with:

```sh
PYTHONPATH=../dynesty/py python3 test/reference/python/generate_reference.py
```

The generator records:

- Python dynesty source path, branch, commit, and dirty status
- Python version
- NumPy version
- SciPy version
- fixture generation timestamp
- per-fixture tolerances and rationale

Current fixture files:

- `fixtures/utils_core.json`: foundational utilities and evidence integration.
- `fixtures/bounding_core.json`: UnitCube, Ellipsoid, MultiEllipsoid, and
  bounding helper cross-checks.
- `fixtures/friends_core.json`: RadFriends, SupFriends, and friends-radius
  helper cross-checks.
- `fixtures/results_postprocess.json`: deterministic results post-processing
  cross-checks for reweighting, unraveling, merging, static-result conversion,
  and live-point-count helpers.
- `fixtures/dynamic_core.json`: dynamic sampler state, weighting, batch-bound,
  and deterministic stopping-function cross-checks.

Current source snapshot:

- Source path: `/home/czc/projects/working/dynesty`
- Commit: `3ec158de0d2bf12a56230faacd0c987b3d55d550`
- Branch: `master`
- Dirty status at Stage 1 fixture creation: clean (`status_short` is empty)
- Python dynesty version: `2.1.2`
- Python version: `3.9.18`
- NumPy version: `1.21.5`
- SciPy version: `1.7.3`

Deterministic scalar/vector fixtures use `rtol=1e-10` and `atol=1e-12` unless a
stricter tolerance is recorded in the JSON.

Index-bearing fixtures record both Python 0-based values and Julia 1-based
values explicitly. Results post-processing fixtures also preserve Python's
public `information` field behavior separately from the internal `h` replacement
key used by several upstream helper functions.
