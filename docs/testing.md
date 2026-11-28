# Testing

## Commands

```bash
make test           # crystal spec
make test-examples  # crystal spec examples
make lint           # ameba src spec examples
make format-check   # crystal tool format --check src spec examples
GOLDEN_UPDATE=1 crystal spec   # rewrite baselines (review the diff!)
```

The gate is `make lint && make test`. Both must be green before a commit.

## Layout

| Path | Purpose |
| --- | --- |
| `spec/golden_spec.cr` | core `require_equal` behavior and update modes |
| `spec/golden_features_spec.cr` | filters, redactions, metadata, glob, serializers, cleanup, config |
| `spec/golden_cli_spec.cr` | `Golden::CLI.dispatch` command output |
| `spec/golden_review_spec.cr` | `ReviewItem` diff/context and `ReviewModel` transitions |
| `spec/spec_helper.cr` | requires `spec` + the shard and calls `Golden.init` |
| `testdata/` | committed fixtures read by the specs |
| `examples/` | runnable examples executed as specs |

## Rules

1. **Port the upstream test first.** When matching an `insta` behavior, find the
   corresponding test under `vendor/insta/src/**` (or
   `vendor/insta-ruby/spec`) and translate its intent. Do not weaken
   assertions to fit current behavior; fix the behavior.

2. **Never write into committed `testdata/` from a spec.** Snapshot-writing
   tests use a unique temp directory:

   ```crystal
   temp_dir = File.join(Dir.tempdir, "golden_#{Random::Secure.hex(6)}")
   begin
     Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
       Golden.require_equal("name", "value")
     end
   ensure
     FileUtils.rm_rf(temp_dir)
   end
   ```

   This keeps `git status` clean after `make test`; a dirty fixture means the
   spec is leaking state.

3. **Reset global state.** `Golden.settings` is process-global. Use
   `Golden.with_settings`, and restore `Golden.group` explicitly in
   `before_each` where relevant.

4. **Test the public surface.** Prefer `Golden.assert_*` macros and documented
   API over private helpers; CLI behavior is asserted through
   `Golden::CLI.dispatch` returning a `String`.

5. **No interactive tests.** `Golden.review!` is covered by testing
   `ReviewItem` and `ReviewModel` directly; do not launch the Bubble Tea
   program in specs.

## Pending snapshots during development

A failing comparison writes `<name>.golden.new` and the end-of-run reporter
(installed by `Golden.init`) prints the pending report when the process exits.
Review with:

```bash
crystal build src/golden_cli.cr -o bin/golden
bin/golden review      # or: golden review
bin/golden accept
bin/golden reject
```

`make test-review` runs the suite and then the review TUI. Pending files are
staging state, never commit them.

## CI behavior

`Golden::UpdateMode::Auto` compares strictly when CI is detected (`CI` set to
anything but `false`/`0`/empty, or `TF_BUILD` set), so a new snapshot fails
instead of silently staging a `.golden.new`. Use `GOLDEN_FORCE_PASS=1` only
for exploratory local runs.

Deleting snapshots is CI-hostile, so set `GOLDEN_UNREFERENCED=reject` (or
`unreferenced: reject` in `.golden.yml`) in CI: the end-of-run hook then fails
the run when a snapshot is no longer referenced. `auto` already rejects in CI
and deletes locally.
