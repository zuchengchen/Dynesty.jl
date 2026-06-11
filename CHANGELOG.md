# Changelog

## 0.2.0 - 2026-06-12

### Breaking

- Removed Python-compatible public aliases from the sampler API.
- Removed no-bang mutating `run_nested`; use `run_nested!`.
- Removed `DynamicNestedSampler`; use `DynamicSampler`.
- Removed `citations`; use `get_citations`.
- Removed `PoolUsage` and Python-style `use_pool`; use `ParallelPolicy` with
  Julia-native fields `initialization`, `proposals`, `bounds`, and `stopping`.
- Removed `rstate` and `random_state`; use `rng` with an `AbstractRNG` or
  integer seed.
- Removed string enum-like options for `bound`, `sample`, `parallel`, and
  `proposal_scheduler`; use Symbols such as `:multi`, `:rwalk`, `:threads`, and
  `:batch`.
- Removed public Python index conversion helpers. Periodic and reflective
  dimension inputs are Julia 1-based.
- Removed public `Results` schema aliases `blob`, `samples_bound`, and `batch`;
  use `blobs`, `boundidx`, and `samples_batch`.

### Added

- Added `test/test_api_surface.jl` to lock down the Julia-native export set and
  negative tests for removed Python-compatible aliases.
- Added integer seed support for public sampler `rng` keywords.

### Changed

- Updated README, compatibility notes, API docs, and migration matrix to teach
  only the Julia-native API.
- Added a migration guide for rewriting Python-style and old compatibility
  usage to the Julia-native API.
- Updated the migration contract in `CODEX_GOAL_PROMPT.md` to make Python
  dynesty the algorithm/workflow reference rather than the public API surface
  reference.
