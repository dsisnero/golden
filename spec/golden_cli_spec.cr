require "./spec_helper"
require "../src/golden/review"
require "../src/golden/cli"

private def temp_dir
  d = File.join(Dir.tempdir, Random::Secure.hex(8))
  FileUtils.mkdir_p(d)
  d
end

private def pending(dir, name = "test", content = "content")
  path = File.join(dir, "#{name}.golden.new")
  File.write(path, content)
  path
end

describe "Golden::CLI" do
  it "dispatch review returns empty when no pending snapshots" do
    dir = temp_dir
    result = Golden::CLI.dispatch(["review", "--snapshot", dir])
    result.should be_a(String)
    result.should be_empty
  end

  it "dispatch accept calls Golden.accept_all!" do
    dir = temp_dir
    pending(dir, "accept_test")
    result = Golden::CLI.dispatch(["accept", "--snapshot", dir])
    result.should contain("accept_test.golden")
  end

  it "dispatch reject calls Golden.reject_all!" do
    dir = temp_dir
    pending(dir, "reject_test")
    result = Golden::CLI.dispatch(["reject", "--snapshot", dir])
    result.should be_a(String)
    result.should_not be_empty
  end

  it "dispatch pending lists pending snapshots" do
    dir = temp_dir
    pending(dir, "snap_a")
    pending(dir, "snap_b")
    result = Golden::CLI.dispatch(["pending", "--snapshot", dir])
    result.should contain("snap_a.golden.new")
    result.should contain("snap_b.golden.new")
  end

  it "dispatch pending --json returns JSON" do
    dir = temp_dir
    pending(dir, "json_snap")
    result = Golden::CLI.dispatch(["pending", "--json", "--snapshot", dir])
    result.should contain("\"name\"")
    result.should contain("json_snap")
  end

  it "dispatch status returns formatted counts" do
    dir = temp_dir
    result = Golden::CLI.dispatch(["status", "--snapshot", dir])
    result.should contain("snapshots")
    result.should contain("pending")
    result.should contain("metadata")
    result.should contain("orphans")
  end

  it "dispatch clean removes unreferenced snapshots" do
    dir = temp_dir
    File.write(File.join(dir, "orphan.golden"), "orphan")
    Golden.reset_tracking!
    result = Golden::CLI.dispatch(["clean", "--snapshot", dir])
    result.should contain("orphan.golden")
    File.exists?(File.join(dir, "orphan.golden")).should be_false
  end

  it "dispatch clean --dry-run does not delete" do
    dir = temp_dir
    File.write(File.join(dir, "orphan.golden"), "orphan")
    Golden.reset_tracking!
    result = Golden::CLI.dispatch(["clean", "--dry-run", "--snapshot", dir])
    result.should contain("orphan.golden")
    File.exists?(File.join(dir, "orphan.golden")).should be_true
  end

  it "dispatch show displays snapshot contents" do
    dir = temp_dir
    File.write(File.join(dir, "display_test.golden"), "hello world")
    result = Golden::CLI.dispatch(["show", File.join(dir, "display_test.golden")])
    result.should contain("hello world")
  end

  it "dispatch show prints message for nonexistent snapshot" do
    dir = temp_dir
    result = Golden::CLI.dispatch(["show", File.join(dir, "nonexistent.golden")])
    result.should contain("not found")
  end

  it "dispatch prints usage for unknown command" do
    result = Golden::CLI.dispatch(["unknown"])
    result.should contain("Usage")
  end

  it "dispatch prints usage for no arguments" do
    result = Golden::CLI.dispatch([] of String)
    result.should contain("Usage")
  end

  it "dispatch accept with no pending returns empty" do
    dir = temp_dir
    result = Golden::CLI.dispatch(["accept", "--snapshot", dir])
    result.should be_a(String)
    result.should be_empty
  end

  it "dispatch reject with no pending returns empty" do
    dir = temp_dir
    result = Golden::CLI.dispatch(["reject", "--snapshot", dir])
    result.should be_a(String)
    result.should be_empty
  end

  it "test-review with --snapshot runs review on successful spec" do
    dir = temp_dir
    result = Golden::CLI.dispatch(["test-review", "--spec-cmd", "echo ok", "--snapshot", dir])
    result.should be_a(String)
  end

  it "test-review returns error when spec command fails" do
    dir = temp_dir
    result = Golden::CLI.dispatch(["test-review", "--spec-cmd", "false", "--snapshot", dir])
    result.should contain("failed")
  end

  it "Makefile has test-review target" do
    File.exists?("Makefile").should be_true
    content = File.read("Makefile")
    content.should contain("test-review:")
    content.should contain("golden review")
  end
end
