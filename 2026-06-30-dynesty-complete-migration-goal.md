# Goal: Complete Dynesty.jl Migration Closure

## Goal Mode Objective

Follow this saved goal file at `2026-06-30-dynesty-complete-migration-goal.md`; close every blocking and important migration gap identified in `docs/migration_audit.md`, verify the completed migration against the local read-only `../dynesty` snapshot, write `docs/migration_completion_audit.md` with a final `Yes` conclusion or explicitly justified non-migration exceptions, and commit all related changes while keeping `Manifest.toml` uncommitted.

## Full Prompt

### Objective

Complete the Dynesty.jl migration closure work identified by `docs/migration_audit.md` so that the repository can be re-audited as fully migrated against the local read-only Python `../dynesty` snapshot.

The task is complete only when:

- All blocking and important gaps from `docs/migration_audit.md` are closed by implementation, examples, tests, documentation, dependency/test-environment setup, or explicitly justified non-migration exceptions.
- The completion audit at `docs/migration_completion_audit.md` gives a final `Yes` conclusion, unless a live Python verification failure is conclusively documented as unrelated to the Julia migration and explicitly waived in that report.
- Required Julia, docs, extended, distributed, plot, slow, and Python live verification commands have been run and recorded.
- A git commit containing all relevant migration-closure changes has been created.
- `Manifest.toml` and generated manifests remain uncommitted.

### Context

Repository: `/home/czc/projects/working/Dynesty.jl`

Primary inputs:

- `CODEX_GOAL_PROMPT.md`
- `AGENTS.md`
- `docs/migration_audit.md`
- `docs/migration_matrix.md`
- `docs/compatibility.md`
- `docs/source_snapshot.md`
- `test/reference/python/README.md`
- `test/reference/python/fixtures/`
- local read-only Python baseline at `../dynesty`

Important current state from the prior audit:

- `docs/migration_audit.md` concluded `No`.
- Core sampler/source migration appears strong.
- Remaining blocking/important gaps are mainly docs/demo/notebook parity, targeted regression evidence, HDF5 extended verification, docs build reproducibility, test flag behavior, and migration matrix granularity.
- Existing untracked prior artifacts are part of the intended commit scope:
  - `2026-06-30-dynesty-migration-audit-goal.md`
  - `docs/migration_audit.md`

Hard constraints:

- Treat `../dynesty` as read-only. Do not modify it, pull it, switch branches, clean it, or write cache/build outputs into it.
- Keep `Manifest.toml` uncommitted. Do not commit root, docs, benchmark, or temporary manifests.
- Preserve existing Julia-native public API design where possible.
- Avoid breaking existing public APIs. Prefer adding examples, docs, tests, compatibility aliases, or narrowly scoped implementation fixes.
- Keep HDF5.jl as a weak dependency/extension; do not make it a core dependency.
- Do not add Plots.jl or Makie as a core dependency.
- Use a separate temporary Python environment for live Python verification; do not pollute the user's current Python environment.
- Network access is allowed only for installing packages into that isolated temporary Python environment or temporary docs/test environments needed for verification.
- If any file targeted for creation already exists unexpectedly, stop and ask before overwriting.

### Brainstorming Direction

Use the approved full-closure approach.

Close every blocking and important audit gap in one coherent migration-closure pass:

1. Add or document Julia coverage for missing Python demo/notebook topics with runnable `.jl` examples, docs entries, and default smoke tests.
2. Add documentation for FAQ, references/acknowledgements, changelog/source-version context, and Python 3.0 feature-overview equivalents in Julia terms.
3. Add targeted tests/fixtures for high-value Python behavior references that lacked evidence.
4. Make HDF5 extended verification actually exercise the extension while preserving weak-dependency semantics.
5. Make docs build verification reproducible by instantiating docs environment before build.
6. Implement real `DYNESTY_RUN_SLOW_TESTS` and `DYNESTY_RUN_PLOT_TESTS` test paths.
7. Expand `docs/migration_matrix.md` to method-level tracking or add a complete method-level appendix that satisfies "one row per Python symbol".
8. Re-run the audit and write `docs/migration_completion_audit.md`.
9. Commit all relevant migration-closure changes, including prior audit artifacts and goal files, excluding manifests.

### Discovery Summary

User decisions:

