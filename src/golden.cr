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
#     Golden.require_equal("MyClass/produces_expected_output", output)
#   end
# end
# ```
#
# This will compare `output` with the contents of `testdata/MyClass/produces_expected_output.golden`.
# If the files differ, a diff will be shown.
require "file_utils"

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

  def self.update?
    @@update
  end

  # Parse command line arguments for --update flag.
  # Note: This only works if the flag is passed to the spec runner.
  def self.parse_args
    @@update = ARGV.includes?("--update")
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

  # Asserts that the given output matches the golden file for the test.
  #
  # * `test_name` is the name of the test, which will be used to construct the
  #   golden file path: `#{dir}/#{test_name}.golden`
  # * `output` is the actual output to compare, either a String or Bytes
  #
  # If the output doesn't match the golden file, a diff will be shown and the
  # test will fail.
  #
  # If `Golden.update` is `true`, the golden file will be updated with the
  # current output instead of comparing.
  def self.require_equal(test_name : String, output : String | Bytes)
    golden_path = File.join(@@dir, "#{test_name}.golden")

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
    lines_a = a.split("\n")
    lines_b = b.split("\n")

    # Simple diff for now - just show both versions
    <<-DIFF
    --- #{a_label}
    +++ #{b_label}
    #{diff_lines(lines_a, lines_b)}
    DIFF
  end

  private def self.diff_lines(a : Array(String), b : Array(String)) : String
    result = [] of String
    max_len = {a.size, b.size}.max

    max_len.times do |i|
      line_a = a[i]?
      line_b = b[i]?

      if line_a == line_b
        result << " #{line_a}"
      else
        result << "-#{line_a}" if line_a
        result << "+#{line_b}" if line_b
      end
    end

    result.join("\n")
  end
end
