# Coding Guidelines

## Formatting and lint

- `crystal tool format src spec examples` is the only formatter; run it before
  every commit (`make format`).
- `ameba src spec examples` is the lint gate (`make lint`). `.ameba.yml`
  excludes `lib/`, `vendor/`, `temp/`, and `spec/`.
- Zero warnings is the baseline. Do not silence a rule in `.ameba.yml` to land a
  change; fix the code or justify the exclusion in the commit message.

## Crystal style

- Two-space indentation, LF endings, final newline (`.editorconfig`).
- Prefer explicit return types on public module methods and on non-trivial
  private helpers, matching the existing `def self.foo(...) : String` style.
- Keep block parameter names at least three characters and meaningful (`io`,
  `path`, `filter_json`); Ameba's `Naming/BlockParameterName` rejects `s`, `p`,
  `sb`, and friends.
- Use `String.build do |io| ... end` rather than repeated concatenation.
- Guard clauses over nesting; `return` early for the empty/absent case.
- Avoid `not_nil!` outside specs. Narrow with `if value = ...?` or an explicit
  `raise`.

## Module layout

- Everything lives under `module Golden`; no top-level helpers.
- `src/golden.cr` owns state via `@@settings`. Mutate it through the public
  setters or `Golden.with_settings` so scope restoration stays automatic.
- `src/golden/cli.cr` must stay side-effect free: return a `String`, print only
  in `src/golden_cli.cr`. This keeps CLI behavior spec-testable.
- `src/golden/review.cr` is the only file that requires `bubbles`; keep the
  core library independent of the TUI.
- Private helpers are `private def self.` and live next to their only caller.

## File and snapshot I/O

- All snapshot writes go through `write_file` (temp file + rename). Do not
  introduce a direct `File.write` on a golden path.
- Metadata is JSON with exactly `name`, `created_at`, `line`; keep the shape
  stable because downstream tooling reads it.
- Treat `.golden.new` as staging state and `.golden.meta` as a sidecar; filters
  that list snapshots must exclude both.

## Public API changes

- The `assert_*` macros are the primary API. Adding an overload must keep
  auto-naming (`ClassName/method_name`, `ClassName/snapshot_at_LINE`) working.
- New settings fields belong on `Golden::Settings` with a default that preserves
  current behavior.
- Document every public addition in `README.md` and `CHANGELOG.md`, and add a
  spec that exercises it through the public surface.

## Tests

- Characterization specs mirror upstream behavior; never weaken an assertion to
  make a refactor pass.
- Specs that write snapshots must use a temporary directory and clean it up
  (`File.join(Dir.tempdir, ...)` + `ensure FileUtils.rm_rf`). Committed fixtures
  under `testdata/` are read-only inputs.
- See [testing.md](testing.md).

## Documentation

- `README.md` describes what the project is and how to use it; it links every
  file in `docs/`.
- Porting notes, upstream pins, and implementation history belong in
  `docs/development.md`, not the README.
- Update `plans/parity.md` and its **Where we are** block in the same commit as
  the feature.
