# Changelog

## Unreleased

### Added
- `.golden.meta` sidecars now record `source_file` (relative to the project
  root), `expression` (captured by the assertion macros), `description`,
  `info`, and `input_file` in addition to `name`, `created_at`, and `line`
- `Golden.with_settings` accepts `description`, `info`, `input_file`, and
  `omit_expression`; `Golden::Settings` exposes the matching properties
- `Golden.glob_snapshots` records the matched input path as `input_file`
- Pending snapshots write `.golden.new.meta`; `Golden.promote_pending!` and
  `Golden.discard_pending!` move or delete the sidecar with the snapshot, and
  `accept_all!` / the review TUI preserve metadata from the pending files
- `Golden.require_equal` accepts `expression`, `source_file`, and `input_file`
  for callers that do not use the macros
- `snapshot_suffix` support: names are stored as `name@suffix.golden`
- `prepend_module_to_snapshot` support: assertion macros pass their module name
  and opt in to `Module/name` snapshot paths. It defaults to `false` here
  (upstream defaults to `true`) to keep existing snapshot paths stable
- `Golden.allow_duplicates` block and `Golden.allow_duplicates?`: repeated
  snapshot names are allowed, but differing content inside the block raises
- `require_equal` accepts `module_name` for callers that do not use the macros
- `strip_ansi_escape_codes` setting (and `Golden.strip_ansi_escape_codes`)
  removes ANSI CSI sequences before redactions and filters
- `sort_maps` setting sorts JSON object keys in `assert_json_snapshot` output
- `allow_empty_glob` setting lets `glob_snapshots` accept a pattern with no
  matches; without it an empty match now raises
- `Golden.clear_filters`, `Golden.clear_redactions`, and the `remove_*`
  helpers for description, info, input_file, and snapshot_suffix, plus
  `Golden::Settings#has_info?`
- path selectors now support ranges (`[0:2]`, `[-1:]`), wildcards (`.*`),
  deep wildcards (`.**`), quoted keys, and comma-separated alternatives
- `Golden.dynamic_redaction`, `Golden.rounded_redaction`,
  `Golden.sorted_redaction`, and `Golden.add_dynamic_redaction` for computed
  path redactions; `Golden.add_path_redaction` accepts a `ValueRedaction`
- `sort_selector` setting sorts only the JSON objects matched by the selector

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
