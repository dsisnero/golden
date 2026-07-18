require "json"
require "yaml"
require "./spec_helper"

def auto_name_helper(value)
  Golden.assert_snapshot(value)
end

def json_auto_helper(value)
  Golden.assert_json_snapshot(value)
end

def yaml_auto_helper(value)
  Golden.assert_yaml_snapshot(value)
end

def binary_auto_helper(data : Bytes)
  Golden.assert_binary_snapshot(data)
end

describe Golden do
  describe ".find_spec_dir" do
    it "finds spec directory from project root" do
      spec_dir = Golden.find_spec_dir
      spec_dir.should_not be_nil
      spec_dir.not_nil!.should end_with("/spec")
    end

    it "returns nil when no spec directory found" do
      temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))
      FileUtils.mkdir_p(temp_dir)
      begin
        spec_dir = Golden.find_spec_dir(temp_dir)
        spec_dir.should be_nil
      ensure
        FileUtils.rm_rf(temp_dir)
      end
    end
  end

  describe ".spec_test_data_dir" do
    it "returns spec/testdata when spec directory exists" do
      if spec_testdata = Golden.spec_test_data_dir
        spec_testdata.should end_with("/spec/testdata")
      else
        pending "spec directory not found"
      end
    end
  end

  describe ".require_equal with custom test_data_dir" do
    it "reads golden file from custom directory" do
      temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))
      begin
        test_data_dir = File.join(temp_dir, "custom_testdata")
        FileUtils.mkdir_p(test_data_dir)
        golden_file = File.join(test_data_dir, "custom_test.golden")
        File.write(golden_file, "expected")

        Golden.require_equal("custom_test", "expected", test_data_dir: test_data_dir)
      ensure
        FileUtils.rm_rf(temp_dir)
      end
    end

    it "fails when golden file doesn't match" do
      temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))
      begin
        test_data_dir = File.join(temp_dir, "custom_testdata")
        FileUtils.mkdir_p(test_data_dir)
        golden_file = File.join(test_data_dir, "custom_test.golden")
        File.write(golden_file, "expected")

        expect_raises(Exception, /output does not match/) do
          Golden.require_equal("custom_test", "wrong", test_data_dir: test_data_dir)
        end
      ensure
        FileUtils.rm_rf(temp_dir)
      end
    end

    it "writes golden file to custom directory when update is true" do
      temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))
      begin
        test_data_dir = File.join(temp_dir, "custom_testdata")
        Golden.update = true
        Golden.require_equal("update_test", "new content", test_data_dir: test_data_dir)

        golden_file = File.join(test_data_dir, "update_test.golden")
        File.read(golden_file).should eq("new content")
      ensure
        FileUtils.rm_rf(temp_dir)
        Golden.update = false
      end
    end
  end

  describe ".with_settings" do
    it "restores original settings after block" do
      original_mode = Golden.settings.update_mode
      Golden.with_settings(update_mode: Golden::UpdateMode::Always) do
        Golden.settings.update_mode.should eq(Golden::UpdateMode::Always)
      end
      Golden.settings.update_mode.should eq(original_mode)
    end

    it "nests correctly" do
      Golden.with_settings(update_mode: Golden::UpdateMode::New) do
        Golden.with_settings(update_mode: Golden::UpdateMode::No) do
          Golden.settings.update_mode.should eq(Golden::UpdateMode::No)
        end
        Golden.settings.update_mode.should eq(Golden::UpdateMode::New)
      end
    end

    it "restores after exception" do
      original_mode = Golden.settings.update_mode
      expect_raises(Exception, "boom") do
        Golden.with_settings(update_mode: Golden::UpdateMode::New) do
          raise "boom"
        end
      end
      Golden.settings.update_mode.should eq(original_mode)
    end
  end

  describe "UpdateMode" do
    temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))

    before_each do
      FileUtils.mkdir_p(temp_dir)
    end

    after_each do
      FileUtils.rm_rf(temp_dir)
    end

    describe "Always" do
      it "writes golden file directly and passes" do
        Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
          Golden.require_equal("always_test", "content")
          golden_path = File.join(temp_dir, "always_test.golden")
          File.read(golden_path).should eq("content")
        end
      end

      it "overwrites existing golden file" do
        File.write(File.join(temp_dir, "overwrite_test.golden"), "old")
        Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
          Golden.require_equal("overwrite_test", "new")
          File.read(File.join(temp_dir, "overwrite_test.golden")).should eq("new")
        end
      end
    end

    describe "No" do
      it "passes when golden matches" do
        File.write(File.join(temp_dir, "match_test.golden"), "content")
        Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
          Golden.require_equal("match_test", "content")
        end
      end

      it "raises on mismatch" do
        File.write(File.join(temp_dir, "mismatch_test.golden"), "expected")
        Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
          expect_raises(Exception, /output does not match/) do
            Golden.require_equal("mismatch_test", "wrong")
          end
        end
      end

      it "does not create .new file on mismatch" do
        File.write(File.join(temp_dir, "no_new_test.golden"), "expected")
        Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
          expect_raises(Exception) do
            Golden.require_equal("no_new_test", "wrong")
          end
          File.exists?(File.join(temp_dir, "no_new_test.golden.new")).should be_false
        end
      end

      it "raises when golden does not exist" do
        Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
          expect_raises(Exception, /No golden file found/) do
            Golden.require_equal("nonexistent", "content")
          end
        end
      end
    end

    describe "Auto" do
      it "passes when golden matches" do
        File.write(File.join(temp_dir, "match_test.golden"), "content")
        Golden.with_settings(update_mode: Golden::UpdateMode::Auto, dir: temp_dir) do
          Golden.require_equal("match_test", "content")
        end
      end

      it "writes .snap.new and raises for new snapshot" do
        Golden.with_settings(update_mode: Golden::UpdateMode::Auto, dir: temp_dir) do
          expect_raises(Exception, /New golden file/) do
            Golden.require_equal("new_snapshot", "content")
          end
          pending_path = File.join(temp_dir, "new_snapshot.golden.new")
          File.exists?(pending_path).should be_true
          File.read(pending_path).should eq("content")
        end
      end

      it "writes .snap.new and raises for changed snapshot" do
        File.write(File.join(temp_dir, "changed_test.golden"), "old")
        Golden.with_settings(update_mode: Golden::UpdateMode::Auto, dir: temp_dir) do
          expect_raises(Exception, /output does not match/) do
            Golden.require_equal("changed_test", "new")
          end
          pending_path = File.join(temp_dir, "changed_test.golden.new")
          File.exists?(pending_path).should be_true
          File.read(pending_path).should eq("new")
        end
      end

      it "does not leave stale .snap.new when snapshot matches" do
        File.write(File.join(temp_dir, "clean_test.golden"), "content")
        stale = File.join(temp_dir, "clean_test.golden.new")
        File.write(stale, "stale")
        Golden.with_settings(update_mode: Golden::UpdateMode::Auto, dir: temp_dir) do
          Golden.require_equal("clean_test", "content")
        end
        File.exists?(stale).should be_false
      end
    end

    describe "New" do
      it "passes when golden matches" do
        File.write(File.join(temp_dir, "match_test.golden"), "content")
        Golden.with_settings(update_mode: Golden::UpdateMode::New, dir: temp_dir) do
          Golden.require_equal("match_test", "content")
        end
      end

      it "writes .snap.new for new snapshot" do
        Golden.with_settings(update_mode: Golden::UpdateMode::New, dir: temp_dir) do
          expect_raises(Exception, /New golden file/) do
            Golden.require_equal("new_snap", "content")
          end
          File.exists?(File.join(temp_dir, "new_snap.golden.new")).should be_true
        end
      end

      it "writes .snap.new for changed snapshot" do
        File.write(File.join(temp_dir, "changed_test.golden"), "old")
        Golden.with_settings(update_mode: Golden::UpdateMode::New, dir: temp_dir) do
          expect_raises(Exception, /output does not match/) do
            Golden.require_equal("changed_test", "new")
          end
          File.exists?(File.join(temp_dir, "changed_test.golden.new")).should be_true
        end
      end
    end

    describe "Unseen" do
      it "auto-accepts new snapshot by writing golden file" do
        Golden.with_settings(update_mode: Golden::UpdateMode::Unseen, dir: temp_dir) do
          Golden.require_equal("unseen_new", "content")
          File.read(File.join(temp_dir, "unseen_new.golden")).should eq("content")
        end
      end

      it "writes .snap.new for changed snapshot" do
        File.write(File.join(temp_dir, "unseen_changed.golden"), "old")
        Golden.with_settings(update_mode: Golden::UpdateMode::Unseen, dir: temp_dir) do
          expect_raises(Exception, /output does not match/) do
            Golden.require_equal("unseen_changed", "new")
          end
          File.exists?(File.join(temp_dir, "unseen_changed.golden.new")).should be_true
        end
      end

      it "passes when golden matches" do
        File.write(File.join(temp_dir, "unseen_match.golden"), "content")
        Golden.with_settings(update_mode: Golden::UpdateMode::Unseen, dir: temp_dir) do
          Golden.require_equal("unseen_match", "content")
        end
      end
    end

  end

  describe "assert_snapshot macro" do
    temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))

    before_each do
      FileUtils.mkdir_p(temp_dir)
      Golden.group = ""
    end

    after_each do
      FileUtils.rm_rf(temp_dir)
    end

    it "delegates to require_equal with explicit name" do
      Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
        Golden.assert_snapshot("explicit_name", "hello")
        File.read(File.join(temp_dir, "explicit_name.golden")).should eq("hello")
      end
    end

    it "generates name from @type when inside a method" do
      Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
        auto_name_helper("macro_auto_value")
        File.read(File.join(temp_dir, "Golden/auto_name_helper.golden")).should eq("macro_auto_value")
      end
    end

    it "uses group prefix when set" do
      Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
        Golden.group = "VisualTests"
        Golden.assert_snapshot("grouped_test", "grouped_value")
        File.read(File.join(temp_dir, "VisualTests/grouped_test.golden")).should eq("grouped_value")
      end
    end

    it "includes group prefix in auto-names" do
      Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
        Golden.group = "VisualTests"
        auto_name_helper("grouped_auto_value")
        File.read(File.join(temp_dir, "VisualTests/Golden/auto_name_helper.golden")).should eq("grouped_auto_value")
      end
    end
  end

  describe "CI detection" do
    temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))

    before_each do
      FileUtils.mkdir_p(temp_dir)
      Golden.group = ""
    end

    after_each do
      FileUtils.rm_rf(temp_dir)
    end

    it "uses No-like behavior in Auto mode when CI env is set" do
      File.write(File.join(temp_dir, "ci_test.golden"), "expected")
      old_ci = ENV["CI"]?
      begin
        ENV["CI"] = "true"
        Golden.with_settings(update_mode: Golden::UpdateMode::Auto, dir: temp_dir) do
          expect_raises(Exception, /output does not match/) do
            Golden.require_equal("ci_test", "wrong")
          end
        end
      ensure
        if old_ci
          ENV["CI"] = old_ci
        else
          ENV.delete("CI")
        end
      end
    end

    it "does not create .new files in Auto mode on CI" do
      old_ci = ENV["CI"]?
      begin
        ENV["CI"] = "true"
        Golden.with_settings(update_mode: Golden::UpdateMode::Auto, dir: temp_dir) do
          expect_raises(Exception) do
            Golden.require_equal("ci_new_test", "content")
          end
          File.exists?(File.join(temp_dir, "ci_new_test.golden.new")).should be_false
        end
      ensure
        if old_ci
          ENV["CI"] = old_ci
        else
          ENV.delete("CI")
        end
      end
    end
  end

  describe "filters" do
    temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))

    before_each do
      FileUtils.mkdir_p(temp_dir)
      Golden.settings.filters.clear
    end

    after_each do
      FileUtils.rm_rf(temp_dir)
      Golden.settings.filters.clear
    end

    it "passes when filter makes output match golden" do
      File.write(File.join(temp_dir, "filtered_test.golden"), "hello [timestamp] world")
      output = "hello 2024-01-15 world"
      Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
        Golden.add_filter(/\d{4}-\d{2}-\d{2}/, "[timestamp]")
        Golden.require_equal("filtered_test", output)
      end
    end

    it "fails when filter still doesn't make output match" do
      File.write(File.join(temp_dir, "filter_fail_test.golden"), "expected")
      output = "actual"
      Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
        Golden.add_filter(/foo/, "bar")
        expect_raises(Exception, /output does not match/) do
          Golden.require_equal("filter_fail_test", output)
        end
      end
    end

    it "supports block-based filters" do
      File.write(File.join(temp_dir, "block_filter_test.golden"), "hello [redacted]")
      output = "hello secret123"
      Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
        Golden.add_filter { |s| s.gsub(/secret\d+/, "[redacted]") }
        Golden.require_equal("block_filter_test", output)
      end
    end

    it "applies filters in order" do
      File.write(File.join(temp_dir, "multi_filter_test.golden"), "a:1 b:2")
      output = "a:1 b:2 "
      Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
        Golden.add_filter(/a:\d+/, "a:1")
        Golden.add_filter(/ +$/, "")
        Golden.require_equal("multi_filter_test", output)
      end
    end

    it "filters are scoped to with_settings block" do
      File.write(File.join(temp_dir, "scoped_filter_test.golden"), "filtered")
      output = "raw"
      Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
        expect_raises(Exception, /output does not match/) do
          Golden.require_equal("scoped_filter_test", output)
        end
      end
    end
  end

  describe "custom comparator" do
    temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))

    before_each do
      FileUtils.mkdir_p(temp_dir)
      Golden.settings.comparator = nil
    end

    after_each do
      FileUtils.rm_rf(temp_dir)
      Golden.settings.comparator = nil
    end

    it "uses custom comparator for comparison" do
      File.write(File.join(temp_dir, "float_test.golden"), "3.14")
      output = "3.14159"
      Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
        Golden.settings.comparator = Golden::FuzzyComparator.new(0.01)
        Golden.require_equal("float_test", output)
      end
    end

    it "custom comparator can fail" do
      File.write(File.join(temp_dir, "float_fail_test.golden"), "3.14")
      output = "3.99"
      Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
        Golden.settings.comparator = Golden::FuzzyComparator.new(0.01)
        expect_raises(Exception, /output does not match/) do
          Golden.require_equal("float_fail_test", output)
        end
      end
    end
  end

  describe "redactions" do
    temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))

    before_each do
      FileUtils.mkdir_p(temp_dir)
      Golden.settings.redactions.clear
    end

    after_each do
      FileUtils.rm_rf(temp_dir)
      Golden.settings.redactions.clear
    end

    it "redacts matching patterns before comparison" do
      File.write(File.join(temp_dir, "redacted_test.golden"), "id: [redacted]")
      output = "id: abc-123-def"
      Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
        Golden.add_redaction(/[a-z]{3}-\d{3}-[a-z]{3}/, "[redacted]")
        Golden.require_equal("redacted_test", output)
      end
    end

    it "redactions can be combined with filters" do
      File.write(File.join(temp_dir, "combined_test.golden"), "user:[redacted] ts:[ts]")
      output = "user:john_doe ts:2024-01-15T12:00:00Z"
      Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
        Golden.add_redaction(/[a-z]+_[a-z]+/, "[redacted]")
        Golden.add_filter(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/, "[ts]")
        Golden.require_equal("combined_test", output)
      end
    end
  end

  describe "assert_json_snapshot" do
    temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))

    before_each do
      FileUtils.mkdir_p(temp_dir)
      Golden.group = ""
    end

    after_each do
      FileUtils.rm_rf(temp_dir)
    end

    it "serializes value as pretty JSON and compares" do
      File.write(File.join(temp_dir, "json_test.golden"), %Q({\n  "name": "test",\n  "value": 42\n}))
      output = {"name" => "test", "value" => 42}
      Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
        Golden.assert_json_snapshot("json_test", output)
      end
    end

    it "fails on mismatched JSON" do
      File.write(File.join(temp_dir, "json_fail_test.golden"), %Q({\n  "name": "wrong"\n}))
      output = {"name" => "test"}
      Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
        expect_raises(Exception, /output does not match/) do
          Golden.assert_json_snapshot("json_fail_test", output)
        end
      end
    end

    it "auto-names from test context" do
      Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
        json_auto_helper({"key" => "value"})
        golden_path = File.join(temp_dir, "Golden/json_auto_helper.golden")
        File.exists?(golden_path).should be_true
        File.read(golden_path).should eq(%Q({\n  "key": "value"\n}))
      end
    end

    it "handles empty hash" do
      File.write(File.join(temp_dir, "empty_json.golden"), "{}")
      output = {} of String => String
      Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
        Golden.assert_json_snapshot("empty_json", output)
      end
    end

    it "handles arrays" do
      File.write(File.join(temp_dir, "array_json.golden"), %Q([\n  1,\n  2,\n  3\n]))
      output = [1, 2, 3]
      Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
        Golden.assert_json_snapshot("array_json", output)
      end
    end

    it "uses group prefix" do
      Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
        Golden.group = "API"
        Golden.assert_json_snapshot("grouped_json", {"a" => 1})
        File.exists?(File.join(temp_dir, "API/grouped_json.golden")).should be_true
      end
    end
  end

  describe "assert_yaml_snapshot" do
    temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))

    before_each do
      FileUtils.mkdir_p(temp_dir)
      Golden.group = ""
    end

    after_each do
      FileUtils.rm_rf(temp_dir)
    end

    it "serializes value as YAML and compares" do
      File.write(File.join(temp_dir, "yaml_test.golden"), "---\nname: test\nvalue: 42\n")
      output = {"name" => "test", "value" => 42}
      Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
        Golden.assert_yaml_snapshot("yaml_test", output)
      end
    end

    it "fails on mismatched YAML" do
      File.write(File.join(temp_dir, "yaml_fail_test.golden"), "---\nname: wrong\n")
      output = {"name" => "test"}
      Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
        expect_raises(Exception, /output does not match/) do
          Golden.assert_yaml_snapshot("yaml_fail_test", output)
        end
      end
    end

    it "auto-names from test context" do
      Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
        yaml_auto_helper({"key" => "value"})
        golden_path = File.join(temp_dir, "Golden/yaml_auto_helper.golden")
        File.exists?(golden_path).should be_true
        File.read(golden_path).should eq("---\nkey: value\n")
      end
    end

    it "handles nested structures" do
      File.write(File.join(temp_dir, "nested_yaml.golden"), "---\na:\n  b: 1\n  c: 2\n")
      output = {"a" => {"b" => 1, "c" => 2}}
      Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
        Golden.assert_yaml_snapshot("nested_yaml", output)
      end
    end

    it "handles arrays in YAML" do
      File.write(File.join(temp_dir, "array_yaml.golden"), "---\n- 1\n- 2\n- 3\n")
      output = [1, 2, 3]
      Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
        Golden.assert_yaml_snapshot("array_yaml", output)
      end
    end
  end

  describe "assert_binary_snapshot" do
    temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))

    before_each do
      FileUtils.mkdir_p(temp_dir)
    end

    after_each do
      FileUtils.rm_rf(temp_dir)
    end

    it "stores binary data as base64 in golden file" do
      data = Bytes[0x00, 0x01, 0x02, 0xFF]
      Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
        Golden.assert_binary_snapshot("binary_test", data)
      end
      content = File.read(File.join(temp_dir, "binary_test.golden"))
      Base64.decode_string(content).should eq(String.new(data))
    end

    it "matches against existing base64 golden file" do
      data = Bytes[0xDE, 0xAD, 0xBE, 0xEF]
      encoded = Base64.encode(data)
      File.write(File.join(temp_dir, "deadbeef.golden"), encoded)
      Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
        Golden.assert_binary_snapshot("deadbeef", data)
      end
    end

    it "raises on mismatch" do
      encoded = Base64.encode(Bytes[0x00, 0x00])
      File.write(File.join(temp_dir, "mismatch.golden"), encoded)
      Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
        expect_raises(Exception, /output does not match/) do
          Golden.assert_binary_snapshot("mismatch", Bytes[0xFF, 0xFF])
        end
      end
    end

    it "works with auto-naming in a method context" do
      data = Bytes[0x42, 0x43]
      Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
        binary_auto_helper(data)
        golden_path = File.join(temp_dir, "Golden/binary_auto_helper.golden")
        File.exists?(golden_path).should be_true
        Base64.decode_string(File.read(golden_path)).should eq(String.new(data))
      end
    end
  end

  describe "configure_with" do
    temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))
    saved = {mode: Golden.settings.update_mode, dir: Golden.settings.dir}

    before_each do
      FileUtils.mkdir_p(temp_dir)
    end

    after_each do
      FileUtils.rm_rf(temp_dir)
      Golden.settings.update_mode = saved[:mode]
      Golden.settings.dir = saved[:dir]
      Golden.settings.filters.clear
      Golden.settings.redactions.clear
    end

    it "sets update_mode from YAML config" do
      File.write(File.join(temp_dir, ".golden.yml"), "update_mode: \"always\"\n")
      Golden.configure_with(File.join(temp_dir, ".golden.yml"))
      Golden.settings.update_mode.should eq(Golden::UpdateMode::Always)
    end

    it "sets dir from YAML config" do
      File.write(File.join(temp_dir, ".golden.yml"), "dir: \"my_snapshots\"\n")
      Golden.configure_with(File.join(temp_dir, ".golden.yml"))
      Golden.settings.dir.should eq("my_snapshots")
    end

    it "adds filters from YAML config" do
      File.write(File.join(temp_dir, ".golden.yml"), <<-YAML
        filters:
          - pattern: "\\\\d+"
            replacement: "[NUM]"
        YAML
      )
      Golden.configure_with(File.join(temp_dir, ".golden.yml"))
      Golden.settings.filters.size.should eq(1)
    end

    it "adds redactions from YAML config" do
      File.write(File.join(temp_dir, ".golden.yml"), <<-YAML
        redactions:
          - pattern: "token=\\\\w+"
            replacement: "[TOKEN]"
        YAML
      )
      Golden.configure_with(File.join(temp_dir, ".golden.yml"))
      Golden.settings.redactions.size.should eq(1)
    end

    it "raises on missing config file" do
      expect_raises(Exception, /Config file not found/) do
        Golden.configure_with(File.join(temp_dir, "nonexistent.yml"))
      end
    end
  end

  describe "auto_configure!" do
    temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))
    saved_mode = Golden.settings.update_mode

    after_each do
      Golden.settings.update_mode = saved_mode
    end

    it "finds and loads .golden.yml from project root" do
      FileUtils.mkdir_p(temp_dir)
      File.write(File.join(temp_dir, "shard.yml"), "name: test\n")
      File.write(File.join(temp_dir, ".golden.yml"), "update_mode: \"no\"\n")
      Golden.settings.update_mode = Golden::UpdateMode::Auto  # reset
      Golden.auto_configure!(temp_dir)
      Golden.settings.update_mode.should eq(Golden::UpdateMode::No)
    end

    it "does nothing when no .golden.yml exists" do
      FileUtils.mkdir_p(temp_dir)
      Golden.auto_configure!(temp_dir)
      # should not raise
    end
  end

  describe "snapshot_metadata" do
    temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))

    before_each do
      FileUtils.mkdir_p(temp_dir)
    end

    after_each do
      FileUtils.rm_rf(temp_dir)
    end

    it "stores metadata when creating a snapshot" do
      Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
        Golden.assert_snapshot("meta_test", "content")
      end
      meta = Golden.snapshot_metadata("meta_test", temp_dir)
      meta.should_not be_nil
      if m = meta
        m["name"].should eq("meta_test")
        m["line"].should_not be_nil
      end
    end

    it "includes creation timestamp" do
      Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
        Golden.assert_snapshot("timestamp_test", "data")
      end
      meta = Golden.snapshot_metadata("timestamp_test", temp_dir)
      meta.should_not be_nil
      if m = meta
        m["created_at"].to_s.should_not be_empty
      end
    end

    it "returns nil for snapshots without metadata" do
      File.write(File.join(temp_dir, "legacy.golden"), "old")
      Golden.snapshot_metadata("legacy", temp_dir).should be_nil
    end

    it "stores metadata for json snapshots" do
      Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
        Golden.assert_json_snapshot("json_meta", {"key" => "val"})
      end
      meta = Golden.snapshot_metadata("json_meta", temp_dir)
      meta.should_not be_nil
      if m = meta
        m["name"].should eq("json_meta")
      end
    end

    it "stores metadata for yaml snapshots" do
      Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
        Golden.assert_yaml_snapshot("yaml_meta", {"a" => 1})
      end
      meta = Golden.snapshot_metadata("yaml_meta", temp_dir)
      meta.should_not be_nil
      if m = meta
        m["name"].should eq("yaml_meta")
      end
    end

    it "stores metadata for binary snapshots" do
      Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
        Golden.assert_binary_snapshot("bin_meta", Bytes[0x01, 0x02])
      end
      meta = Golden.snapshot_metadata("bin_meta", temp_dir)
      meta.should_not be_nil
      if m = meta
        m["name"].should eq("bin_meta")
      end
    end

    it "defaults to golden dir when no dir given" do
      old_dir = Golden.dir
      begin
        Golden.dir = temp_dir
        Golden.with_settings(update_mode: Golden::UpdateMode::Always) do
          Golden.assert_snapshot("default_dir_meta", "x")
        end
        Golden.snapshot_metadata("default_dir_meta").should_not be_nil
      ensure
        Golden.dir = old_dir
      end
    end

    it "writes metadata for accept_all!" do
      File.write(File.join(temp_dir, "promoted.golden.new"), "data")
      Golden.accept_all!(temp_dir)
      meta = Golden.snapshot_metadata("promoted", temp_dir)
      meta.should_not be_nil
    end
  end

  describe "glob_snapshots" do
    temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))
    input_dir = File.join(temp_dir, "inputs")

    before_each do
      FileUtils.mkdir_p(input_dir)
      Golden.group = ""
    end

    after_each do
      FileUtils.rm_rf(temp_dir)
    end

    it "creates golden files from glob matches in Always mode" do
      File.write(File.join(input_dir, "hello.txt"), "hello world")
      File.write(File.join(input_dir, "goodbye.txt"), "goodbye world")
      Golden.update = true
      Golden.glob_snapshots(File.join(input_dir, "*.txt"), test_data_dir: temp_dir) { |p| File.read(p) }
      Golden.update = false
      File.read(File.join(temp_dir, "hello.golden")).should eq("hello world")
      File.read(File.join(temp_dir, "goodbye.golden")).should eq("goodbye world")
    end

    it "compares existing golden files against glob matches" do
      File.write(File.join(input_dir, "match.txt"), "content")
      File.write(File.join(temp_dir, "match.golden"), "content")
      Golden.update = false
      Golden.glob_snapshots(File.join(input_dir, "*.txt"), test_data_dir: temp_dir) { |p| File.read(p) }
    end

    it "raises on mismatch" do
      File.write(File.join(input_dir, "mismatch.txt"), "actual")
      File.write(File.join(temp_dir, "mismatch.golden"), "expected")
      Golden.update = false
      expect_raises(Exception, /output does not match/) do
        Golden.glob_snapshots(File.join(input_dir, "*.txt"), test_data_dir: temp_dir) { |p| File.read(p) }
      end
    end

    it "processes files in sorted order" do
      File.write(File.join(input_dir, "a_first.txt"), "a")
      File.write(File.join(input_dir, "b_second.txt"), "b")
      Golden.update = true
      names = [] of String
      Golden.glob_snapshots(File.join(input_dir, "*.txt"), test_data_dir: temp_dir) do |path|
        names << File.basename(path)
        File.read(path)
      end
      Golden.update = false
      names.should eq(["a_first.txt", "b_second.txt"])
    end

    it "works with block transforming content" do
      File.write(File.join(input_dir, "transform.txt"), "raw")
      Golden.update = true
      Golden.glob_snapshots(File.join(input_dir, "*.txt"), test_data_dir: temp_dir) do |path|
        File.read(path).upcase
      end
      Golden.update = false
      File.read(File.join(temp_dir, "transform.golden")).should eq("RAW")
    end

    it "uses snapshot group prefix" do
      File.write(File.join(input_dir, "grouped.txt"), "content")
      Golden.update = true
      Golden.group = "GlobTests"
      Golden.glob_snapshots(File.join(input_dir, "*.txt"), test_data_dir: temp_dir) { |p| File.read(p) }
      Golden.update = false
      File.read(File.join(temp_dir, "GlobTests/grouped.golden")).should eq("content")
    end

    it "yields the matched path to the block" do
      File.write(File.join(input_dir, "path_check.txt"), "data")
      seen_paths = [] of String
      Golden.update = true
      Golden.glob_snapshots(File.join(input_dir, "*.txt"), test_data_dir: temp_dir) do |path|
        seen_paths << path
        File.read(path)
      end
      Golden.update = false
      seen_paths.size.should eq(1)
      seen_paths.first.should contain("path_check.txt")
    end
  end

  describe "pending_snapshots" do
    temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))

    before_each do
      FileUtils.mkdir_p(temp_dir)
    end

    after_each do
      FileUtils.rm_rf(temp_dir)
    end

    it "returns empty array when no pending snapshots exist" do
      results = Golden.pending_snapshots(temp_dir)
      results.should be_a(Array(String))
      results.should be_empty
    end

    it "finds .snap.new files in the directory" do
      File.write(File.join(temp_dir, "test1.golden.new"), "pending1")
      File.write(File.join(temp_dir, "test2.golden.new"), "pending2")
      results = Golden.pending_snapshots(temp_dir)
      results.size.should eq(2)
      results.should contain(File.join(temp_dir, "test1.golden.new"))
      results.should contain(File.join(temp_dir, "test2.golden.new"))
    end

    it "ignores .golden files without .new suffix" do
      File.write(File.join(temp_dir, "accepted.golden"), "accepted")
      File.write(File.join(temp_dir, "pending.golden.new"), "pending")
      results = Golden.pending_snapshots(temp_dir)
      results.size.should eq(1)
      results.first.should contain("pending.golden.new")
    end

    it "finds pending snapshots in subdirectories" do
      sub_dir = File.join(temp_dir, "nested")
      FileUtils.mkdir_p(sub_dir)
      File.write(File.join(sub_dir, "deep.golden.new"), "deep_pending")
      results = Golden.pending_snapshots(temp_dir)
      results.size.should eq(1)
      results.first.should contain("nested/deep.golden.new")
    end

    it "defaults to Golden.dir when no argument given" do
      old_dir = Golden.dir
      begin
        Golden.dir = temp_dir
        File.write(File.join(temp_dir, "default.golden.new"), "default_pending")
        results = Golden.pending_snapshots
        results.should contain(File.join(temp_dir, "default.golden.new"))
      ensure
        Golden.dir = old_dir
      end
    end
  end

  describe "unreferenced_snapshots" do
    temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))

    before_each do
      FileUtils.mkdir_p(temp_dir)
    end

    after_each do
      FileUtils.rm_rf(temp_dir)
    end

    it "returns empty when every golden file has been accessed" do
      File.write(File.join(temp_dir, "used.golden"), "used")
      Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
        Golden.reset_tracking!
        Golden.assert_snapshot("used", "used")
        results = Golden.unreferenced_snapshots
        results.should be_empty
      end
    end

    it "reports golden files that were not accessed" do
      File.write(File.join(temp_dir, "used.golden"), "used")
      File.write(File.join(temp_dir, "orphan.golden"), "orphan")
      Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
        Golden.reset_tracking!
        Golden.assert_snapshot("used", "used")
        results = Golden.unreferenced_snapshots
        results.size.should eq(1)
        results.first.should contain("orphan.golden")
      end
    end

    it "handles multiple unreferenced snapshots" do
      File.write(File.join(temp_dir, "a.golden"), "a")
      File.write(File.join(temp_dir, "b.golden"), "b")
      File.write(File.join(temp_dir, "c.golden"), "c")
      Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
        Golden.reset_tracking!
        Golden.assert_snapshot("a", "a")
        results = Golden.unreferenced_snapshots
        results.size.should eq(2)
      end
    end

    it "ignores non-golden files" do
      File.write(File.join(temp_dir, "readme.md"), "docs")
      Golden.reset_tracking!
      results = Golden.unreferenced_snapshots(temp_dir)
      results.should be_empty
    end
  end

  describe "cleanup!" do
    temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))

    before_each do
      FileUtils.mkdir_p(temp_dir)
    end

    after_each do
      FileUtils.rm_rf(temp_dir)
    end

    it "removes unreferenced golden files" do
      File.write(File.join(temp_dir, "used.golden"), "used")
      File.write(File.join(temp_dir, "orphan.golden"), "orphan")
      Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
        Golden.reset_tracking!
        Golden.assert_snapshot("used", "used")
        removed = Golden.cleanup!
        removed.size.should eq(1)
        removed.first.should contain("orphan.golden")
        File.exists?(File.join(temp_dir, "orphan.golden")).should be_false
        File.exists?(File.join(temp_dir, "used.golden")).should be_true
      end
    end

    it "also removes orphan metadata files" do
      File.write(File.join(temp_dir, "orphan.golden"), "x")
      File.write(File.join(temp_dir, "orphan.golden.meta"), "{}")
      Golden.reset_tracking!
      Golden.cleanup!(temp_dir)
      File.exists?(File.join(temp_dir, "orphan.golden.meta")).should be_false
    end

    it "dry-run returns files but does not delete" do
      File.write(File.join(temp_dir, "orphan.golden"), "x")
      Golden.reset_tracking!
      removed = Golden.cleanup!(temp_dir, dry_run: true)
      removed.size.should eq(1)
      File.exists?(File.join(temp_dir, "orphan.golden")).should be_true
    end

    it "defaults to Golden.dir" do
      old_dir = Golden.dir
      begin
        Golden.dir = temp_dir
        File.write(File.join(temp_dir, "orphan.golden"), "x")
        Golden.reset_tracking!
        Golden.cleanup!.size.should eq(1)
      ensure
        Golden.dir = old_dir
      end
    end
  end

  describe "accept_all!" do
    temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))

    before_each do
      FileUtils.mkdir_p(temp_dir)
    end

    after_each do
      FileUtils.rm_rf(temp_dir)
    end

    it "promotes .golden.new to .golden" do
      File.write(File.join(temp_dir, "test.golden.new"), "content")
      accepted = Golden.accept_all!(temp_dir)
      accepted.size.should eq(1)
      accepted.first.should contain("test.golden")
      File.read(File.join(temp_dir, "test.golden")).should eq("content")
      File.exists?(File.join(temp_dir, "test.golden.new")).should be_false
    end

    it "returns empty array when no pending snapshots exist" do
      accepted = Golden.accept_all!(temp_dir)
      accepted.should be_empty
    end

    it "promotes multiple pending snapshots" do
      File.write(File.join(temp_dir, "a.golden.new"), "a")
      File.write(File.join(temp_dir, "b.golden.new"), "b")
      accepted = Golden.accept_all!(temp_dir)
      accepted.size.should eq(2)
      File.read(File.join(temp_dir, "a.golden")).should eq("a")
      File.read(File.join(temp_dir, "b.golden")).should eq("b")
    end

    it "promotes pending snapshots in subdirectories" do
      sub = File.join(temp_dir, "sub")
      FileUtils.mkdir_p(sub)
      File.write(File.join(sub, "deep.golden.new"), "deep")
      accepted = Golden.accept_all!(temp_dir)
      accepted.size.should eq(1)
      accepted.first.should contain("sub/deep.golden")
      File.read(File.join(sub, "deep.golden")).should eq("deep")
    end

    it "overwrites existing .golden files" do
      File.write(File.join(temp_dir, "existing.golden"), "old")
      File.write(File.join(temp_dir, "existing.golden.new"), "new")
      accepted = Golden.accept_all!(temp_dir)
      File.read(File.join(temp_dir, "existing.golden")).should eq("new")
    end

    it "defaults to golden dir" do
      old_dir = Golden.dir
      begin
        Golden.dir = temp_dir
        File.write(File.join(temp_dir, "test.golden.new"), "auto")
        accepted = Golden.accept_all!
        accepted.size.should eq(1)
      ensure
        Golden.dir = old_dir
      end
    end
  end

  describe "reject_all!" do
    temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))

    before_each do
      FileUtils.mkdir_p(temp_dir)
    end

    after_each do
      FileUtils.rm_rf(temp_dir)
    end

    it "removes .golden.new files" do
      File.write(File.join(temp_dir, "test.golden.new"), "pending")
      rejected = Golden.reject_all!(temp_dir)
      rejected.size.should eq(1)
      rejected.first.should contain("test.golden.new")
      File.exists?(File.join(temp_dir, "test.golden.new")).should be_false
    end

    it "does not affect .golden files" do
      File.write(File.join(temp_dir, "kept.golden"), "accepted")
      File.write(File.join(temp_dir, "removed.golden.new"), "pending")
      Golden.reject_all!(temp_dir)
      File.read(File.join(temp_dir, "kept.golden")).should eq("accepted")
    end

    it "returns empty when no pending files exist" do
      Golden.reject_all!(temp_dir).should be_empty
    end
  end
end
