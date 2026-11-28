# Architecture

`golden` is a single Crystal shard with a small library surface, an interactive
review TUI, and a CLI binary.

## Source layout

```text
src/golden.cr         core: settings, update modes, filters/redactions,
                      comparators, serializers, config, pending lifecycle,
                      macros (assert_*), diff helpers
src/golden/cli.cr     Golden::CLI.dispatch — command parsing and text output
src/golden/review.cr  ReviewItem + InlineReviewItem + ReviewModel (Bubble Tea
                      TUI) and Golden.review!
src/golden_cli.cr     binary entry point (shard.yml target: golden)
examples/             runnable example specs
spec/                 characterization specs mirroring upstream behavior
testdata/             committed fixtures used by the specs
plans/                parity plan and (future) inventory ledgers
vendor/insta          Rust upstream (git submodule, pinned)
vendor/insta-ruby     Ruby upstream reference (git submodule, pinned)
```

## Snapshot lifecycle

A snapshot name resolves to `#{dir}/#{group}/#{name}.golden` where `dir`
defaults to `testdata`. Three sibling artifacts exist:

| Path | Meaning |
| --- | --- |
| `<name>.golden` | accepted baseline |
| `<name>.golden.new` | pending candidate written on mismatch |
| `<name>.golden.meta` | JSON sidecar: `name`, `created_at`, `line` |

`Golden.require_equal` is the single write path used by all macros. It:

1. runs the output through path redactions (JSON), redactions, then filters;

2. applies the serializer for the current settings, if any;

3. branches on the effective update mode:

   | Mode | Behavior |
   | --- | --- |
   | `Always` | overwrite `.golden` |
   | `No` | strict compare, raise on mismatch |
   | `New` | write `.golden.new` only when no baseline exists |
   | `Unseen` | `.golden` on first run, `.golden.new` on mismatch |
   | `Auto` | strict in CI (`CI=true`, `TF_BUILD`), otherwise `Unseen`-style staging |

4. compares with the configured `Comparator` (default exact string equality);

5. on mismatch raises with a unified diff unless `GOLDEN_FORCE_PASS=1`.

When `GOLDEN_PENDING_DIR` (or `INSTA_PENDING_DIR`) is set, step 3 writes the
pending candidate under that directory instead, at the snapshot's path
relative to `Golden.dir`; `promote_pending!` maps it back through
`golden_path_for_pending` before moving it, and `discard_pending!` deletes the
pending file and its sidecar where they are.

Writes are atomic: content goes to a temporary file in the target directory and
is then renamed over the destination, so an interrupted run cannot leave a
partially written baseline.

## Review TUI

`ReviewItem` precomputes everything a review needs: new content, old content
when a baseline exists, a unified diff (via the `similar` shard), an inline
word-level diff, and metadata-derived source context. `InlineReviewItem` does
the same for records in the inline-pending registry; accepting one patches its
source literal through `Golden.accept_inline_entry`. `ReviewModel` is a
Bubble Tea model that presents the list, a diff viewport, a source-context
overlay, and a help overlay. `Golden.review!` builds the model (file pendings
and inline pendings in one list), runs the program, applies
accept/reject/skip decisions, and returns `Array(Tuple(String, String))` of
`{name, action}`. A decision is recorded once per item, so a failed inline
patch reports `failed: ...` without retrying or repeating in the same session.

`bubbles` is a development dependency that the TUI requires; the core library
and the non-TUI CLI commands work without it.

## CLI

`Golden::CLI.dispatch(args)` returns a `String` (printed by `src/golden_cli.cr`)
so every command is testable without a subprocess. Commands: `review`,
`accept`, `reject`, `pending`, `status`, `clean`, `show`, `test-review`.
Shared flags: `--snapshot DIR`, `--json`, `--dry-run`, `--spec-cmd CMD`.

## Testing surface

Specs are characterization tests for upstream behavior. They deliberately cover
the same public API as the Rust crate: update modes, filters and redactions,
metadata sidecars, orphan detection, glob batches, serializers, path
redactions, and review-state transitions. See [testing.md](testing.md).

## Divergences from upstream

- Inline snapshots use a line-based patcher instead of a parser. Rust uses the
  `syn` parser and insta-ruby uses Prism; Crystal has no equivalent source
  patcher, so the guardrails are specified in
  [inline-snapshots.md](../plans/inline-snapshots.md).
- The Rust CLI subcommands (`cargo insta ...`) map to the `golden` binary;
  `test-review` is the equivalent of `cargo insta test --review`.
- Charm's Go `x/exp/golden` inspired the original API but is not a parity
  target and is not vendored.
