require "./spec_helper"

describe Golden do
  before_each do
    Golden.update = false
  end

  it "TestRequireEqualUpdate" do
    Golden.update = true
    Golden.require_equal("TestRequireEqualUpdate", "test")
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
