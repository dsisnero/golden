# Parity Plan: Crystal Golden vs Rust/Ruby insta

## Where we are

- **Current focus:** Phase 6.11 — info block in the snapshot summary
  (`runtime.rs::SnapshotAssertionContext.print_snapshot_info`,
  `snapshot.rs::MetaData.private_info`).
- **Next up (in order):**
  1. **6.11 Info block in the summary.** Extend `Golden.snapshot_summary`
     (`src/golden.cr`) to print `Expression:`, the description, and the
     `Info:` body ahead of the mismatch text, sourced from the assertion
     args with `.golden.meta` fallback. Reference:
     `vendor/insta/insta/src/output.rs::print_info` (~427) and
     `runtime.rs::print_snapshot_info` (~635). Closes 2 `partial` rows; add
     specs beside the 6.10 summary cases in
     `spec/golden_features_spec.cr`.
  2. **6.12 Fiber-local settings binding.** Make `Golden.settings` prefer a
     per-fiber `Settings` while `with_settings` is active (upstream
     `Settings.bind` / `clone_current`) and route
     `add_filter`/`add_redaction`/`add_path_redaction`/`dir=` through the
     getter so scoped overrides do not leak across fibers. Acceptance: two
     interleaved fibers inside `with_settings` see only their own settings;
     full suite green. Closes 2 `partial` rows.
  3. **6.13 Ledger hygiene for internal-shape rows.** No new behavior:
     reclassify `SnapshotAssertionContext*`, `SnapshotValue*`, `InlineValue`,
     `Snapshot`, `Snapshot.from_components`, and `Snapshot.module_name` as
     `ported`/`skipped` with a one-line rationale (single-pass function API,
     String/Bytes values, content-only files, user-set group prefix) so
     `partial` reaches 0. Add the shape divergence to **Intentional
     divergences**, rerun `make inventory`, refresh counts here.
  4. **Release chores.** `shard.yml` and `Golden::VERSION` still say `0.2.0`
     while `CHANGELOG.md` describes `0.3.0`: bump both, cut the changelog
     section, tag, publish.
- **Status by area:**
  - Review TUI (Phase 1): complete
  - Pending reporter (Phase 2): complete
  - CLI binary (Phase 3): complete
  - Test runner integration (Phase 5.1): complete
  - End-of-run reporter (Phase 5.2): complete — `Golden.init` installs a
    `Spec.after_suite` hook (or `at_exit` outside specs;
    `GOLDEN_REPORT_PENDING=0` disables) that prints pending file and inline
    snapshots; advisory only, no exit-status change
  - Settings metadata (Phase 6.1): complete
  - Snapshot naming (Phase 6.2): complete
  - Strict comparison (Phase 6.3): closed — always exact; `matches_fully` is
    not applicable without embedded metadata
  - Redaction helpers and selectors (Phase 6.4): complete
  - Settings/pending helpers (Phase 6.5): complete
  - Output normalization (Phase 6.6): complete
  - Pending directory (Phase 6.7): complete — `GOLDEN_PENDING_DIR`
    (`INSTA_PENDING_DIR` fallback) mirrors pending snapshots outside the
    snapshot tree; binary sidecar storage is closed as a divergence
  - Unreferenced snapshots (Phase 6.8): complete — references-file
    memoization plus Auto/Reject/Delete/Warn/Ignore policy applied after the
    suite; `GOLDEN_UNREFERENCED`, config `unreferenced:`, and
    `golden test-review --unreferenced MODE`
  - Redaction key traversal (Phase 6.9): complete — selectors can rewrite
    object keys through the `$key` segment, matching upstream traversal order
  - Snapshot summary (Phase 6.10): complete — mismatch and new-snapshot errors
    start with file, name, source (`path:line`), and input file, falling back
    to the metadata sidecar
  - Inline snapshots (Phase 4.1): complete — 4.1a–4.1e done; assertions record
    pendings, the CLI and review TUI patch source on accept, and reject/skip
    drop or keep registry entries without touching source
  - Rust parity inventory: 554 rows (125 `ported`, 15 `partial`,
    0 `missing`, 414 `skipped`)
  - Ruby ledger: not tracked (`vendor/insta-ruby` is a reference only)
