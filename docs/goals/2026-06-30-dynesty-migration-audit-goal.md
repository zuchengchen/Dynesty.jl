# Goal: Dynesty.jl Migration Completeness Audit

## Goal Mode Objective

Follow this saved goal file at `2026-06-30-dynesty-migration-audit-goal.md`; audit whether the local read-only Python `../dynesty` functionality has been completely migrated into the Julia package, write the detailed audit report to `docs/migration_audit.md`, and complete only when the verification section has been attempted and the report contains a clear Yes/No/Conditional conclusion.

## Full Prompt

### Objective

Determine whether the current `Dynesty.jl` repository has fully migrated the functionality of the local read-only Python `../dynesty` snapshot according to `CODEX_GOAL_PROMPT.md`, and produce a detailed maintainer-facing Markdown audit report at `docs/migration_audit.md`.

The report must directly answer whether the migration can be declared complete with one of:

- `Yes`
- `No`
- `Conditional`

It must include detailed evidence, missing coverage, failed or unavailable verification, and a suggested repair order for any gaps.

### Context

Repository: `/home/czc/projects/working/Dynesty.jl`

Important local constraints:

- Follow `AGENTS.md`.
- Treat `../dynesty` as a read-only source reference.
- Do not modify, pull, checkout, clean, or otherwise change `../dynesty`.
- Keep `Manifest.toml` uncommitted.
- This task is an audit-only task.
- Do not implement missing functionality.
- Do not add tests, examples, or documentation except for the single audit report file.
- The only intended repository file change is `docs/migration_audit.md`.
- If `docs/migration_audit.md` already exists, stop and ask before overwriting or editing it.
- Temporary scripts, copied Python source, logs, and generated comparison outputs may be created only in temporary or scratch locations outside the intended final repository changes.

Primary migration contract:

- `CODEX_GOAL_PROMPT.md`
- `docs/migration_matrix.md`
- `docs/compatibility.md`
- `docs/source_snapshot.md`
- `test/reference/python/README.md`
- `test/reference/python/fixtures/`

Python baseline:

- Use only the local `../dynesty` checkout as the Python source baseline.
- Do not browse or compare against upstream latest dynesty.
- A temporary copy of `../dynesty` may be created outside the source tree to run Python tests or demos.
- If Python-side tests or demos fail because of environment, dependency, version, or runtime limitations, record that as environment-limited evidence and continue the audit. Do not treat environment failure alone as a migration failure.

### Brainstorming Direction

Use the approved audit-only approach.

The purpose is not to fix migration gaps but to establish a trustworthy answer to: "Has the Python version's functionality been completely migrated?"

The audit should prioritize evidence over declarations. `docs/migration_matrix.md` is useful input, but if it claims an item is implemented and source/test/docs evidence is insufficient, record that as an evidence gap.

### Discovery Summary

The user selected:

- Complete migration-contract scope.
- Deliver both a repository Markdown report and final conversational summary.
- Save the report to `docs/migration_audit.md`.
- Use a detailed maintainer/executor-oriented report.
- Compare Python source files, Python tests, Python docs, and Python demos/notebooks item by item.
- Attempt comprehensive verification, including Julia default tests, docs build, extended/slow/plot/distributed test modes, and Python temporary-copy probes.
- Do not set a fixed timeout; try to complete verification unless a command is clearly stuck or resource-limited.
- If Julia tests or docs build fail, the final audit conclusion cannot be `Yes`; it may be `Conditional` at best unless the user explicitly changes the standard.
- Classify gaps as `Blocking`, `Important`, or `Minor`.
- Include a recommended follow-up repair order.
- Stop only when continuing would violate constraints or required paths cannot be read.

Not applicable:

- Deployment, rollout, feature flags, production operations.
- Data migrations.
- Security/privacy changes beyond respecting file and source-readonly constraints.

### Scope

Inspect and compare, at minimum:

- `CODEX_GOAL_PROMPT.md`
- `AGENTS.md`
- `Project.toml`
- `README.md`
- `src/*.jl`
- `ext/*.jl`
- `test/*.jl`
- `test/reference/python/*`
- `docs/migration_matrix.md`
- `docs/compatibility.md`
- `docs/source_snapshot.md`
- `docs/src/**/*.md`
- `docs/*.md`
- `examples/*.jl`
- `benchmark/*` where relevant to migration-contract coverage
- local read-only Python files under `../dynesty/py/dynesty/*.py`
- local read-only Python tests under `../dynesty/tests/*.py`
- local read-only Python docs under `../dynesty/docs`
- local read-only Python demos/notebooks under `../dynesty/demos`

The audit report must include:

