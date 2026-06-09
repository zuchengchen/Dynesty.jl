# Dynesty.jl Migration Notes

- Treat `../dynesty` as a read-only source reference. Do not modify it, pull it,
  or switch its branch.
- Follow `CODEX_GOAL_PROMPT.md` as the migration contract.
- Keep `Manifest.toml` uncommitted.
- Update `docs/migration_matrix.md` whenever Python symbols are implemented or
  intentionally replaced.
- Update `docs/compatibility.md` for public behavior differences.
- Run relevant Julia tests before each stage commit.

