# Basic golden file testing
#
# Run: crystal spec examples/simple.cr

require "spec"
require "../src/golden"

describe "basic" do
  temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))

  before_each do
    FileUtils.mkdir_p(temp_dir)
  end

  after_each do
    FileUtils.rm_rf(temp_dir)
  end

  it "matches golden file" do
    # First create the golden file
    Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
      Golden.require_equal("hello", "hello world")
    end
    # Now compare
    Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
      Golden.require_equal("hello", "hello world")
    end
  end

  it "auto-updates golden files" do
    Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
      Golden.require_equal("generated", "this output becomes the golden file")
    end
    File.read(File.join(temp_dir, "generated.golden")).should eq("this output becomes the golden file")
  end

  it "uses group prefix" do
    Golden.group = "MyTests"
    Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
      Golden.require_equal("grouped", "stored in MyTests/grouped.golden")
    end
    Golden.group = ""
    File.read(File.join(temp_dir, "MyTests/grouped.golden")).should eq("stored in MyTests/grouped.golden")
  end
end