- Executive conclusion: `Yes`, `No`, or `Conditional`.
- Summary of evidence supporting the conclusion.
- Blocking, important, and minor gaps.
- A suggested fix order for gaps.
- A table mapping each Python core module/file to Julia implementation, tests, docs, and status.
- A table mapping each Python test file to Julia test or fixture coverage and status.
- A table mapping each Python docs page to Julia documentation coverage and status.
- A table mapping each Python demo/notebook to Julia example/docs coverage and status.
- A check of whether every Python symbol required by the migration contract is represented in `docs/migration_matrix.md`.
- A check of whether matrix rows marked implemented/replacement/internal are backed by source and test evidence.
- A check of public behavior differences against `docs/compatibility.md`.
- A check of persistence, parallelism, plotting, docs, examples, demos, notebooks, and benchmark/performance deliverables required by the migration contract.
- Verification commands attempted, with pass/fail/limited/skipped results.
- Environment limitations and their impact on the conclusion.
- Assumptions and unresolved unknowns.

### Out Of Scope

Do not:

- Modify `../dynesty`.
- Pull, checkout, switch branches, or clean `../dynesty`.
- Track upstream latest Python dynesty.
- Implement missing Julia functionality.
- Add or modify tests.
- Add or modify examples.
- Edit `docs/migration_matrix.md`, `docs/compatibility.md`, or other existing docs.
- Commit changes.
- Treat migration-matrix claims alone as sufficient evidence.
- Mark the goal complete if `docs/migration_audit.md` is missing, incomplete, or lacks a final Yes/No/Conditional judgment.

### Verification

Attempt these verification steps and record exact commands, outcomes, and limitations in `docs/migration_audit.md`.

Static audit:

- Enumerate Python modules, tests, docs pages, and demos from `../dynesty`.
- Enumerate Julia source, tests, docs, examples, fixtures, and migration-matrix rows.
- Compare Python symbols and behavior references against Julia implementations, tests, fixtures, docs, and compatibility notes.
- Confirm the only intended repository file change is `docs/migration_audit.md`.

Julia default test suite:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

Julia docs build:

```sh
julia --project=docs docs/make.jl
```

Extended Julia test attempts:

```sh
DYNESTY_RUN_SLOW_TESTS=true julia --project=. -e 'using Pkg; Pkg.test()'
DYNESTY_RUN_PLOT_TESTS=true julia --project=. -e 'using Pkg; Pkg.test()'
DYNESTY_RUN_EXTENDED_TESTS=true julia --project=. -e 'using Pkg; Pkg.test()'
DYNESTY_RUN_DISTRIBUTED_TESTS=true julia --project=. -e 'using Pkg; Pkg.test()'
```

If useful and feasible, also attempt combined extended flags and record the result:

```sh
DYNESTY_RUN_SLOW_TESTS=true DYNESTY_RUN_PLOT_TESTS=true DYNESTY_RUN_EXTENDED_TESTS=true DYNESTY_RUN_DISTRIBUTED_TESTS=true julia --project=. -e 'using Pkg; Pkg.test()'
```

Python temporary-copy probes:

- Copy `../dynesty` to a temporary directory.
- Run only from the temporary copy.
- Do not write into the original `../dynesty`.
- Attempt Python test/demo discovery or execution as useful for audit evidence.
- If Python environment dependencies are missing or incompatible, record the limitation and continue.

Completion evidence required:

- `docs/migration_audit.md` exists.
- Report contains a final Yes/No/Conditional conclusion.
- Report contains detailed per-file/per-test/per-doc/per-demo coverage tables.
- Report contains gap severity classification.
- Report contains recommended follow-up repair order.
- Report records verification commands and results.
- Report records any tests or probes that could not run and why.
- `git diff -- docs/migration_audit.md` shows the intended report.
- No repository files other than `docs/migration_audit.md` were intentionally modified.

### Stop Conditions

Stop and ask the user before continuing if:

- `docs/migration_audit.md` already exists and would need to be overwritten or edited.
- Any required path such as `../dynesty`, `CODEX_GOAL_PROMPT.md`, `src/`, `test/`, or `docs/migration_matrix.md` cannot be read.
- Completing the audit would require modifying `../dynesty`.
- Completing the audit would require modifying repository files other than `docs/migration_audit.md`.
- The user asks to change the scope from audit-only to implementation.
- Verification would require installing system-level dependencies, changing global environment state, or making network-dependent changes that are not already approved.

Do not stop merely because:

- A migration gap is found.
- A test fails.
- Python demo/test execution is environment-limited.
- Extended verification is slow.
- A matrix row has insufficient evidence.

Record those conditions in the audit report and continue.

## Notes

- Created for Codex Goal mode.
- Do not mark complete until the verification section passes or every failed/unavailable verification item is recorded and the final conclusion accounts for it.
