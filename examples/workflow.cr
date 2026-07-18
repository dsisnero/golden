# Workflow: pending snapshots, glob testing, review, and cleanup
#
# Run: crystal spec examples/workflow.cr

require "spec"
require "../src/golden"

describe "workflow" do
  temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))

  before_each do
    FileUtils.mkdir_p(temp_dir)
  end

  after_each do
    FileUtils.rm_rf(temp_dir)
  end

  it "lists pending snapshots" do
    File.write(File.join(temp_dir, "test.golden.new"), "pending")
    pending = Golden.pending_snapshots(temp_dir)
    pending.size.should eq(1)
  end

  it "accepts all pending snapshots" do
    File.write(File.join(temp_dir, "a.golden.new"), "a")
    File.write(File.join(temp_dir, "b.golden.new"), "b")
    Golden.accept_all!(temp_dir)
    File.exists?(File.join(temp_dir, "a.golden")).should be_true
    File.exists?(File.join(temp_dir, "b.golden")).should be_true
    File.exists?(File.join(temp_dir, "a.golden.new")).should be_false
  end

  it "rejects all pending snapshots" do
    File.write(File.join(temp_dir, "bad.golden.new"), "bad")
    Golden.reject_all!(temp_dir)
    File.exists?(File.join(temp_dir, "bad.golden.new")).should be_false
  end

  it "glob snapshots over input files" do
    inputs = File.join(temp_dir, "inputs")
    FileUtils.mkdir_p(inputs)
    File.write(File.join(inputs, "a.txt"), "data_a")
    File.write(File.join(inputs, "b.txt"), "data_b")

    Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
      Golden.glob_snapshots(File.join(inputs, "*.txt")) { |p| File.read(p) }
    end

    File.read(File.join(temp_dir, "a.golden")).should eq("data_a")
    File.read(File.join(temp_dir, "b.golden")).should eq("data_b")
  end

  it "finds unreferenced snapshots after tracking" do
    File.write(File.join(temp_dir, "used.golden"), "used")
    File.write(File.join(temp_dir, "orphan.golden"), "orphan")
    Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
      Golden.reset_tracking!
      Golden.assert_snapshot("used", "used")
      orphans = Golden.unreferenced_snapshots
      orphans.size.should eq(1)
      orphans.first.should contain("orphan.golden")
    end
  end

  it "cleans up orphans" do
    File.write(File.join(temp_dir, "orphan.golden"), "x")
    Golden.reset_tracking!
    removed = Golden.cleanup!(temp_dir)
    removed.size.should eq(1)
    File.exists?(File.join(temp_dir, "orphan.golden")).should be_false
  end
end
