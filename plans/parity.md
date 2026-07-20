# Parity Plan: Crystal Golden vs Rust/Ruby insta

## Current Status

Golden has **near-full parity** with Rust/Ruby insta on snapshot fundamentals and review TUI. All 6 quick wins and 3 Phase 1 features are implemented (skip, batch ops, g/G navigation, help overlay, review summary, pending reporter, diff display, source context, inline word-level highlighting). Remaining gaps in **Inline Snapshots**, **CLI**, and **Test Runner Integration**.

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
| 3.1   | CLI binary | Medium | Medium | ❌ Pending |
| 4.1   | Inline snapshots | Low | Large | ❌ Pending |
| 5.1   | Test runner integration | Low | Small | ❌ Pending |