- **Scoping notes / gotchas:**
  - Upstream pins: `vendor/insta` `1.48.0` (`3d62572`), `vendor/insta-ruby`
    `v0.3.0` (`500434b`). `vendor/x` (Charm Go) is declared but not checked out
    and is not a parity target.
  - Ledger scope is `insta/src,insta/tests` with `tree-sitter` discovery. Keep
    that scope/parser or every id churns.
  - 414 rows are `skipped` because they are insta's content/serialization
    engine (vendored YAML parser, content scanner/emitter), cargo/nextest
    workspace internals, or deliberate divergences (strict match, binary
    sidecar data files); Crystal replaces those with stdlib or does not expose
    them. Do not "fix" those rows into `missing`.
  - `spec_helper` calls `Golden.init`, so the suite installs the end-of-run
    reporter as `Spec.after_suite`. Do not add a plain `at_exit` reporter for
    specs: it runs before Crystal's spec runner and reports stale state.
  - An early feature spec sets `Golden.update = false`, which means
    `UpdateMode::No` for the rest of the suite. New specs that rely on the
    ambient update mode must pass `update_mode:` explicitly.
  - Process-global switches (`GOLDEN_PENDING_DIR`,
    `GOLDEN_SNAPSHOT_REFERENCES_FILE`, `GOLDEN_UNREFERENCED`,
    `GOLDEN_REPORT_PENDING`, `GOLDEN_DIFF_TOOL`) must be saved/restored in
    specs; also reset `Golden.unreferenced` to `Ignore`.
  - Untracked `package.json` / `package-lock.json` in the workspace root are
    tree-sitter scratch files, not part of the shard. Do not commit them.
  - `shard.yml` and `Golden::VERSION` still say `0.2.0` while `CHANGELOG.md`
    describes `0.3.0`; bump both at the next release.
- **Resume gate:** `make lint && make test && make inventory` (expected: 285
  examples, 554 ledger rows, `PARITY_DISCOVERY_BACKEND=chiasmus-tree-sitter`),
  then `make format-check`.
- **Last commit:** `b263017` snapshot summary on mismatch (6.10), on top of
  redaction key traversal (6.9), unreferenced policy (6.8), end-of-run reporter
  (5.2), pending directory (6.7), and inline review TUI (4.1e).
- **Gates:** `make lint` pass; `make test` pass (285 examples); `make inventory`
  pass (554 items tracked, tree-sitter backend).

Keep this block accurate after every feature: the next session reads it first
(see `AGENTS.md` → **How to resume**).

## Current Status

Golden has **feature parity** with Rust/Ruby insta on snapshot fundamentals and
the review TUI. All 6 quick wins and 3 Phase 1 features are implemented (skip,
batch ops, g/G navigation, help overlay, review summary, pending reporter, diff
display, source context, inline word-level highlighting), and the end-of-run
pending report matches insta-ruby's suite hooks.

The Rust ledger now measures symbol-level parity: 554 scoped declarations, of
which 125 are `ported`, 15 `partial`, 0 `missing`, and 414 `skipped` (insta's
content/serialization engine, cargo internals, and documented divergences).
Phases 1–5 and 6.1–6.10 are complete. Remaining work is the 6.11–6.13 backlog
in **Where we are**, which closes the 15 `partial` rows, followed by the release
chores.

---

## Phase 1: Review TUI Improvements (`src/golden/review.cr`)

### 1.1 Add diff display during review

**Problem:** Review TUI shows only filenames — no diff context.

**Required:**
- Read `.golden.new` content and corresponding `.golden` (if exists) for each pending item
- Use `similar` shard (Patience algorithm) to produce a unified diff
- Display diff inline using `Bubbles::Viewport::Model` for scrolling
- Show `(new snapshot)` label when no `.golden` exists yet

**Implementation sketch:**
```crystal
class PendingSnapshot
  getter name : String
  getter pending_path : String
  getter golden_path : String?
  getter new_content : String
  getter old_content : String?
  getter has_existing : Bool
  getter diff : String
end
```

**Key bindings:** `d` to toggle diff display.

**Depends:** `lib/similar` (already available, Patience algorithm).

---

### 1.2 Add skip operation

