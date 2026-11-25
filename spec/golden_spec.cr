require "./spec_helper"

describe Golden do
  before_each do
    Golden.update = false
    Golden.group = ""
  end

  it "TestRequireEqualUpdate" do
    temp_dir = File.join(Dir.tempdir, "golden_spec_update_#{Random::Secure.hex(8)}")
    begin
      Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
        Golden.require_equal("TestRequireEqualUpdate", "test")
      end
      File.read(File.join(temp_dir, "TestRequireEqualUpdate.golden")).should eq("test")
    ensure
      FileUtils.rm_rf(temp_dir)
    end
  end

  it "TestRequireEqualNoUpdate" do
    Golden.update = false
    Golden.require_equal("TestRequireEqualNoUpdate", "test")
  end

  it "TestRequireWithLineBreaks" do
    Golden.update = false
    Golden.require_equal("TestRequireWithLineBreaks", "foo\nbar\nbaz\n")
  end

  describe "TestTypes" do
    it "SliceOfBytes" do
      Golden.update = false
      Golden.require_equal("TestTypes/SliceOfBytes", "test".to_slice)
    end

    it "String" do
      Golden.update = false
      Golden.require_equal("TestTypes/String", "test")
    end
  end
end
