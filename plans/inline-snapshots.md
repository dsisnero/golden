# Inline Snapshots Design (Phase 4.1)

Status: design complete; 4.1b (registry/runtime) and 4.1c (patcher/accept)
implemented. CLI and review integration are still pending, so inline ledger
rows stay `partial` until 4.1d/4.1e land.

## Goal

Store the expected snapshot inline in the spec source, like insta's inline
snapshots, instead of a `.golden` file:

```crystal
it "renders the greeting" do
  Golden.assert_inline_snapshot(render("world"), %("hello world"))
end
```

An empty literal (`""`) means "fill this in": the runtime records the value and
the next accept updates the source.

## Runtime behavior

1. Normalize the produced value with `normalize_inline`: strip the common
   indentation of non-empty lines, drop leading/trailing blank lines, and keep a
   single trailing newline only when the content is multi-line.
2. Compare with the decoded literal using the same comparator settings as file
   snapshots (`compare_outputs`).
3. On match, do nothing.
4. On mismatch:
   - Upsert `{file, line, name, old, new, created_at}` in
     `<Golden.dir>/.golden-inline.json`, one entry per `file:line`.
   - If `GOLDEN_UPDATE=1` (or `Golden.update = true`), patch the source
     immediately and pass. `GOLDEN_FORCE_PASS=1` suppresses the failure but
     leaves the source unchanged.
   - Otherwise raise with the diff and a hint to run `golden inline-accept`.
5. Duplicate guard: recording the same `file:line` twice in one run raises
   unless `Golden.allow_duplicates` is active. This mirrors
   `prevent_inline_duplicate`.

## Source patcher

Crystal has no stable equivalent of Rust's `syn` or Ruby's Prism, so the patcher
is line-based and conservative:

- Scan only the recorded line for string-literal tokens: `"..."` and `%()`
  style literals. Decode each token's value.
- Select exactly one token whose decoded value equals the old expected value.
  Zero or multiple matches abort the patch with a clear message and leave the
  pending entry in place.
- Serialize the new value as a double-quoted Crystal literal, escaping `\`,
  `"`, tabs, and control characters. Multi-line values are refused (use a file
  snapshot instead).
- Write atomically (temp file + rename) and preserve the original line endings.
- Refuse to patch files outside the project root.
- Never patch when the invocation is split across lines; report it instead.

## CLI

| Command | Behavior |
| --- | --- |
| `golden inline-pending` | list pending inline records (`--json` supported) |
| `golden inline-accept` | patch every pending record that can be patched safely |
| `golden inline-reject` | drop the pending registry |
| `golden review` | TUI integration is a follow-up sub-item |

## Sub-items

| Id | Scope |
| --- | --- |
| 4.1a | this design (done) |
| 4.1b | done: pending registry, runtime compare/record, duplicate guard |
| 4.1c | done: source patcher, `GOLDEN_UPDATE` auto-accept, accept/reject API |
| 4.1d | CLI commands |
| 4.1e | review TUI integration |

## Tests

- Patcher: replaces a single literal in a temp file, refuses ambiguous matches,
  refuses multi-line values, and leaves the file untouched on failure.
- Runtime (4.1b): mismatch records a pending entry and the duplicate
  `file:line` guard raises. (4.1c) `GOLDEN_UPDATE=1` patches and passes;
  ambiguous, multi-line, or out-of-root patches fail and keep the entry.
- Registry: upsert replaces an older entry for the same `file:line`;
  accept/reject clears entries.
- Optional end-to-end: generate a temporary spec file and run `crystal spec` on
  it, skipped in CI if the toolchain is unavailable.

## Divergences

- Pending inline snapshots live in one `.golden-inline.json` registry instead of
  per-file `.pending-snap` files.
- Source patching is line-based and refuses ambiguous edits; it does not attempt
  a full Crystal parse.
- Inline snapshots and file snapshots share the metadata/comparator settings but
  inline values are never written to `.golden.meta` sidecars.

## Ledger mapping

As sub-items land, update `plans/inventory/rust_port_inventory.tsv`:

- `snapshot.rs::class::PendingInlineSnapshot` and its methods → `ported`/`partial`
  with the registry and patcher refs.
- `snapshot.rs::function::{leading_space,min_indentation,legacy_inline_normalize,normalize_inline,normalized_of_literal}`
  → `ported` once normalization exists.
- `runtime.rs::{class::InlineValue,function::prevent_inline_duplicate}` → `ported`
  once the runtime guard exists.
