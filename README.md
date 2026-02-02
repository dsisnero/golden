# golden

A Crystal shard for golden file testing, ported from [charmbracelet/x/exp/golden](https://github.com/charmbracelet/x/tree/main/exp/golden).

Golden files contain the raw expected output of your tests, which can contain control codes and escape sequences. When comparing test output, `Golden` escapes control codes and sequences before comparing with golden files.

## Installation

1.  Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     golden:
       github: dsisnero/golden
   ```

2.  Run `shards install`

## Usage

```crystal
require "spec"
require "golden"

describe "MyClass" do
  it "produces expected output" do
    output = MyClass.new.generate_output

    # Compare with testdata/MyClass/produces_expected_output.golden (default)
    Golden.require_equal("MyClass/produces_expected_output", output)

    # Or specify custom directory
    Golden.require_equal("MyClass/produces_expected_output", output,
                        test_data_dir: "spec/testdata")

    # Or use spec directory detection
    if spec_testdata = Golden.spec_test_data_dir
      Golden.require_equal("MyClass/produces_expected_output", output,
                          test_data_dir: spec_testdata)
    end
  end
end
```

### How it works

1.  `Golden.require_equal(test_name, output, test_data_dir = nil)` looks for a golden file at `#{test_data_dir || Golden.dir}/#{test_name}.golden`
2.  If `Golden.update?` is `true`, the golden file is updated with the current output
3.  Otherwise, the output is compared with the golden file content
4.  If they differ, a diff is shown and the test fails

### Configuration

```crystal
# Set the directory for golden files (default: "testdata")
Golden.dir = "spec/testdata"

# Enable update mode (writes golden files instead of comparing)
Golden.update = true

# Or use environment variable
# GOLDEN_UPDATE=1 crystal spec

# Initialize from environment variable (call in spec_helper)
Golden.init  # Checks GOLDEN_UPDATE environment variable
```

### Directory Detection

Golden can help locate your spec directory and test data:

```crystal
# Find the spec directory (searches upward from current dir)
spec_dir = Golden.find_spec_dir
# => "path/to/your/project/spec"

# Get the test data directory within spec (spec/testdata)
spec_testdata = Golden.spec_test_data_dir
# => "path/to/your/project/spec/testdata"

# Use custom directory for a specific test
Golden.require_equal("test_name", output, test_data_dir: "custom/path")

# Or use the spec test data directory
if spec_testdata = Golden.spec_test_data_dir
  Golden.require_equal("test_name", output, test_data_dir: spec_testdata)
end
```

The `test_data_dir` parameter in `require_equal` overrides `Golden.dir` for that call.

### Updating golden files

There are several ways to update golden files:

1.  **In your spec file:**

   ```crystal
   describe "MyClass" do
     before_each do
       Golden.update = true  # Update all golden files in this describe
     end

     it "produces output" do
       Golden.require_equal("test", "output")
     end
   end
   ```

2.  **Using environment variable:**

   ```bash
   GOLDEN_UPDATE=1 crystal spec
   ```

3.  **Globally in spec helper:**

   ```crystal
   # spec/spec_helper.cr
   require "golden"

   if ENV["GOLDEN_UPDATE"]? == "1"
     Golden.update = true
   end
   ```

### File permissions

Golden files are created with permissions `0o600` (read/write for owner only) and directories with `0o750`, matching the behavior of the Go version.

### Comparison details

*   Control codes and escape sequences are escaped using Crystal's `String#inspect`
*   Windows line endings (`\r\n`) are normalized to `\n` on non-Windows systems
*   Both `String` and `Bytes` output are supported
*   Diffs are generated using the [similar](https://github.com/dsisnero/similar.cr) library with unified diff format

## Development

```bash
# Run tests
crystal spec

# Run tests with update mode
GOLDEN_UPDATE=1 crystal spec
```

## Porting from Go

This shard ports the functionality from `charmbracelet/x/exp/golden`:

| Go Function | Crystal Equivalent |
|------------|-------------------|
| `golden.RequireEqual(tb, out)` | `Golden.require_equal(test_name, output)` |
| `-update` flag | `GOLDEN_UPDATE=1` environment variable or `Golden.update = true` |

## Contributing

1.  Fork it (<https://github.com/dsisnero/golden/fork>)
2.  Create your feature branch (`git checkout -b my-new-feature`)
3.  Commit your changes (`git commit -am 'Add some feature'`)
4.  Push to the branch (`git push origin my-new-feature`)
5.  Create a new Pull Request

## Contributors

*   [Dominic Sisneros](https://github.com/dsisnero) - creator and maintainer
