# Dynesty.jl Python Feature Gap Completion Goal Prompt

Copy the text below into Codex Goal mode from
`/home/czc/projects/working/dynesty.jl`.

```text
在 `/home/czc/projects/working/dynesty.jl` 中继续推进 Dynesty.jl 迁移收尾工作：以当前只读 Python 源项目 `../dynesty` 为准，全面审计 Python dynesty 的源码、测试、文档、demos/notebooks、benchmark/CI 期望和用户工作流，找出当前 Julia 版本还缺少的能力、行为、测试、示例和文档覆盖，并全部补齐。

本目标已经经过用户确认，不要在已确认策略上重复提问。你需要先审计，再按已确认方案持续执行。只有遇到本提示词明确列出的新的重大阻塞时才停下来询问用户。

## 已确认总方案

- 范围：全面审计 + 全部补齐。
- 补齐标准：能力级全部补齐，不机械复制 Python 表面 API。
- API 方针：严格纯 Julia-native。现有 Python-compatible alias 也要硬移除。
- 契约方针：允许并要求修改 `CODEX_GOAL_PROMPT.md`，把总迁移契约更新为纯 Julia-native。
- 执行节奏：Stage 0 完成审计并生成审计文档后继续执行，不再等待用户再次批准；只有遇到新的重大阻塞才问用户。
- 依赖方针：允许自行新增成熟、维护良好、适合 Julia 生态的依赖，但必须说明原因、分类、影响并更新相应 `Project.toml`。仍然不要提交 `Manifest.toml`。
- 测试方针：每个阶段都必须运行完整验证，包括 full `Pkg.test()`、docs build、format/Aqua、完整 benchmark suite、`git diff --check`。
- benchmark 方针：Stage 0 先定义完整 benchmark suite 清单，之后每个阶段都严格按清单运行。
- 工作区方针：最终 `git status --short` 必须为空。允许处理所有当前仓库内文件，包括目标开始前已有的未跟踪文件：相关的提交，无关/过期/临时/输出/缓存的删除。处理情况必须记录。
- Git 方针：如果当前分支是 `main` 或 `master`，新建工作分支；否则沿用当前分支。只本地 commit，不 push。
- 最终回复语言：中文，简洁列出分支、commits、主要完成项、验证命令、清理/删除文件、剩余风险。

## 必须遵守

- 阅读并遵守 `AGENTS.md`。
- 阅读现有 `CODEX_GOAL_PROMPT.md`，但本目标要求先把其中与 Python-compatible alias 冲突的旧条款改写为纯 Julia-native 契约。
- Treat `../dynesty` as a read-only source reference. Do not modify it, do not pull it, and do not switch its branch.
- 以当前 `../dynesty` checkout 为审计准绳。
- 不要使用 `sudo`，不要使用系统包管理器，不要修改系统目录。
- 可以使用用户级工具、项目内 Python virtual environment、项目内 Julia/Python 依赖配置来让测试、docs 和 benchmark 通过；不要提交 venv、cache 或临时安装产物。
- 不要提交 `Manifest.toml`、`docs/build/`、benchmark output directories、`__pycache__/`、临时日志或无关缓存。
- 当前 Julia 仓库里的 Python helper/fixture/benchmark 脚本可以修改；`../dynesty` 不能修改。
- 搜索文件/文本优先使用 `rg`；手工编辑文件使用 `apply_patch`。
- 不使用 destructive git 命令去重置用户历史。允许删除当前仓库内被审计为无关、过期、临时、输出或缓存的未跟踪/已生成文件，以达成最终 clean worktree；删除清单必须记录。
- 每个阶段通过完整验证后自动 commit。每个 commit 只包含该阶段相关变更或被明确清理/归档的文件处理。

## 新迁移契约：纯 Julia-Native API

本目标要把 Dynesty.jl 从“带 Python alias 的迁移兼容 API”清理为“严格 Julia-native API”。Python dynesty 仍是算法、行为、测试、文档工作流和能力覆盖的基准，但不是 Julia public API 形状的基准。

必须在 `CODEX_GOAL_PROMPT.md` 中直接重写相关条款，不保留旧 alias 方针。历史变化记录放在 `CHANGELOG.md`、`docs/feature_gap_audit.md`、`docs/migration_guide.md`、`docs/compatibility.md` 和 Documenter 对应页面中。

具体 API 规则：

1. Mutating API 只保留 bang 形式。
   - 例如保留 `run_nested!`、`checkpoint!`、`add_live_points!`、`combine_runs!`。
   - 删除无 bang 的 mutating alias，例如仅调用 `run_nested!` 的 `run_nested`。
2. Enum-like public options 只接受 `Symbol` 或专门类型，不接受 string。
   - `bound=:multi` 可以，`bound="multi"` 不可以。
   - `sample=:rwalk` 可以，`sample="rwalk"` 不可以。
   - `proposal_scheduler=:batch` 可以，`"batch"` 不可以。
   - 字符串仍可用于真实文本、文件路径、plot label、标题、dataset name 和 free-form metadata。
3. 随机数关键词只用 `rng`。
   - `rng` 可接受 Julia `AbstractRNG` 或 integer seed。
   - 不支持 `rstate` / `random_state` alias。
   - 文档说明 Julia RNG 和 Python NumPy RNG 不保证 same-seed sample-by-sample 一致。
4. Results public schema 只保留 Julia-native 字段名。
   - 保留 `blobs`，删除 `blob` alias。
   - 删除 `samples_bound`、`batch` 等仅为 Python schema/fixture 方便而存在的 public aliases。
   - Python fixture schema 转换只能放在测试 helper / fixture reader 中，不能污染 public API。
5. 索引只使用 Julia 1-based。
   - 不接受 Python 0-based 输入。
   - 如果曾有 public `from_python_indices` 等迁移辅助，要从 public API 移除；确需保留只能是非导出测试/文档内部 helper。
6. 用户函数参数使用 closures 或 callable objects。
   - 不支持 `logl_args`、`logl_kwargs`、`ptform_args`、`ptform_kwargs` 等 Python 包装模式。
   - migration guide 要给出 Python 写法改为 Julia closure/callable object 的示例。
7. 并行 API 使用 Julia-native backend/config。
   - 删除 `use_pool`。
   - 删除或重命名 `PoolUsage`，改用 Julia-native `ParallelPolicy`。
   - `ParallelPolicy` 控制 sampler 各阶段并行策略，例如 initialization、proposals、bounds、stopping 等，字段名按 Julia 语义设计，不沿用 Python key 名。
   - 保留/整理 `SerialMapBackend`、`ThreadedMapBackend`、`DistributedMapBackend` 等 Julia-native backend。
8. 错误行为按 Julia 习惯。
   - 不复制 Python exception class 或完整 message。
   - 覆盖同等错误场景，public validation 测试检查合理 exception type 和关键诊断关键词。
9. 文档只教 Julia-native API。
   - README、manual、API docs、examples 不展示 Python-compatible alias。
   - Python-to-Julia 对照只放在 compatibility / migration guide 中，并明确 Python 写法不是 Dynesty.jl API。

命名风格遵循当前仓库既有风格。不要为了纯 Julia-native 做机械全局重命名。保留自然、领域通用的 plotting workflow 名称，例如 `runplot`、`traceplot`、`cornerplot`、`cornerpoints`、`boundplot`、`cornerbound`；这些不是 Python alias，而是 dynesty plotting workflow 名称。实现必须是 Julia-native data object / RecipesBase recipe，不返回 Matplotlib figure/axes。

## 能力补齐标准

目标是能力级全部补齐：

- Python dynesty 的用户可见能力、算法行为、数值功能、结果处理、采样 workflow、plotting workflow、persistence workflow、parallel workflow、docs/demos/notebooks workflow 都必须在 Julia 中有 Julia-native 等价能力。
- 不要求 Julia 中出现同名 Python 符号或 Python 生态绑定实现。
- Matplotlib-specific、multiprocessing-specific、pickle-specific、Python function wrapper、docstring generator 等 Python-specific 实现细节不照搬；它们应在 migration matrix 中映射到 Julia-native replacement / internal / not applicable，并说明理由。
- 不允许把真实能力缺口标成 future work。
- 最终 migration matrix 不能有 `pending`、`todo`、`partial` 或 `future work` 状态。

最终完成态可以是：

- `implemented`：Julia-native 能力已实现并测试。
- `replacement`：由 Julia-native API/workflow 覆盖，并已记录。
- `internal`：Python 内部行为由 Julia 内部实现或调用路径覆盖。
- `not applicable`：仅限 Python-specific 机制，例如 Matplotlib figure plumbing、pickle/multiprocessing glue、docstring generator 等，并且必须说明理由。

如果遇到无法补齐、无法替代、也无法合理标记 not applicable 的项，必须停下来解决，不得继续装作完成。

## 行为默认值

- API 形状纯 Julia-native。
- 数值、算法和 workflow 默认尽量匹配 Python dynesty。
- 默认采样启发式、停止条件、bound/sample 行为、结果数值语义、shape 约定、后处理公式、plotting 数据含义等，应尽量匹配 Python。
- 如果为了 Julia 性能、安全或生态必须改变默认行为，要写入 compatibility docs 并有测试覆盖。
- 保留 `copy_inputs=false` 作为性能优先默认；保留 `copy_inputs=true` 作为 Julia-native safety option。它不是 Python alias。文档说明用户函数应把输入视为 read-only、短生命周期 view/scratch。
- 旧 Dynesty.jl `.jls` checkpoint、`.jld2` results archive、HDF5 evaluation history 不保证兼容。新版本自己的 save/load/checkpoint/restore 必须完整测试通过。不要为了兼容旧 alias 或旧字段保留 Python-compatible schema。

## Stage 0: Audit, Branch, Worktree And Benchmark Suite

先做审计和基线整理，然后继续执行，不等待用户再次批准。

1. Check branch:
   - Run `git branch --show-current`.
   - If current branch is `main` or `master`, create and switch to a new branch such as `julia-native-feature-completion`.
   - If already on a non-main branch, use the current branch.
2. Capture full initial worktree:
   - Run `git status --short`.
   - Record every untracked/modified/deleted file in `docs/feature_gap_audit.md`.
   - Throughout the goal, classify each file as related, obsolete, generated, cache, output, or unrelated; related files should be committed, obsolete/generated/cache/output files may be deleted. Final worktree must be clean.
3. Capture Python source snapshot from current `../dynesty` checkout:
   - `git -C ../dynesty rev-parse --abbrev-ref HEAD`
   - `git -C ../dynesty rev-parse HEAD`
   - `git -C ../dynesty status --short`
   - Do not modify `../dynesty`.
4. Capture Julia repository snapshot:
   - `git branch --show-current`
   - `git rev-parse HEAD` if available
   - `git status --short`
5. Update Python source snapshot references if stale:
   - `docs/source_snapshot.md`
   - `docs/src/source_snapshot.md`
   - `docs/migration_matrix.md`
   - `docs/src/migration_matrix.md`
   - `test/reference/python/README.md`
   - `docs/feature_gap_audit.md`
   - any other file that records Python branch/commit/status
6. Create or update `docs/feature_gap_audit.md`.
   - This document is both audit record and final completion report.
   - It must record source snapshots, initial worktree, audit method, feature gap table, Python test mapping, docs/demos mapping, API alias removal inventory, benchmark suite definition, implementation stages, validation results, commit list, deleted/submitted pre-existing files, and final summary.
7. Define the Full Benchmark Suite.
   - Enumerate `benchmark/`, relevant `examples/`, Python helper/plotter scripts, formal benchmark output dependencies, and any benchmark documented in README/docs.
   - Classify entries as formal benchmark, benchmark helper, plotting/overlay postprocessor, compile/smoke-only helper, external-environment dependent benchmark.
   - Write the exact command list into `docs/feature_gap_audit.md`.
   - From Stage 1 onward, every stage must run this full suite exactly as defined.
   - If a benchmark needs environment setup, create project-local/user-level setup or fallback so it can run; do not skip.
8. Audit current Julia exports and public API.
   - Enumerate `src/Dynesty.jl` exports.
   - Identify Python-compatible aliases and old compatibility entry points to remove.
   - Identify exported symbols lacking docs.
9. Audit Python package surface.
   - List every file under `../dynesty/py/dynesty`.
   - Identify public classes/functions/constants from module exports, docs, tests, demos, examples and README.
   - Identify internal helpers that affect public behavior.
   - Internal Python helpers must be audited, but Julia implementation does not need the same names. If a helper affects public behavior, cover it through Julia-native implementation and tests. If it is Python-only plumbing, mark replacement/not applicable with reason.
10. Audit Julia package surface.
   - Public constructors/functions documented in README/docs.
   - Exported symbols.
   - Existing compatibility aliases.
   - Internal helpers currently listed in migration matrix.
11. Compare Python and Julia symbol/behavior coverage.
   - Do not rely only on current migration matrix.
   - Verify each row against source/tests/docs.
   - Find Python symbols/behaviors not represented in the matrix.
   - Find stale, over-optimistic, partial or under-tested rows.
12. Map Python tests one by one.
   - Enumerate every `../dynesty/tests/*.py` file.
   - For every Python test function or clear behavior scenario, map to a Julia test file/testset, Python fixture + Julia reader test, Julia-native replacement behavior test, or not-applicable reason.
   - Final audit cannot leave unmapped Python test behavior.
13. Map Python docs/demos/notebooks one by one.
   - Enumerate `../dynesty/docs`, `../dynesty/demos`, notebooks if present, and README workflows.
   - For each meaningful user workflow, map to Julia docs page, Documenter manual/API page, Julia example script, benchmark/example workflow, or not-applicable reason.
   - Migration is workflow/capability migration, not Python code-form migration. Notebooks may become Julia scripts or Documenter pages.
14. Search current Julia repo for TODO/compatibility signals:
   - Search for `TODO`, `FIXME`, `missing`, `partial`, `not implemented`, `future`, `unsupported`, `alias`, `compat`, `rstate`, `use_pool`, `PoolUsage`, `blob`, `samples_bound`, `random_state`, `logl_args`, `kwargs`.
   - Classify each finding.
15. Audit CI.
   - Check `.github/workflows/test.yml`.
   - If missing, add a conservative GitHub Actions workflow for Julia package tests.
   - If present, update it for the new pure Julia-native testing strategy.
16. Audit docs navigation.
   - Check `docs/make.jl`, `docs/src/index.md`, manual/API page links.
   - Ensure migration guide, compatibility, API, examples and manual pages are reachable.

Stage 0 should commit the audit + contract groundwork when complete and validated.

Suggested Stage 0 commit messages:

- `Audit Python feature gaps`
- `Update migration contract for Julia-native API`

Use one or more focused commits if Stage 0 is large.

## API Cleanup And Breaking Version Stage

After Stage 0, perform the pure Julia-native breaking cleanup before filling remaining feature gaps.

1. Update `CODEX_GOAL_PROMPT.md`.
   - Remove old requirements for low-cost Python compatibility aliases.
   - State that Python dynesty is the algorithm/behavior/workflow reference, not the API surface reference.
2. Update package version in `Project.toml`.
   - Treat alias removal as breaking cleanup.
   - If current version is `0.x.y`, bump minor, e.g. `0.1.y -> 0.2.0`.
   - If current version is `1.x`, bump major.
3. Add or update `CHANGELOG.md`.
   - Record breaking cleanup.
   - List removed Python-compatible aliases.
   - Explain migration to Julia-native API.
   - Record major capability completions as they are implemented.
4. Define and implement public API inventory.
   - Add or update a test such as `test/test_api_surface.jl`.
   - Check exported/public symbols match the pure Julia-native API list.
   - Check removed Python aliases are not exported and not accepted by public APIs.
   - Add to `test/runtests.jl`.
5. Remove Python-compatible aliases by module.
   - Sampler aliases: no-bang mutating aliases, Python-style constructor keywords, string enum options.
   - Results aliases: `blob`, old schema aliases, Python fixture field aliases.
   - Parallel aliases: `use_pool`, `PoolUsage`; introduce `ParallelPolicy`.
   - Index helpers: remove public Python 0-based compatibility helpers.
   - Args/kwargs wrappers: remove Python-style user-function wrappers.
6. Add negative tests.
   - Non-bang mutating alias is absent or rejected.
   - String enum-like options rejected.
   - `rstate` / `random_state` rejected.
   - Results field aliases rejected.
   - `use_pool` rejected.
   - old `PoolUsage` rejected or absent.
   - Python-style args/kwargs wrappers rejected.
   - Public validation errors check exception type and key message terms, not full exact strings.
7. Update all tests, examples, README, docs and benchmark scripts to use pure Julia-native API.
8. Finish API cleanup with a validation stage.
   - Public API inventory test passes.
   - Negative alias tests pass.
   - Docs/examples contain no Python alias usage except in migration/compatibility comparison text.
   - Changelog and migration guide explain breaking changes.

Run full validation before each commit in this stage.

## Feature Gap Completion Stages

After API cleanup is complete, fill every remaining Python capability gap on the clean Julia-native API foundation.

Suggested order, adjusting based on Stage 0 audit:

1. Low-risk docs/tests/examples gaps.
2. Utilities, results and post-processing behavior.
3. Bounding and internal sampler behavior.
4. Static sampler behavior.
5. Dynamic sampler behavior.
6. Persistence and evaluation history behavior.
7. Parallel backend and `ParallelPolicy` behavior.
8. Plotting workflow behavior.
9. Docs/demos/notebooks parity.
10. CI, docs navigation, final matrix consistency and final clean worktree.

For every gap:

- Implement Julia-native ability or documented Julia-native replacement.
- Add or update tests according to the testing policy.
- Update migration matrix and compatibility docs.
- Update docs/examples/migration guide if user-facing.
- Update `docs/feature_gap_audit.md` status.
- Run full validation.
- Commit.

## Testing And Fixture Policy

Every implemented or replaced capability must have tests.

Use this policy:

- Public API and core numerical functions: direct Julia tests.
- Stable deterministic behavior with meaningful Python comparison: Python fixture + Julia fixture reader test.
- Random sampler trajectories, parallel scheduling and dynamic Monte Carlo: invariant/statistical/reproducibility tests, not sample-by-sample Python equality unless explicitly appropriate.
- Docs/examples workflows: smoke tests or example tests.
- Critical public/core utility kernels: add limited `@inferred` or allocation sanity tests where stable and not brittle.
- Do not add brittle inference tests to full sampler runs, parallel scheduling, random trajectories or plotting backend recipes.

Python fixtures:

- Generate from current read-only `../dynesty` checkout.
- Record branch, commit, dirty status, Python version, NumPy/SciPy versions, fixture purpose and tolerance rationale in `test/reference/python/README.md`.
- Default Julia tests should read committed fixtures, not require live Python.
- Python fixture may preserve Python raw schema; conversion belongs in test helper / fixture reader, not in public `src/` API.
- Current Julia repo Python helper scripts may be edited:
  - `test/reference/python/generate_reference.py`
  - `examples/*.py`
  - `benchmark/*.py`
  - docs/report helper scripts
  - Run `python3 -m py_compile ...` or equivalent smoke checks after edits.

## Documentation Requirements

Maintain both root docs and Documenter sources.

Synchronize changes between:

- `docs/migration_matrix.md`
- `docs/src/migration_matrix.md`
- `docs/compatibility.md`
- `docs/src/compatibility.md`
- `docs/source_snapshot.md`
- `docs/src/source_snapshot.md`
- `docs/examples.md`
- `docs/src/examples.md`
- other root/docs/src equivalents where present

Migration matrix semantics:

- Keep one row per Python symbol/behavior where useful for traceability.
- Julia column records Julia-native capability mapping, not same-name API promise.
- Examples:
  - Python `run_nested` capability maps to Julia `run_nested!`, with no `run_nested` alias.
  - Python `res.blob` capability maps to Julia `res.blobs`, with no `blob` alias.
  - Python `Pool` / `use_pool` capability maps to Julia `ParallelPolicy` and map backends.
  - Python args/kwargs wrappers map to Julia closures/callable objects.

Compatibility docs:

- Record public behavior differences.
- Record breaking cleanup and removed aliases.
- Record that old Dynesty.jl saved files are not guaranteed compatible.
- Record Julia RNG behavior and Python same-seed non-equivalence.

Migration guide:

- Add or update:
  - `docs/migration_guide.md`
  - `docs/src/migration_guide.md`
- Link it from README and Documenter navigation.
- Include Python-to-Julia comparisons only here or in compatibility docs.
- Explain:
  - bang mutating API
  - Symbol options
  - `rng`
  - closures/callable objects instead of args/kwargs
  - 1-based indices
  - `ParallelPolicy`
  - Results field names
  - plotting recipes/data objects
  - persistence/checkpoint/results save-load differences
  - no old file compatibility guarantee

README:

- Update to a pure Julia-native quickstart.
- Do not show Python-compatible aliases.
- Cover or link:
  - install/setup
  - basic static nested sampling
  - dynamic nested sampling
  - results extraction
  - plotting workflow
  - persistence/checkpoint/results save-load
  - parallel backends / `ParallelPolicy`
  - migration/compatibility notes

Public API docs:

- Every exported symbol must have docstring and/or Documenter API/manual coverage.
- If an exported symbol should not be public, remove it from exports instead of leaving undocumented.

Docs/demos/notebooks:

- Python docs/demos/notebooks must be mapped one by one to Julia workflows.
- Do not require line-by-line translation or notebook format preservation.
- Julia examples must be smoke-tested.

Python helper examples:

- Current repo Python helper scripts may remain only as cross-check / benchmark / reference tools.
- They are not Dynesty.jl user API examples.
- Document their role clearly.

## CI Requirements

- `.github/workflows/test.yml` must exist by the end.
- It should run Julia package tests using the project.
- If docs build is a formal deliverable, include docs build or explain in `docs/feature_gap_audit.md` why CI keeps it local-only.
- CI must not require writable `../dynesty`.
- CI must not run extremely long benchmarks unless explicitly designed for that workflow.

## Full Validation Required Before Every Stage Commit

Before each stage commit, run all of the following:

1. Full package tests:

   ```bash
   julia --project=. -e 'using Pkg; Pkg.test()'
   ```

2. Docs build:

   ```bash
   julia --project=docs docs/make.jl
   ```

3. Formatter / format check using the repo's JuliaFormatter setup.
   - If the repo has a clear formatting command, run it.
   - If formatting modifies files, include those files in the relevant stage commit.

4. Aqua.
   - If Aqua is already included in `Pkg.test()`, record that.
   - Otherwise run the existing Aqua test directly.

5. Full benchmark suite.
   - Use the exact command list defined in Stage 0.
   - Record command outcomes and summary in `docs/feature_gap_audit.md`.
   - Do not commit benchmark output directories unless a stage explicitly updates report assets.

6. Python helper checks when Python files changed:

   ```bash
   python3 -m py_compile <changed-python-files>
   ```

7. Git whitespace check:

   ```bash
   git diff --check
   ```

Validation failures:

- Do not commit and do not continue to next stage until fixed.
- Fix code, tests, dependencies, docs, scripts or project-local/user-level environment.
- If a system-level dependency is missing, first implement a project-local fallback or user-level setup without sudo.
- Do not skip or mark not-run.

## Git And Worktree Rules

- Stage changes carefully.
- Do not commit unrelated caches, venvs, benchmark outputs, docs build outputs, `Manifest.toml`, `__pycache__`, temporary logs or generated scratch files.
- Final `git status --short` must be empty.
- You may delete current-repo files classified as unrelated, obsolete, temporary, generated output or cache, including files that existed before this goal, to make the worktree clean.
- Record deleted/submitted pre-existing files in `docs/feature_gap_audit.md`.
- Do not delete or modify anything in `../dynesty`.
- Do not push.

Suggested commit messages:

- `Audit Python feature gaps`
- `Update migration contract for Julia-native API`
- `Remove sampler compatibility aliases`
- `Rename pool usage policy`
- `Clean results public schema`
- `Add Julia-native migration guide`
- `Complete Python test mapping`
- `Fill plotting workflow gaps`
- `Add package CI workflow`
- `Finalize feature gap audit`

## License, Citation And Attribution

- Keep MIT license.
- Preserve upstream attribution.
- If audit finds missing attribution, citation or README/docs citation coverage, fix it.
- You may update `get_citations`, README citation section and docs citations.
- If there is a legal/copyright uncertainty, stop and ask the user.

## Stop-And-Ask Conditions

Do not ask about already-confirmed strategy. Only stop if one of these new blockers appears:

- A Python capability cannot reasonably be implemented or replaced in Julia-native form.
- A required verification step cannot be made to pass even after code/script/dependency/environment fallback work.
- A license/copyright question is unclear.
- A necessary change would require modifying `../dynesty`.
- A necessary environment change would require sudo/system package manager/system directory modification.
- A benchmark suite item cannot be defined or run without external resources unavailable on this machine.
- The repository state makes it impossible to reach clean worktree without deleting something whose purpose cannot be determined.

## Definition Of Done

The goal is complete only when:

- `CODEX_GOAL_PROMPT.md` reflects the pure Julia-native migration contract.
- `Project.toml` version has been bumped for breaking cleanup.
- `CHANGELOG.md` records the breaking cleanup and major completed work.
- Python source snapshot references are synchronized to current `../dynesty`.
- `docs/feature_gap_audit.md` is complete and updated to final state.
- Every Python source symbol/behavior, test behavior, docs/demo/notebook workflow and benchmark/CI expectation has a mapped final state.
- Existing Python-compatible aliases have been removed, and negative tests confirm they are not accepted.
- `PoolUsage` / `use_pool` have been replaced by Julia-native `ParallelPolicy` and backend configuration.
- Migration matrix has no `pending`, `todo`, `partial` or `future work` final statuses.
- Compatibility docs and migration guide explain all public differences and migration paths.
- All exported symbols are documented.
- All Julia examples are smoke-tested.
- CI workflow exists and matches the project testing strategy.
- Every stage has passed full validation and has a focused commit.
- Final `git status --short` is empty.
- No commits were pushed.

Final response must be in Chinese and concise. Include:

- branch name
- commit hashes and short messages
- major capabilities completed
- files deleted or submitted from the initial worktree
- validation commands and outcomes
- final worktree cleanliness
- remaining risks, if any
```
