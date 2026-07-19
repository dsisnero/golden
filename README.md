# golden

A Crystal shard for golden file (snapshot) testing, inspired by [insta](https://github.com/mitsuhiko/insta) and ported from [charmbracelet/x/exp/golden](https://github.com/charmbracelet/x/tree/main/exp/golden).

Golden files contain the expected output of your tests. When you run your tests, the output is compared against the golden file. If they match, the test passes. If they don't, a diff is shown.

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

# Or use the interactive review TUI
crystal run src/golden.cr  # requires bubbles dependency
Golden.review!
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

The `Auto` mode automatically detects CI environments (`CI=true`, `TF_BUILD`) and uses strict comparison.

### Filters & Redactions

Strip dynamic content before comparison:

```crystal
Golden.add_filter(/\d{4}-\d{2}-\d{2}/, "[DATE]")
Golden.add_filter(->(s : String) { s.gsub(/pid: \d+/, "pid: XXX") })

Golden.add_redaction(/token=\w+/, "token=REDACTED")
```

Filters run before comparison, cleaning up timestamps, IDs, paths, etc.

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

### Interactive Review

```crystal
# Launch TUI to review pending snapshots (requires bubbles shard)
Golden.review!
# Keys: y = accept, n = reject, j/k = navigate, q = quit
```

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

### Metadata

```crystal
# Read creation info from .golden.meta sidecar
meta = Golden.snapshot_metadata("my_snapshot")
meta["created_at"]  # RFC 3339 timestamp
meta["name"]        # snapshot name
meta["line"]        # source line number
```

### Config File

Create `.golden.yml` in your project root:

```yaml
update_mode: "auto"
dir: "spec/testdata"
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

Redact specific JSON paths before comparison (jq-style):

```crystal
Golden.add_path_redaction("password", "***")
Golden.add_path_redaction("user.email", "[email]")
Golden.add_path_redaction("users[*].id", "[id]")

# Applied automatically in assert_json_snapshot
output = {"user" => {"email" => "a@b.com", "name" => "test"}}
Golden.assert_json_snapshot("user", output)
# Stores: {"user": {"email": "[email]", "name": "test"}}
```

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

## How It Works

1. `Golden.require_equal` looks for `#{dir}/#{name}.golden`
2. If the golden file doesn't exist (or update mode says so), a pending `.golden.new` is created
3. On comparison, output is processed through redactions → filters, then compared
4. Custom comparators can override the default equality check
5. On mismatch, a unified diff is shown

## Development

```bash
crystal spec
crystal spec examples/
GOLDEN_UPDATE=1 crystal spec
```

## License

MIT
