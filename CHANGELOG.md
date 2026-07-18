# Changelog

## 0.2.0 (2026-07-18)

### Added
- `UpdateMode` enum (`Auto`, `Always`, `No`, `New`, `Unseen`) with CI-aware auto-detection
- `Golden.with_settings` for scoped configuration overrides
- Macro-based snapshot assertions: `assert_snapshot`, `assert_json_snapshot`, `assert_yaml_snapshot`, `assert_binary_snapshot`
- Auto-naming from `@type.name` / `@def.name` with line-number fallback
- `Golden.group` prefix for organizing snapshots into subdirectories
- Filters (`add_filter`) and redactions (`add_redaction`) for scrubbing dynamic content
- Custom comparators via `Comparator` module and `FuzzyComparator` for numeric tolerance
- `globbing batch testing` via `Golden.glob_snapshots`
- Pending snapshot workflow: `.golden.new` staging, `pending_snapshots`, `accept_all!`, `reject_all!`
- `unreferenced_snapshots` and `cleanup!` for orphan detection and removal
- `snapshot_metadata` sidecar (`.golden.meta` JSON) with source line tracking
- `Golden.configure_with` and `Golden.auto_configure!` for `.golden.yml` config files
- `Golden.review!` interactive TUI using `bubbles` for reviewing pending snapshots
- `Golden.reset_tracking!` for snapshot access tracking

### Changed
- `Golden.update=` now maps to `UpdateMode::Always`/`No` backward compat
- `Golden.init` now checks `GOLDEN_UPDATE` environment variable internally
- `Golden.require_equal` accepts optional `metadata_line` parameter
- `Golden.dir=` delegates to `Golden.settings.dir`

## 0.1.0 (2025)

### Added
- Initial release
- `Golden.require_equal` for golden file comparison
- `Golden.dir`, `Golden.update`, `Golden.update?` configuration
- `Golden.init` for env-var-based setup
- `Golden.find_spec_dir`, `Golden.spec_test_data_dir` directory helpers
- `Golden.group`, `Golden.group=` for test grouping
- Control code escaping and line ending normalization
- Unified diff output via `similar` shard
- String and Bytes output support