**Problem:** No way to defer a decision — only accept/reject.

**Required:**
- Add `s` key binding to skip current item
- Skipped items remain on disk as `.golden.new`
- Track skip actions in `@actions`

**Implementation:**
```crystal
when "s"
  skip_current
  @list.cursor_down
```

---

### 1.3 Add batch operations in TUI

**Problem:** Bulk accept/reject requires separate `Golden.accept_all!` / `Golden.reject_all!` API calls.

**Required:**
- `A` — accept all remaining (same as Rust's uppercase convention)
- `R` — reject all remaining
- `S` — skip all remaining

**Implementation:**
```crystal
when "A"
  accept_all_remaining
  return {self, Tea.quit}
```

---

### 1.4 Add source context display

**Problem:** No file path, line number, or code context shown during review.

**Required:**
- Read `created_at` and `line` from `.golden.meta` sidecar files
- Show snapshot name, golden path (relative to project root), source line
- Display 3 lines of source context before the assertion

**Implementation:**
- If `metadata_line` is set, read the source file and extract context
- Use `Bubbles::Textarea::Model` or a styled viewport for code display
- Key binding: `i` to toggle info display

---

### 1.5 Add review summary

**Problem:** No feedback after review exits.

**Required:**
- Print accepted/rejected/skipped counts and file paths to stdout
- Return structured result from `Golden.review!`

**Already partially done:** `Golden.review!` returns `Array(Tuple(String, String))`.

---

### 1.6 Add inline word-level diff highlighting

**Problem:** Diff is plain text, no inline change highlighting.

**Required:**
- Use `similar`'s `iter_inline_changes` method (returns `Array({Bool, String})`)
- Bool = emphasis flag; render emphasized segments underlined/bold in TUI

**Reference:** `lib/similar/src/text/inline.cr`

---

### 1.7 Key binding reference

| Key    | Current        | Planned        |
|--------|----------------|----------------|
| `y`    | Accept         | Accept         |
| `n`    | Reject         | Reject         |
| `s`    | -              | **Skip**       |
| `A`    | -              | **Accept all** |
| `R`    | -              | **Reject all** |
| `S`    | -              | **Skip all**   |
| `d`    | -              | **Toggle diff**|
| `i`    | -              | **Toggle info**|
| `j/k`  | Navigate       | Navigate       |
| `g/G`  | -              | Top/bottom     |
| `?`    | -              | **Help**       |
| `q`    | Quit           | Quit           |

---

## Phase 2: Pending Reporter (`src/golden/pending_reporter.cr`)

### 2.1 Add end-of-test-run pending notification

**Problem:** No output after `crystal spec` to tell users about pending snapshots.

**Required:**

When a spec run completes with `.golden.new` files present, print:

```
Pending snapshots found. Run `Golden.review!` to review them.
  - path/to/snapshot1.golden.new
  - path/to/snapshot2.golden.new
```

**Implementation sketch:**

```crystal
# src/golden/pending_reporter.cr
module Golden
  def self.report_pending!(dir : String? = nil)
    pending = pending_snapshots(dir)
    return if pending.empty?
    STDERR.puts "\n#{pending.size} pending snapshot(s) found."
    pending.each { |p| STDERR.puts "  #{p}" }
    STDERR.puts "Run `Golden.review!` to review them."
  end
end
```

Users call `Golden.report_pending!` in `spec_helper.cr` after all specs.

---

## Phase 3: CLI Binary (`bin/golden`)

### 3.1 Build CLI dispatcher

**Problem:** No CLI binary — users must call `Golden.review!` from Crystal code.

**Required:**

A CLI binary defined in `shard.yml`:

```yaml
targets:
  golden:
    main: src/golden_cli.cr
```

Commands:

| Command    | Flags             | Description                        |
|------------|-------------------|------------------------------------|
| `review`   | `--snapshot PATH` | Interactive TUI review             |
| `accept`   | `--snapshot PATH` | Accept all (or specific) pending   |
| `reject`   | `--snapshot PATH` | Reject all (or specific) pending   |
| `pending`  | `--json`          | List pending snapshots             |
| `status`   |                   | Snapshot overview (counts, files)  |
| `clean`    | `--dry-run`       | Remove unreferenced snapshots      |
| `show`     | `<snapshot>`      | Display snapshot contents          |

**Implementation sketch:**

```crystal
# src/golden_cli.cr
require "./golden"

command = ARGV.first?
case command
when "review" then Golden.review!
when "accept" then Golden.accept_all!
when "reject" then Golden.reject_all!
when "pending" then list_pending
when "status"  then print_status
when "clean"   then Golden.cleanup!
when "show"    then show_snapshot(ARGV[1])
else print_usage
end
```

---

## Phase 4: Inline Snapshots (`src/golden/inline/`)

Design: [plans/inline-snapshots.md](inline-snapshots.md). Crystal has no `syn`
or Prism equivalent, so the patcher is line-based and refuses ambiguous edits.

**4.1a Design** — done: API, runtime compare/record flow, conservative source
patcher, CLI commands, and ledger mapping are specified in the design doc.

- [x] **4.1b Pending registry and runtime** — `assert_inline_snapshot`,
      `normalize_inline`, `.golden-inline.json` upsert, mismatch diff, duplicate
      `file:line` guard, `pending_inline_snapshots`, and
      `reject_inline_snapshots!`.
- [x] **4.1c Source patcher** — single-literal replacement with ambiguity and
      multi-line refusal, atomic writes, `GOLDEN_UPDATE` auto-accept, and
      `accept_inline!` / `reject_inline!`.
- [x] **4.1d CLI** — `golden inline-pending` (`--json`), `inline-accept` (`--dry-run`), `inline-reject`.
- [x] **4.1e Review TUI** — `golden review` lists file and inline pendings in
      one list; accepting an inline entry patches the expected literal in its
      source and drops the registry entry, rejecting drops it without touching
      source, and skips keep it. Patch failures are reported in the action list
      and keep the entry for a retry. `review!` accepts `root:` (CLI `--root`),
      matching `inline-accept`.

Acceptance for each sub-item: specs from the design doc pass, ledger rows for
the covered upstream declarations move off `missing`, and the plan block stays
accurate.


---

## Phase 5: Test Runner Integration

### 5.1 Add `crystal spec --review` equivalent

**Problem:** No end-to-end flow: run tests → review pending.

**Required:**
- A script or CLI flag that runs `crystal spec` then auto-launches `Golden.review!`
- Equivalent to `cargo insta test --review`

**Implementation:**
```bash
# In Makefile or scripts/
golden-test-review:
  crystal spec && golden review
```

### 5.2 Add the end-of-run pending reporter hook

**Problem:** pending snapshots are only reported when the caller remembers to
call `Golden.report_pending!`; insta-ruby prints them automatically when the
suite finishes.

**Upstream reference:** Ruby only — Rust `insta` has no in-crate hook (the
`cargo-insta` runner reports after the test process). insta-ruby installs
`PendingReporter.flush_and_report!` from `RSpec.after(:suite)`
(`lib/insta/rspec/hooks.rb`) and `Minitest.after_run`
(`lib/minitest/insta_plugin.rb`); the reporter flushes buffered inline updates,
then prints pending file snapshots and pending inline entries with a review
hint.

**Required:**
- `Golden.install_exit_reporter!` registers one hook; it is idempotent and
  installed by `Golden.init`. When `spec` is part of the program the hook is
  `Spec.after_suite` (Crystal's spec runner registers its own `at_exit`, so a
  plain `at_exit` would fire before the examples); otherwise it is `at_exit`.
- The hook calls `Golden.report_pending!`, which now covers file pendings
  (`pending_snapshots`) and inline pendings (`pending_inline_snapshots`) and
  hints at `golden review`.
- `GOLDEN_REPORT_PENDING=0|false|no|off` disables installation;
  `Golden.report_pending_on_exit?` exposes the decision.
- Advisory only: stderr output, no exit-status change, and errors in the hook
  are swallowed so they cannot mask a test failure.

**Divergence:** insta-ruby buffers inline updates in memory and flushes them in
the hook; Golden patches inline literals immediately (or records pendings), so
the Crystal hook only reports. Crystal has no Minitest/RSpec metaphor, so
`Spec.after_suite` is the suite-level analogue and `at_exit` covers plain
binaries. Cargo-insta’s post-run `test.unreferenced` handling is not part of
this item (tracked as 6.8).

---

## Phase 6: Upstream settings and snapshot parity (from the Rust ledger)

Scope comes from `plans/inventory/rust_port_inventory.tsv`; each item closes a
group of `missing`/`partial` rows and must update those rows in the same commit.

- [x] **6.1 Settings metadata parity** — `.golden.meta` now records
      `expression` (captured by the macros), `description`, `info`,
      `input_file`, and `source_file`; `Golden.with_settings` exposes
      `description`, `info`, `input_file`, and `omit_expression`; pending
      metadata is carried through accept (`settings.rs`, `snapshot.rs`).
- [x] **6.2 Snapshot naming** — `snapshot_suffix` appends `@suffix`;
      `prepend_module_to_snapshot` prefixes the macro module name (default
      `false` here, upstream `true`); `Golden.allow_duplicates` /
      `allow_duplicates?` detect differing content for repeated names
      (`settings.rs`, `runtime.rs`).
- [x] **6.3 Strict comparison** — closed without code: Golden stores no
      metadata inside snapshot files and compares normalized content exactly,
      so `matches_fully` / `require_full_match` add nothing. Ledger rows are
      `skipped` with that rationale.
- [x] **6.4 Redaction helpers and selector grammar** — selectors support
      keys, quoted keys, indices, ranges (including negative), wildcards, deep
      wildcards, and comma-separated alternatives; `dynamic_redaction`,
      `rounded_redaction`, `sorted_redaction`, and `add_dynamic_redaction` are
      implemented, and `sort_selector` sorts only matched objects. Object keys
      are not traversed as paths (values only).
- [x] **6.5 Settings and pending lifecycle helpers** — `clear_filters`,
      `clear_redactions`, `remove_description/info/input_file/snapshot_suffix`,
      `Settings#has_info?`, and stale-pending cleanup on a passing assertion
      (`cleanup_passing`). Binary `.new.*` cleanup is not applicable here.
- [x] **6.6 ANSI and map ordering** — `strip_ansi_escape_codes` removes CSI
      sequences before redactions; `sort_maps` sorts JSON object keys in
      `assert_json_snapshot`; `allow_empty_glob` controls empty glob matches.
- [x] **6.7 Pending snapshot directory** — `Golden.pending_dir` reads
      `GOLDEN_PENDING_DIR` with an `INSTA_PENDING_DIR` fallback;
      `Golden.pending_snapshot_path` mirrors a snapshot's path (relative to
      the snapshot dir) under that directory and refuses paths that would
      escape it; `Golden.golden_path_for_pending` maps a pending file back.
      Mismatches, `pending_snapshots`, `status`, `accept_all!`,
      `reject_all!`, `review!`, and pending promotion all route through these
      helpers. Binary sidecar data files (`Snapshot.build_binary_path`) are
      closed as a divergence: `.golden` stays content-only and binary
      payloads stay base64 (`env.rs`, `snapshot.rs`).
