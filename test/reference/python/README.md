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
