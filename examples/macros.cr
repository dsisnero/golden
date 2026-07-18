# Snapshot assertion macros (auto-naming and serialization)
#
# Run: crystal spec examples/macros.cr

require "spec"
require "../src/golden"

describe "macros" do
  temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))

  before_each do
    FileUtils.mkdir_p(temp_dir)
  end

  after_each do
    FileUtils.rm_rf(temp_dir)
  end

  it "assert_snapshot with explicit name" do
    Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
      Golden.assert_snapshot("explicit_name", "my output")
    end
    File.read(File.join(temp_dir, "explicit_name.golden")).should eq("my output")
  end

  it "assert_json_snapshot" do
    Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
      Golden.assert_json_snapshot("my_data", {"name" => "Alice", "age" => 30})
    end
    content = File.read(File.join(temp_dir, "my_data.golden"))
    content.should contain("Alice")
    content.should contain("30")
  end

  it "assert_yaml_snapshot" do
    Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
      Golden.assert_yaml_snapshot("config", {"debug" => true, "port" => 8080})
    end
    content = File.read(File.join(temp_dir, "config.golden"))
    content.should contain("debug")
  end

  it "assert_binary_snapshot" do
    Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
      Golden.assert_binary_snapshot("image_data", Bytes[0x89, 0x50, 0x4E, 0x47])
    end
    stored = File.read(File.join(temp_dir, "image_data.golden"))
    Base64.decode(stored)[0, 4].to_a.should eq([0x89, 0x50, 0x4E, 0x47])
  end
end