- [x] **6.8 Unreferenced snapshot policy** — `Golden::UnreferencedMode`
      (`auto`, `reject`/`error`, `delete`, `warn`, `ignore`; `auto` resolves
      to reject in CI and delete locally) with
      `Golden.handle_unreferenced_snapshots!`, which walks `.golden` files
      under the snapshot dir, prints to stderr, deletes (including the
      metadata sidecar) or raises `Golden::UnreferencedSnapshotsError`.
      `Golden.memoize_snapshot_file` appends every asserted snapshot to
      `GOLDEN_SNAPSHOT_REFERENCES_FILE` (`INSTA_SNAPSHOT_REFERENCES_FILE`
      fallback) and the file is removed after handling, so detection works
      across processes. Configured by `GOLDEN_UNREFERENCED`, the flat
      `unreferenced:` config key, and `golden test-review --unreferenced MODE`
      (exported to the spec child), default `ignore` (`env.rs`,
      `cargo-insta/src/cli.rs`). `ci?` now matches `utils.rs::is_ci`
      (`CI=false|0|""` is not CI).
- [x] **6.9 Redaction key traversal** — object keys are redacted through the
      synthetic `$key` segment (`.hm.$key`, `.users.*.$key`, `**.$key`), the
      original key is used for value paths, dynamic key redactions receive
      the key text and `.$key` path, and non-string replacements are
      stringified. Redactions apply sequentially in registration order, so a
      value selector registered after a key rewrite no longer matches, same
      as upstream (`redaction.rs::Selector.redact_impl` / `redact_struct`).
