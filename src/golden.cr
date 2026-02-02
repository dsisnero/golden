# Golden provides a helper function to assert the output of tests.
#
# Golden files contain the raw expected output of your tests, which can
# contain control codes and escape sequences. When comparing the output of
# your tests, `Golden.require_equal` will escape the control codes and sequences
# before comparing the output with the golden files.
#
# You can update the golden files by setting `Golden.update = true` in your tests,
# or by setting the environment variable `GOLDEN_UPDATE=1`.
#
# Example:
# ```
# require "spec"
# require "golden"
#
# describe "MyClass" do
#   it "produces expected output" do
#     output = MyClass.new.generate_output
#     # Uses Golden.dir (default: "testdata")
#     Golden.require_equal("MyClass/produces_expected_output", output)
#
#     # Or specify custom directory
#     Golden.require_equal("MyClass/produces_expected_output", output,
#       test_data_dir: "spec/testdata")
#
#     # Or use spec directory detection
#     if spec_testdata = Golden.spec_test_data_dir
#       Golden.require_equal("MyClass/produces_expected_output", output,
#         test_data_dir: spec_testdata)
#     end
#   end
# end
# ```
#
# By default this will compare `output` with the contents of `testdata/MyClass/produces_expected_output.golden`.
# If the files differ, a diff will be shown.
require "file_utils"
require "similar"

module Golden
  VERSION = "0.1.0"

  # Flag to update golden files
  @@update = false

  # Directory for golden files
  @@dir = "testdata"

  # Initialize the golden module by checking the `GOLDEN_UPDATE` environment variable.
  # Call this in your spec helper if you want to use environment variable to control updates.
  def self.init
    @@update = ENV["GOLDEN_UPDATE"]? == "1"
  end

  # Set whether golden files should be updated.
  def self.update=(value : Bool)
    @@update = value
  end

  # Check if golden files should be updated.
  def self.update?
    @@update
  end

  # Set the directory where golden files are stored (default: "testdata").
  def self.dir=(dir : String)
    @@dir = dir
  end

  # Get the directory where golden files are stored.
  def self.dir
    @@dir
  end

  # Find the spec directory by searching upward from the current directory
  # for a directory named "spec". Returns nil if not found.
  def self.find_spec_dir(start_dir : String = Dir.current) : String?
    dir = start_dir
    while true
      spec_dir = File.join(dir, "spec")
      if Dir.exists?(spec_dir)
        return spec_dir
      end
      parent = File.dirname(dir)
      break if parent == dir # reached root
      dir = parent
    end
    nil
  end

  # Find the project root directory by searching upward for shard.yml
  def self.find_project_root(start_dir : String = Dir.current) : String?
    dir = start_dir
    while true
      shard_yml = File.join(dir, "shard.yml")
      if File.exists?(shard_yml)
        return dir
      end
      parent = File.dirname(dir)
      break if parent == dir
      dir = parent
    end
    nil
  end

  # Get the test data directory within the spec directory (spec/testdata).
  # Returns nil if spec directory cannot be found.
  def self.spec_test_data_dir : String?
    if spec_dir = find_spec_dir
      File.join(spec_dir, "testdata")
    else
      nil
    end
  end

  # Asserts that the given output matches the golden file for the test.
  #
  # * `test_name` is the name of the test, which will be used to construct the
  #   golden file path: `#{dir}/#{test_name}.golden`
  # * `output` is the actual output to compare, either a String or Bytes
  # * `test_data_dir` optional directory for golden files (overrides Golden.dir)
  #
  # If the output doesn't match the golden file, a diff will be shown and the
  # test will fail.
  #
  # If `Golden.update` is `true`, the golden file will be updated with the
  # current output instead of comparing.
  def self.require_equal(test_name : String, output : String | Bytes, test_data_dir : String? = nil)
    dir = test_data_dir || @@dir
    golden_path = File.join(dir, "#{test_name}.golden")

    if @@update
      FileUtils.mkdir_p(File.dirname(golden_path), mode: 0o750)
      File.write(golden_path, output, perm: 0o600)
    end

    golden_content = File.read(golden_path)
    golden_str = normalize_windows_line_breaks(golden_content)
    golden_str = escape_seqs(golden_str)
    out_str = escape_seqs(output.is_a?(Bytes) ? String.new(output) : output)

    if golden_str != out_str
      diff = unified_diff("golden", "run", golden_str, out_str)
      raise "output does not match, expected:\n\n#{golden_str}\n\ngot:\n\n#{out_str}\n\ndiff:\n\n#{diff}"
    end
  end

  # escape_seqs escapes control codes and escape sequences from the given string.
  # The only preserved exception is the newline character.
  private def self.escape_seqs(input : String) : String
    input.split("\n").map do |line|
      line.inspect[1..-2]
    end.join("\n")
  end

  # normalize_windows_line_breaks replaces all \r\n with \n.
  # This is needed because Git for Windows checks out with \r\n by default.
  private def self.normalize_windows_line_breaks(str : String) : String
    if {% if flag?(:win32) %}true{% else %}false{% end %}
      str.gsub("\r\n", "\n")
    else
      str
    end
  end

  # Simple unified diff implementation
  private def self.unified_diff(a_label : String, b_label : String, a : String, b : String) : String
    diff = Similar::TextDiff.from_lines(a, b)
    diff.unified_diff.header(a_label, b_label).to_s
  end
end