- Full closure, not only blocking-only or staged closure.
- Necessary source changes are allowed.
- Final completion standard is a re-auditable `Yes`.
- Migration matrix must be expanded to method-level tracking or an equivalent complete method-level appendix.
- Python demos/notebooks should be covered by Julia `.jl` examples, documentation, and smoke tests, not Julia notebooks.
- Missing demo topics should be covered one-to-one where practical:
  - Exponential Wave
  - Hyper-Pyramid
  - Linear Regression
  - LogGamma
  - Noisy Likelihoods
  - Importance Reweighting
  - 25-D Correlated Normal
  - Python 3.0 feature overview via a Julia-native feature overview
- HDF5 remains weak dependency but extended verification must actually run HDF5 path.
- Docs build verification should instantiate docs environment first.
- `DYNESTY_RUN_SLOW_TESTS` and `DYNESTY_RUN_PLOT_TESTS` should have actual test paths.
- Python live verification should use an isolated temporary virtualenv or conda env, may use network, and must run Python pytest/notebook verification from a temporary copy of `../dynesty`.
- Python live failure blocks `Yes` unless the completion audit proves it is unrelated to Julia migration and explicitly waives it.
- Python live verification is a final Goal verification command, not part of Julia `Pkg.test()`.
- New Julia examples should enter default `test/test_examples.jl` smoke tests and have lightweight defaults.
- All newly added Julia tests should be part of default `Pkg.test()`, while slow/plot flags still need meaningful additional paths.
- A new completion audit should be written to `docs/migration_completion_audit.md`; keep `docs/migration_audit.md` as historical `No`.
- Save this Goal file at `2026-06-30-dynesty-complete-migration-goal.md`.
- Move the previous audit Goal file to `docs/goals/2026-06-30-dynesty-migration-audit-goal.md`.
- Automatically commit all relevant changes after verification passes, including prior related files and this Goal file.
- Public API changes should be avoided unless needed by the migration contract.

### Scope

In scope:

- `src/*.jl` and `ext/*.jl` if needed to close real functionality gaps.
- `test/*.jl` and `test/reference/python/*` for coverage and fixtures.
- `docs/*.md`, `docs/src/**/*.md`, `docs/migration_matrix.md`, `docs/compatibility.md`, and new docs pages.
- `docs/migration_completion_audit.md`.
- `examples/*.jl` for missing Python notebook/demo topics.
- `docs/Project.toml`, `Project.toml`, and test/docs dependency configuration if needed, while keeping HDF5 weak and avoiding Plots/Makie as core dependencies.
- `.gitignore` or CI/workflow files if needed to keep manifests/generated outputs uncommitted or to make verification reproducible.
- Move `2026-06-30-dynesty-migration-audit-goal.md` to `docs/goals/2026-06-30-dynesty-migration-audit-goal.md`.
- Create this saved Goal file at `2026-06-30-dynesty-complete-migration-goal.md`.
- Temporary Python virtualenv/conda env and temporary copy of `../dynesty` outside the repository for live Python verification.
- A final git commit containing all related changes.

Required closure targets from `docs/migration_audit.md`:

- B1: Python demos/notebooks not fully covered by Julia examples/docs.
- B2: FAQ and references/changelog docs not fully represented.
- B3: Python slow/regression behavior references not fully evidenced.
- I1: docs build command failed as written.
- I2: HDF5 evaluation-history extended verification skipped.
- I3: Python pytest probe environment-limited.
- I4: migration matrix method granularity gap.
- I5: documented slow/plot flags not consumed by tests.

Outcomes expected in code/docs/tests:

- Add `.jl` examples with fast default `main()` paths and docs table entries for every missing Python notebook topic.
- Update `test/test_examples.jl` so all new examples are smoke-tested by default.
- Add tests/fixtures for Rosenbrock/pathology/dynamic batch/large-logl/HDF5 history or document exact equivalent existing coverage.
- Add meaningful slow and plot test paths gated by `DYNESTY_RUN_SLOW_TESTS` and `DYNESTY_RUN_PLOT_TESTS`.
- Ensure `DYNESTY_RUN_EXTENDED_TESTS=true` can actually exercise HDF5 extension when dependencies are instantiated.
- Update docs/testing and README verification commands to instantiate docs env before docs build.
- Add or update docs for FAQ, references, changelog/source snapshot, feature overview, and notebook coverage mapping.
- Expand migration matrix or add a method-level appendix for Python class methods.
- Update compatibility docs for any new intentional differences or clarified replacements.
- Write `docs/migration_completion_audit.md` with final `Yes`, detailed evidence, or explicit non-migration waivers.