- [x] **6.10 Snapshot summary on mismatch** —
      `Golden.snapshot_summary` renders upstream's `print_snapshot_summary`
      header (`Snapshot file`, `Snapshot`, `Source: path:line`, `Input file`)
      and prefixes mismatch and new-snapshot errors. Source/line/input fall
      back to the `.golden.meta` sidecar when the assertion does not supply
      them, and paths under the current directory are shown relative
      (`output.rs`).
- [ ] **6.11 Info block in the summary** — extend `Golden.snapshot_summary`
      with upstream `print_info`: `Expression:`, the description line, and the
      `Info:` body before the mismatch text. Values come from the assertion
      arguments (`expression`/`description`/`info` settings and macro capture)
      with `.golden.meta` fallback. Closes
      `runtime.rs::SnapshotAssertionContext.print_snapshot_info` and
      `snapshot.rs::MetaData.private_info`.
- [ ] **6.12 Fiber-local settings binding** — `Golden.settings` should prefer
      a per-fiber `Settings` while `with_settings` is active (upstream
      `Settings.bind` / `clone_current`), so concurrent fibers cannot observe
      each other's overrides. Route `add_filter`, `add_redaction`,
      `add_path_redaction`, and `dir=` through the getter. Acceptance: two
      interleaved fibers inside `with_settings` see only their own settings;
      full suite green. Closes `settings.rs::Settings.bind` and
      `clone_current`.
