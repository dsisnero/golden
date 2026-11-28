# golden

A Crystal shard for golden file (snapshot) testing, inspired by
[insta](https://github.com/mitsuhiko/insta) and ported from
[charmbracelet/x/exp/golden](https://github.com/charmbracelet/x/tree/main/exp/golden).

Golden files contain the expected output of your tests. When you run your tests,
the output is compared against the golden file. If they match, the test passes.
If they don't, a diff is shown.

## Installation

Add to your `shard.yml`:

```yaml
dependencies:
  golden:
    github: dsisnero/golden
```

Run `shards install`.

## Quick Start

```crystal
require "spec"
require "golden"

describe "MyClass" do
  it "produces expected output" do
    output = MyClass.new.run

    # Compare with testdata/MyClass/produces_expected_output.golden
    Golden.assert_snapshot("MyClass/produces_expected_output", output)

    # Or use auto-naming from class/method name:
    Golden.assert_snapshot(output)
  end
end
```

First run creates pending `.golden.new` files. Review them:

```bash
# Accept all pending snapshots
GOLDEN_UPDATE=1 crystal spec

# CLI binary — review pending snapshots interactively
golden review

# Accept/reject all at once
golden accept
golden reject

# List pending, check status, clean orphans
golden pending --json
golden status
golden clean --dry-run

# Run tests then launch review (single command)
golden test-review
make test-review
```

## Features

### Macros (Recommended API)

| Macro | Description |
|-------|-------------|
| `assert_snapshot(name, value)` | String snapshot with explicit name |
| `assert_snapshot(value)` | Auto-named from class/method |
| `assert_json_snapshot(name, value)` | Pretty-printed JSON (calls `to_pretty_json`) |
| `assert_yaml_snapshot(name, value)` | YAML output (calls `to_yaml`) |
| `assert_binary_snapshot(name, bytes)` | Base64-encoded binary data |

All macros support auto-naming from `ClassName/method_name` or fallback to `ClassName/snapshot_at_LINE`.

### Update Modes

```crystal
# Automatic (default): creates .golden.new on mismatch, compares on CI
Golden.settings.update_mode = Golden::UpdateMode::Auto

# Always update golden files
Golden.update = true  # or GOLDEN_UPDATE=1 env var
Golden.settings.update_mode = Golden::UpdateMode::Always

# Never update — fail hard on mismatch
Golden.settings.update_mode = Golden::UpdateMode::No

# Create .golden.new only if no golden file exists
Golden.settings.update_mode = Golden::UpdateMode::New

# Create golden on first run, .golden.new on mismatch
Golden.settings.update_mode = Golden::UpdateMode::Unseen
```

The `Auto` mode automatically detects CI environments (`CI=true`, `TF_BUILD`)
and uses strict comparison.

### Filters & Redactions

Strip dynamic content before comparison:

```crystal
Golden.add_filter(/\d{4}-\d{2}-\d{2}/, "[DATE]")
Golden.add_filter(->(s : String) { s.gsub(/pid: \d+/, "pid: XXX") })

Golden.add_redaction(/token=\w+/, "token=REDACTED")
```

Filters run before comparison, cleaning up timestamps, IDs, paths, etc.

### Output Normalization

```crystal
Golden.settings.strip_ansi_escape_codes = true  # drop terminal color codes
Golden.settings.sort_maps = true                # sort JSON object keys
Golden.settings.allow_empty_glob = true         # glob_snapshots may match nothing
```

All three are accepted by `Golden.with_settings`. `strip_ansi_escape_codes`
runs before redactions and filters; `sort_maps` affects
`assert_json_snapshot` output (YAML snapshots keep their emitted order); a
`glob_snapshots` pattern that matches nothing raises unless
`allow_empty_glob` is set.

### Custom Comparators

```crystal
# Fuzzy comparison with numeric tolerance
Golden.settings.comparator = Golden::FuzzyComparator.new(0.001)

# Or implement your own:
class MyComparator
  include Golden::Comparator
  def matches?(expected : String, actual : String) : Bool
    # custom logic
  end
end
```

### Scoped Settings

```crystal
Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: "spec/testdata") do
  Golden.assert_snapshot("test", output)
end
# Settings restored after block
```

### Group Prefix

```crystal
Golden.group = "API"
Golden.assert_snapshot("users", output)
# Stored in: testdata/API/users.golden
```

### Snapshot Naming

```crystal
Golden.settings.snapshot_suffix = "unit"
# name@unit.golden

Golden.settings.prepend_module_to_snapshot = true
# Module/name.golden (the module comes from the assertion macro)
```

`Golden.with_settings` accepts both settings. `prepend_module_to_snapshot`
defaults to `false` in this shard (upstream insta defaults to `true`) so that
existing snapshot paths keep working; enable it to opt into module-prefixed
names.

### Duplicate Assertions

Repeated assertions with the same name are allowed. Wrap them in
`Golden.allow_duplicates` when a loop is expected to produce identical content;
a repeated name with different content raises a mismatch error:

```crystal
Golden.allow_duplicates do
  items.each { |item| Golden.assert_snapshot("item", render(item)) }
end
```

`Golden.allow_duplicates?` reports whether the block is active.

### Glob Batch Testing

Test against multiple input files:

```crystal
Golden.glob_snapshots("testdata/inputs/*.txt") { |path| File.read(path) }
# Creates a snapshot per file, named by basename
```

### Pending Snapshots

```crystal
# List pending
pending = Golden.pending_snapshots

# Accept all
Golden.accept_all!

# Reject all
Golden.reject_all!
```

Set `GOLDEN_PENDING_DIR` (or upstream's `INSTA_PENDING_DIR`) to write pending
snapshots outside the snapshot tree, mirroring each snapshot's relative path
under that directory. Accepting or rejecting moves/deletes them back through
the same mapping, and `pending_snapshots`, `status`, and `golden review` all
discover them there.

`Golden.init` installs an end-of-run reporter (like insta-ruby's
`after(:suite)` / `after_run` hooks): after the spec suite — or at process
exit outside specs — it prints any pending file and inline snapshots plus a
`golden review` hint to stderr. The report is advisory — it never changes the
exit status. Set `GOLDEN_REPORT_PENDING=0` to disable it, or install it
explicitly with `Golden.install_exit_reporter!`.

### Interactive Review

```crystal
# Launch TUI to review pending snapshots (requires bubbles shard)
Golden.review!
```

| Key | Action |
|-----|--------|
| `y` / `n` | Accept / reject current snapshot |
| `s` | Skip (leave as `.golden.new`) |
| `j` / `k` | Navigate down / up |
| `g` / `G` | Go to top / bottom |
| `d` | Toggle unified diff display |
| `i` | Toggle source context (file, line, code) |
| `A` / `R` / `S` | Accept / reject / skip all remaining |
| `?` | Toggle help overlay |
| `q` | Quit (shows review summary) |

Inline word-level diff highlights insertions (green), deletions (red), and
changed segments (bold+underline).

### Orphan Cleanup

```crystal
# Track accessed snapshots during a test run, then find orphans
Golden.reset_tracking!
# ... run tests ...
orphans = Golden.unreferenced_snapshots

# Remove orphans (with dry-run support)
Golden.cleanup!(dry_run: true)   # preview
Golden.cleanup!                   # actually delete
```

Post-run policy (the `cargo insta test --unreferenced` equivalent) is also
available. Set `GOLDEN_UNREFERENCED` (or config `unreferenced:`) to `auto`,
`reject`, `delete`, `warn`, or `ignore` (default). The end-of-run hook then
applies it: `auto` deletes locally and rejects in CI, `reject` fails the run,
`delete` removes the files (and their metadata), and `warn` only prints.

```bash
GOLDEN_UNREFERENCED=reject crystal spec
golden test-review --unreferenced=delete
```

Assertions append each touched snapshot to
`GOLDEN_SNAPSHOT_REFERENCES_FILE` (upstream's
`INSTA_SNAPSHOT_REFERENCES_FILE` is accepted too) when set, so a runner in
another process can compare it against the snapshot tree.

### Metadata

Every accepted snapshot gets a `.golden.meta` JSON sidecar. Assertion macros
record the source line, source file, and expression automatically; the remaining
fields come from settings:

```crystal
Golden.with_settings(description: "users list", info: "generated from API") do
  Golden.assert_snapshot("users", output)
  # stores expression: "output", source_file: "spec/users_spec.cr", line: 12,
  # description: "users list", info: "generated from API"
end

# Read creation info from the sidecar
meta = Golden.snapshot_metadata("my_snapshot")
meta["created_at"]    # RFC 3339 timestamp
meta["name"]          # snapshot name
meta["line"]          # source line number
meta["source_file"]   # source file relative to the project root
meta["expression"]    # expression captured by the macro
meta["description"]   # optional human description
meta["info"]          # optional free-form info text
meta["input_file"]    # input file, set by glob_snapshots or settings
```

Set `omit_expression: true` to keep the captured expression out of the sidecar.
Pending snapshots keep their metadata in `.golden.new.meta`; accepting them
promotes the sidecar along with the snapshot.

### Inline Snapshots

Store the expected value next to the assertion instead of in a `.golden` file:

```crystal
Golden.assert_inline_snapshot(output, %("expected"))
```

A mismatch records a pending entry in `<Golden.dir>/.golden-inline.json`
(default `testdata/`) and fails the spec. Review and accept with the library API
or the CLI:

```crystal
Golden.pending_inline_snapshots       # records with file, line, old, and new
Golden.accept_inline!(dry_run: true)  # preview
Golden.accept_inline!                 # patch safely patchable entries
Golden.reject_inline_snapshots!       # drop all pendings
```

```bash
golden inline-pending --json
golden inline-accept --dry-run   # preview
golden inline-accept             # add --root DIR for workspaces
golden inline-reject
golden review                    # inline pendings appear in the same list
```

In `golden review`, accepting an inline entry patches its source literal and
drops the registry entry, rejecting drops the entry without touching source,
and skipping keeps it. Pass `--root DIR` when the source paths are relative to
a workspace root other than the current directory.

Running with `GOLDEN_UPDATE=1` (or `Golden.update = true`) patches inline
literals automatically. The patcher only rewrites a single-line `"..."` or
`%(...)` literal and refuses ambiguous matches, multi-line values, or files
outside the project root, leaving the pending entry in place.

### Config File

Create `.golden.yml` in your project root:

```yaml
update_mode: "auto"
dir: "spec/testdata"
unreferenced: "warn"
filters:
  - pattern: "\\d{4}-\\d{2}-\\d{2}"
    replacement: "[DATE]"
redactions:
  - pattern: "token=\\w+"
    replacement: "token=REDACTED"
```

```crystal
# Auto-load from project root on startup
Golden.init  # already calls auto_configure!

# Or load explicitly
Golden.configure_with(".golden.yml")
```

### Force Pass Mode

Skip test failures for new snapshots (writes `.golden.new` instead):

```bash
GOLDEN_FORCE_PASS=1 crystal spec
```

### Status Reporting

Inspect snapshot state at a glance:

```crystal
status = Golden.status
status["snapshots"]  # total .golden files
status["pending"]    # .golden.new files
status["metadata"]   # .golden.meta sidecars
status["orphans"]    # unreferenced golden files
```

### Serializers

Register named serializers for custom output processing:

```crystal
Golden.register_serializer(:upcase, ->(v : String) { v.upcase })

Golden.with_settings(serializer: :upcase) do
  Golden.assert_snapshot("test", "hello")  # stores "HELLO"
end
```

### Path-Based Redactions

Redact specific JSON paths before comparison (jq-style selectors):

```crystal
Golden.add_path_redaction("password", "***")
Golden.add_path_redaction("user.email", "[email]")
Golden.add_path_redaction("users[*].id", "[id]")

# Selector syntax
Golden.add_path_redaction("users[0:2].id", "[id]")   # range
Golden.add_path_redaction("users[-1:].id", "[id]")    # trailing range
Golden.add_path_redaction("users.*.id", "[id]")       # single wildcard
Golden.add_path_redaction("**.token", "[token]")      # deep wildcard
Golden.add_path_redaction(%(user["full-name"]), "[name]")
Golden.add_path_redaction("settings.$key", "[setting]") # map keys
Golden.add_path_redaction("**.$key", "[key]")          # nested map keys

# Computed replacements
Golden.add_dynamic_redaction("user.email") { |_value, path| JSON::Any.new("<#{path}>") }
Golden.add_path_redaction("total", Golden.rounded_redaction(2))
Golden.add_path_redaction("tags", Golden.sorted_redaction)

# Applied automatically in assert_json_snapshot
output = {"user" => {"email" => "a@b.com", "name" => "test"}}
Golden.assert_json_snapshot("user", output)
# Stores: {"user": {"email": "[email]", "name": "test"}}
```

Selectors accept comma-separated alternatives and `.` for the document root.
Dynamic redactions receive the matched value and its dotted path (for example
`.user.email`). The synthetic `$key` segment targets object keys, matching
upstream's map traversal; dynamic key redactions receive the key text and a
path ending in `.$key`. Redactions run in registration order, so register value
selectors before key rewrites that would change their path.

## Configuration

```crystal
# Default directory for golden files
Golden.dir = "spec/testdata"

# Enable update mode
Golden.update = true

# Or use environment variable
# GOLDEN_UPDATE=1 crystal spec

# Initialize (checks GOLDEN_UPDATE, loads .golden.yml)
Golden.init
```

### Resetting Settings

```crystal
Golden.clear_filters
Golden.clear_redactions        # also clears path redactions
Golden.remove_description
Golden.remove_info
Golden.remove_input_file
Golden.remove_snapshot_suffix
Golden.settings.has_info?      # => false after remove_info
```

## How It Works

1. `Golden.require_equal` looks for `#{dir}/#{name}.golden`
2. If the golden file doesn't exist (or update mode says so), a pending
   `.golden.new` is created
3. On comparison, output is processed through redactions → filters, then compared
4. Custom comparators can override the default equality check
5. On mismatch, the error starts with the snapshot summary
   (`Snapshot file`, `Snapshot`, `Source: path:line`, `Input file`) followed
   by a unified diff

## Development

```bash
make install        # shards install
make format         # crystal tool format src spec examples
make lint           # ameba src spec examples
make test           # crystal spec
make test-examples  # crystal spec examples
GOLDEN_UPDATE=1 crystal spec   # rewrite baselines
```

## Documentation

- [Resuming work](docs/resuming.md) — start here for a new session
- [Architecture](docs/architecture.md) — modules and snapshot lifecycle
- [Development](docs/development.md) — upstream pins, repo layout, parity work
- [Coding Guidelines](docs/coding-guidelines.md)
- [Testing](docs/testing.md)
- [PR Workflow](docs/pr-workflow.md)
- [Parity plan](plans/parity.md)

## License

MIT
