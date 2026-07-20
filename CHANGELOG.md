# Changelog

## 0.3.0 (2026-07-19)

### Added
- `CLI binary` — `golden review|accept|reject|pending|status|clean|show|test-review` with `--snapshot`, `--json`, `--dry-run`, `--spec-cmd` flags
- `Golden.test_and_review!` — run `crystal spec` then launch review on success
- `Golden.show_snapshot` — read snapshot file contents from path
- `Makefile` with `test-review` target (`crystal spec && golden review`)
- Review TUI: `d` toggles unified diff display via `Bubbles::Viewport::Model`
- Review TUI: `i` toggles source context (reads `.golden.meta`, shows 3 lines before assertion)
- Review TUI: inline word-level diff highlighting (insertions green, deletions red, replacements bold+underline)
- Review TUI: `s` skip, `A`/`R`/`S` batch accept/reject/skip all, `g`/`G` go top/bottom
- Review TUI: `?` help overlay, review summary (accepted/rejected/skipped on exit)
- `Golden.report_pending!` — end-of-run notification for pending snapshots
- `Golden.normalize` and `Golden.unified_diff` made public for reuse

### Changed
- `shard.yml` target changed from `src/golden.cr` to `src/golden_cli.cr`
- All CLI dispatch methods return `String` for consistent output formatting

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
- Atomic file writes: temp file + `File.rename` prevents partial golden files
- `GOLDEN_FORCE_PASS` env var: creates `.golden.new` without test failure
- `Golden.status` reporting: snapshot, pending, metadata, and orphan counts
- Serializer registry: `Golden.register_serializer(:name, ->(v) { ... })` with `serializer:` setting
- Structured path redactions: `Golden.add_path_redaction("key.nested", "***")` for JSON values

### Changed
- `Golden.update=` now maps to `UpdateMode::Always`/`No` backward compat
- `Golden.init` now checks `GOLDEN_UPDATE` environment variable internally
- `Golden.require_equal` accepts optional `metadata_line` parameter
- `Golden.dir=` delegates to `Golden.settings.dir`
- `Golden.with_settings` now accepts `serializer:` kwarg and preserves all settings
- `process_output` made public as `apply_path_redactions` for structured JSON redaction

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