- [ ] **6.13 Ledger hygiene for internal-shape rows** — reclassify
      `SnapshotAssertionContext*`, `SnapshotValue*`, `InlineValue`,
      `Snapshot`, `Snapshot.from_components`, and `Snapshot.module_name` as
      `ported`/`skipped` with a one-line rationale (single-pass function API,
      String/Bytes values, content-only `.golden` files, user-set group
      prefix) so `partial` reaches 0. Document the shape divergence under
      **Intentional divergences** and refresh the counts.

---

## Summary

| Phase | Feature | Priority | Effort | Status |
|-------|---------|----------|--------|--------|
| 1.1   | Diff display in review | High | Medium | ✅ Done |
| 1.2   | Skip operation | High | Small | ✅ Done |
| 1.3   | Batch ops in TUI | High | Small | ✅ Done |
| 1.4   | Source context display | Medium | Medium | ✅ Done |
| 1.5   | Review summary | Medium | Small | ✅ Done |
| 1.6   | Inline diff highlighting | Medium | Small | ✅ Done |
| 1.7   | Help keybinding | Low | Small | ✅ Done |
| 2.1   | Pending reporter | High | Small | ✅ Done |
| 3.1   | CLI binary | Medium | Medium | ✅ Done |
| 4.1   | Inline snapshots | Low | Large | ✅ Done |
| 5.1   | Test runner integration | Low | Small | ✅ Done |
| 5.2   | End-of-run pending reporter | Medium | Small | ✅ Done |
| 6.1   | Settings metadata parity | High | Medium | ✅ Done |
| 6.2   | Snapshot naming | Medium | Small | ✅ Done |
| 6.3   | Strict comparison | Medium | Small | ✅ Closed (no code needed) |
| 6.4   | Redaction helpers + selector grammar | Medium | Medium | ✅ Done |
| 6.5   | Settings and pending helpers | Medium | Small | ✅ Done |
| 6.6   | ANSI and map ordering | Low | Small | ✅ Done |
| 6.7   | Pending snapshot directory | Medium | Small | ✅ Done |
| 6.8   | Unreferenced snapshot policy | Medium | Medium | ✅ Done |
| 6.9   | Redaction key traversal | Medium | Small | ✅ Done |
| 6.10  | Snapshot summary on mismatch | Medium | Small | ✅ Done |
| 6.11  | Info block in the summary | Medium | Small | ⬜ Next |
| 6.12  | Fiber-local settings binding | Medium | Medium | ⬜ Planned |
| 6.13  | Ledger hygiene (internal shapes) | Low | Small | ⬜ Planned |

