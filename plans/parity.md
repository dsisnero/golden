# Parity Plan: Crystal Golden vs Rust/Ruby insta

## Where we are

- **Current focus:** Phase 6.3 — strict comparison
  (`DefaultComparator.matches_fully`, `require_full_match`).
- **Next up:**
  1. 6.3 strict comparison: `require_full_match` semantics and trailing-newline
     handling.
  2. 6.4 redaction helpers plus the full path-selector grammar (the current
     `partial` rows).
  3. 6.5 pending lifecycle: `clear_*`, `remove_*`, cleanup helpers.
  4. 6.6 ANSI stripping and map ordering.
  5. 4.1 inline snapshots (source patching; needs a design).
- **Status by area:**
  - Review TUI (Phase 1): complete
  - Pending reporter (Phase 2): complete
  - CLI binary (Phase 3): complete
  - Test runner integration (Phase 5.1): complete
  - Settings metadata (Phase 6.1): complete
  - Snapshot naming (Phase 6.2): complete
  - Inline snapshots (Phase 4.1): not started
  - Rust parity inventory: bootstrapped — 554 rows (71 `ported`, 30 `partial`,
    64 `missing`, 389 `skipped`)
  - Ruby ledger: not tracked (`vendor/insta-ruby` is a reference only)
- **Scoping notes / gotchas:**
  - Upstream pins: `vendor/insta` `1.48.0` (`3d62572`), `vendor/insta-ruby`
    `v0.3.0` (`500434b`). `vendor/x` (Charm Go) is declared but not checked out
    and is not a parity target.
  - Ledger scope is `insta/src,insta/tests` with `tree-sitter` discovery. Keep
    that scope/parser or every id churns.
  - 389 rows are `skipped` because they are insta's content/serialization
    engine (vendored YAML parser, content scanner/emitter) or cargo/nextest
    workspace internals; Crystal replaces those with stdlib or does not expose
    them. Do not "fix" those rows into `missing`.
  - `shard.yml` and `Golden::VERSION` still say `0.2.0` while `CHANGELOG.md`
    describes `0.3.0`; bump both at the next release.
- **Last commit:** snapshot naming (parent `a873f36`).
- **Gates:** `make lint` pass; `make test` pass (190 examples); `make inventory`
  pass (554 items tracked, tree-sitter backend).

Keep this block accurate after every feature: the next session reads it first
(see `AGENTS.md` → **How to resume**).

## Current Status

Golden has **feature parity** with Rust/Ruby insta on snapshot fundamentals and
the review TUI. All 6 quick wins and 3 Phase 1 features are implemented (skip,
batch ops, g/G navigation, help overlay, review summary, pending reporter, diff
display, source context, inline word-level highlighting).

The Rust ledger now measures symbol-level parity: 554 scoped declarations, of
which 71 are `ported`, 30 `partial`, 64 `missing`, and 389 `skipped` (insta's
content/serialization engine and cargo internals). Phase 6 turns the `missing`
and `partial` groups into features; inline snapshots (Phase 4.1) remain the
largest single gap.

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

### 4.1 Add inline snapshot macro

**Problem:** No inline snapshot support (snapshot value stored in source code).

**Required:**
- `assert_inline_snapshot(value, @"expected")` macro — replaces inline content on accept
- `match_inline_snapshot(value)` — auto-generates inline content
- Cumbersome in Crystal due to macro limitations — inline snapshot strings stored in source file

**Approach:**

In Crystal, inline snapshots mean the expected value is embedded in the source code:

```crystal
Golden.assert_inline_snapshot(compute_result, %("expected output"))
```

On first run, the macro auto-fills the string literal:
```crystal
Golden.assert_inline_snapshot(compute_result, %("computed output"))
```

**Pending storage:** JSON file in snapshot dir tracking `{file, line, content, old_content}`.
**File patcher:** Rewrite source file lines around the assertion call.

**Depends:** Crystal macro system, `Crystal::AST` (or regex-based source patching).
**Complexity:** High. Rust uses `syn` parser, Ruby uses `Prism` parser. Crystal has no equivalent parser library — may need regex-based patching or a `Crystal::Compiler` API.

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
- [ ] **6.3 Strict comparison** — `DefaultComparator.matches_fully`,
      `require_full_match`, and trailing-newline behavior
      (`comparator.rs`, `output.rs`, `runtime.rs`).
- [ ] **6.4 Redaction helpers and selector grammar** — `dynamic_redaction`,
      `rounded_redaction`, `sorted_redaction`, plus the full `Selector` grammar
      (ranges, struct/seq selectors). Closes the `partial` redaction rows.
- [ ] **6.5 Pending lifecycle** — `clear_filters` / `clear_redactions`, the
      `remove_*` settings helpers, `cleanup_passing`, and
      `cleanup_previous_pending_binary_snapshots`.
- [ ] **6.6 ANSI and map ordering** — `strip_ansi_escape_codes`, `sort_maps`,
      and `sort_selector`.

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
| 4.1   | Inline snapshots | Low | Large | ❌ Pending |
| 5.1   | Test runner integration | Low | Small | ✅ Done |
| 6.1   | Settings metadata parity | High | Medium | ✅ Done |
| 6.2   | Snapshot naming | Medium | Small | ✅ Done |
| 6.3   | Strict comparison | Medium | Small | ❌ Pending |
| 6.4   | Redaction helpers + selector grammar | Medium | Medium | ❌ Pending |
| 6.5   | Pending lifecycle | Medium | Small | ❌ Pending |
| 6.6   | ANSI and map ordering | Low | Small | ❌ Pending |

## Intentional divergences

- **Inline snapshots are deferred, not stubbed.** Rust uses `syn` and
  insta-ruby uses Prism to patch source files; Crystal has no stable equivalent,
  so the API waits for a reviewed design instead of shipping a regex hack.
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

