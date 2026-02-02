require "./spec_helper"

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
        # If spec directory not found (unlikely in test environment), skip
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

        Golden.update = false
        Golden.require_equal("custom_test", "expected", test_data_dir: test_data_dir)

        # Should not raise
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

        Golden.update = false
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
end