## Intentional divergences

- **Inline snapshots patch source line-by-line, not via a parser.** Rust uses
  `syn` and insta-ruby uses Prism; Crystal has no stable equivalent, so the
  patcher scans the recorded line for a single matching string literal and
  refuses ambiguous or multi-line edits. Pending inline records live in one
  `<dir>/.golden-inline.json` registry instead of per-file `.pending-snap`
  files, and the review TUI reads that registry directly.
- **Charm's Go `x/exp/golden` is inspiration only.** The parity contract is
  Rust insta, with insta-ruby as a reference; Go behavior is not tracked in the
  ledger.
- **The review TUI is opt-in.** `src/golden.cr` does not require `bubbles`;
  consumers that want `Golden.review!` require `golden/review` (the CLI binary
  does), so the core shard does not force a TUI stack on every user.
- **`prepend_module_to_snapshot` defaults to `false`.** Upstream defaults to
  `true`, which would move every existing explicit-name snapshot into a module
  subdirectory. The setting is implemented and opt-in; separator style follows
  this shard's directory layout (`Module/name`) instead of insta's
  `Module__name` filename prefix.
- **Glob snapshots keep basename names.** Upstream derives a suffix from the
  matched file's common-prefix-relative path; here the per-file snapshot name
  is supplied by the caller and `input_file` records the source path.
- **Binary snapshots stay base64 inside `.golden`.** Upstream stores binary
  payloads in a sibling data file (`foo.snap.png`) described by metadata in
  the snapshot file; Golden's `.golden` files are pure content with sidecar
  metadata, so `Snapshot.build_binary_path` has nothing to name. Converting
  would require a snapshot container format, so those ledger rows are
  `skipped` rather than `missing`.
- **The end-of-run hook reports, it does not buffer.** insta-ruby's suite hooks
  flush in-memory inline updates before reporting; Golden patches inline
  literals immediately (or records pending entries), so `Golden.init` only
  installs a reporter (`Spec.after_suite` when spec is loaded, `at_exit`
  otherwise). Disable it with `GOLDEN_REPORT_PENDING=0`; the report is
  advisory and never changes the exit status.
- **Only JSON object keys are redactable.** Upstream supports structured map
  keys (structs/tuples) through nested `$key` selectors; Crystal's JSON model
  keys are strings, so `.hm.$key` rewrites the string key and non-string
  replacements are stringified.
- **Unreferenced detection walks the snapshot dir, not packages.** cargo-insta
  walks every workspace package and skips files that do not look like insta
  snapshots; Golden has no workspace concept, so it walks `Golden.dir` for
  `*.golden` files and reads the same references-file protocol. Environment
  names accept a `GOLDEN_` alias (`GOLDEN_SNAPSHOT_REFERENCES_FILE`,
  `GOLDEN_UNREFERENCED`) with upstream's `INSTA_` names as fallbacks.
- **Pending snapshots can live outside the snapshot tree.** `GOLDEN_PENDING_DIR`
  (with upstream's `INSTA_PENDING_DIR` as a fallback name) mirrors the path
  relative to the snapshot dir instead of cargo-insta's workspace-relative
  mapping, because Golden has no cargo workspace concept.
- **`sort_maps` applies to JSON only.** Upstream sorts the content model before
  emitting JSON or YAML; here `assert_json_snapshot` sorts parsed object keys
  and YAML snapshots keep their emitted order.
- **Diff rendering: `similar` by default, external tool optional.** Mismatch
  messages and the review TUI render unified diffs with `similar`; setting
  `GOLDEN_DIFF_TOOL` (or `INSTA_DIFF_TOOL`) delegates rendering to an external
  tool such as `delta`, falling back to the built-in diff when it fails.
- **There is no `require_full_match` mode.** Upstream compares metadata inside
  the snapshot file when `INSTA_REQUIRE_FULL_MATCH` is set; Golden stores
  metadata in a sidecar and always compares normalized content exactly, so the
  mode has nothing extra to enforce.