### Out Of Scope

Do not:

- Modify `../dynesty`.
- Pull, checkout, switch branches, or clean `../dynesty`.
- Commit any `Manifest.toml`.
- Make HDF5 a core dependency.
- Add Plots.jl or Makie as a core dependency.
- Replace Julia-native APIs with Python-shaped APIs unless explicitly required for compatibility.
- Delete `docs/migration_audit.md` or rewrite its historical `No` conclusion.
- Treat a green default test run alone as enough for completion.
- Mark complete without a git commit.
- Leave completion audit at `No` or unresolved `Conditional`.

### Verification

Run and record results in `docs/migration_completion_audit.md`.

Repository hygiene:

```sh
git status --short
git -C ../dynesty status --short
git ls-files --others --exclude-standard
```

Julia default tests:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

Docs build with instantiated docs environment:

```sh
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs docs/make.jl
```

Extended Julia tests:

```sh
DYNESTY_RUN_SLOW_TESTS=true julia --project=. -e 'using Pkg; Pkg.test()'
DYNESTY_RUN_PLOT_TESTS=true julia --project=. -e 'using Pkg; Pkg.test()'
DYNESTY_RUN_EXTENDED_TESTS=true julia --project=. -e 'using Pkg; Pkg.test()'
DYNESTY_RUN_DISTRIBUTED_TESTS=true julia --project=. -e 'using Pkg; Pkg.test()'
DYNESTY_RUN_SLOW_TESTS=true DYNESTY_RUN_PLOT_TESTS=true DYNESTY_RUN_EXTENDED_TESTS=true DYNESTY_RUN_DISTRIBUTED_TESTS=true julia --project=. -e 'using Pkg; Pkg.test()'
```

HDF5 verification requirement:

- `DYNESTY_RUN_EXTENDED_TESTS=true` must actually run HDF5 evaluation-history checks, not merely log a skip due to missing HDF5.jl.
- If this requires a temporary test environment or extras setup, document it and ensure the committed project configuration supports reproducing it without committing manifests.

Python live verification:

- Create an isolated temporary Python virtualenv or conda environment outside the repository.
- Install required dependencies into that temporary environment, using network if needed.
- Copy `../dynesty` to a temporary directory outside the repository.
- Run Python pytest collection and tests from the temporary copy.
- Run or verify execution of Python notebooks/demos from the temporary copy.
- Do not write into original `../dynesty`.
- Record exact commands, dependency versions, pass/fail counts, and any explicitly waived non-migration failures in `docs/migration_completion_audit.md`.

Completion audit:

- `docs/migration_completion_audit.md` must include:
  - Final judgment `Yes`.
  - Before/after closure table for B1-B3 and I1-I5.
  - Python module, test, docs, demo/notebook, and symbol/method coverage tables.
  - Verification command results.
  - Confirmation that `../dynesty` remained unmodified.
  - Confirmation that no `Manifest.toml` was committed.
  - Commit hash of the final migration-closure commit.

Git commit:

```sh
git status --short
git add <all relevant files except Manifest.toml and generated outputs>
git status --short
git commit -m "Complete Dynesty migration closure"
git status --short
```

Before committing, inspect staged files and ensure the commit includes all related migration closure artifacts and excludes manifests/generated temporary outputs.

### Stop Conditions

Stop and ask the user before continuing if:

- Any target file to create already exists unexpectedly and would need overwrite.
- Continuing requires modifying `../dynesty`.
- Python live verification requires changing the user's global/current Python environment instead of an isolated temporary environment.
- Dependency installation requires system-level changes or privileged operations.
- A public API break seems necessary.
- Verification repeatedly fails because of an external service, package registry, network, or environment problem that cannot be isolated or reasonably waived.
- Achieving `Yes` appears impossible without changing the user-approved completion standard.
- Git commit would include `Manifest.toml`, generated output, large binary artifacts, or unrelated user changes.

Do not stop merely because:

- A missing example/test/doc is found.
- A Julia test fails initially.
- Python live pytest/notebook fails due to a fixable missing dependency in the temporary environment.
- Existing coverage is better handled by documentation than duplicate implementation.
- The work is long or touches many files.

Fix, document, and verify within the approved scope.

## Notes

- Created for Codex Goal mode.
- Do not mark complete until verification passes, `docs/migration_completion_audit.md` reaches `Yes`, and the final git commit exists.
