require "./spec_helper"
require "../src/golden/review"

private def pending(dir, name = "test", content = "content")
  path = File.join(dir, "#{name}.golden.new")
  File.write(path, content)
  path
end

private def temp_dir
  d = File.join(Dir.tempdir, Random::Secure.hex(8))
  FileUtils.mkdir_p(d)
  d
end

describe "Golden::ReviewItem" do
  it "has name, path, and content" do
    dir = temp_dir
    p = pending(dir, "test")
    item = Golden::ReviewItem.new("test", p)
    item.name.should eq("test")
    item.path.should eq(p)
    item.new_content.should eq("content")
  end

  it "provides DefaultItem interface" do
    dir = temp_dir
    p = pending(dir, "test")
    item = Golden::ReviewItem.new("test", p)
    item.title.should eq("test")
    item.filter_value.should eq("test")
  end
end

describe "Golden::ReviewModel" do
  it "starts with empty actions" do
    model = Golden::ReviewModel.new([] of String)
    model.actions.should be_empty
  end

  it "shows review header in view" do
    model = Golden::ReviewModel.new([] of String)
    view = model.view
    view.content.should contain("Reviewing Pending Snapshots")
    view.content.should contain("[y] Accept")
  end

  it "lists pending items in view" do
    dir = temp_dir
    p1 = pending(dir, "snap_a")
    p2 = pending(dir, "snap_b")
    model = Golden::ReviewModel.new([p1, p2], dir)
    view = model.view
    view.content.should contain("snap_a")
    view.content.should contain("snap_b")
  end

  it "accepts the current item on 'y'" do
    dir = temp_dir
    p = pending(dir, "test_snap")
    model = Golden::ReviewModel.new([p], dir)

    key = Tea.key('y')
    model2, _ = model.update(key)

    model2 = model2.as(Golden::ReviewModel)
    model2.actions.size.should eq(1)
    model2.actions[0].should eq({"test_snap", "accepted"})
    File.exists?(File.join(dir, "test_snap.golden")).should be_true
  end

  it "rejects the current item on 'n'" do
    dir = temp_dir
    p = pending(dir, "test_snap")
    model = Golden::ReviewModel.new([p], dir)

    key = Tea.key('n')
    model2, _ = model.update(key)

    model2 = model2.as(Golden::ReviewModel)
    model2.actions.size.should eq(1)
    model2.actions[0].should eq({"test_snap", "rejected"})
    File.exists?(p).should be_false
  end

  it "skips the current item on 's'" do
    dir = temp_dir
    p = pending(dir, "test_snap")
    model = Golden::ReviewModel.new([p], dir)

    key = Tea.key('s')
    model2, _ = model.update(key)

    model2 = model2.as(Golden::ReviewModel)
    model2.actions.size.should eq(1)
    model2.actions[0].should eq({"test_snap", "skipped"})
    # File should remain on disk as .golden.new
    File.exists?(p).should be_true
  end

  it "returns quit command on 'q'" do
    model = Golden::ReviewModel.new([] of String)
    key = Tea.key('q')
    _, cmd = model.update(key)
    cmd.should_not be_nil
  end

  it "handles init returning nil" do
    model = Golden::ReviewModel.new([] of String)
    model.init.should be_nil
  end

  it "overwrites existing golden on accept" do
    dir = temp_dir
    p = pending(dir, "existing", "new_content")
    File.write(File.join(dir, "existing.golden"), "old_content")
    model = Golden::ReviewModel.new([p], dir)

    model.update(Tea.key('y'))
    File.read(File.join(dir, "existing.golden")).should eq("new_content")
  end

  it "delegates non-action keys to list" do
    dir = temp_dir
    p1 = pending(dir, "a")
    p2 = pending(dir, "b")
    model = Golden::ReviewModel.new([p1, p2], dir)

    # Initially at index 0
    model.list.index.should eq(0)

    # Press down arrow to navigate
    model.update(Tea.key(Tea::KeyDown))
    model.list.index.should eq(1)
  end

  it "tracks multiple actions" do
    dir = temp_dir
    p1 = pending(dir, "first", "a")
    p2 = pending(dir, "second", "b")
    model = Golden::ReviewModel.new([p1, p2], dir)

    model.update(Tea.key('y'))
    model.update(Tea.key('n'))

    model.actions.size.should eq(2)
    model.actions.should eq([{"first", "accepted"}, {"second", "rejected"}])
  end

  # --- Quick Wins: Skip, Batch ops, g/G, Help ---

  it "returns quit command on 'A' (accept all)" do
    dir = temp_dir
    p1 = pending(dir, "a", "content_a")
    p2 = pending(dir, "b", "content_b")
    model = Golden::ReviewModel.new([p1, p2], dir)

    key = Tea.key('A')
    model2, cmd = model.update(key)

    model2 = model2.as(Golden::ReviewModel)
    model2.actions.size.should eq(2)
    model2.actions.should eq([{"a", "accepted"}, {"b", "accepted"}])
    cmd.should_not be_nil
    # Files should be promoted
    File.exists?(File.join(dir, "a.golden")).should be_true
    File.exists?(File.join(dir, "b.golden")).should be_true
    File.read(File.join(dir, "a.golden")).should eq("content_a")
  end

  it "returns quit command on 'R' (reject all)" do
    dir = temp_dir
    p1 = pending(dir, "a")
    p2 = pending(dir, "b")
    model = Golden::ReviewModel.new([p1, p2], dir)

    key = Tea.key('R')
    model2, cmd = model.update(key)

    model2 = model2.as(Golden::ReviewModel)
    model2.actions.size.should eq(2)
    model2.actions.should eq([{"a", "rejected"}, {"b", "rejected"}])
    cmd.should_not be_nil
    File.exists?(p1).should be_false
    File.exists?(p2).should be_false
  end

  it "returns quit command on 'S' (skip all)" do
    dir = temp_dir
    p1 = pending(dir, "a")
    p2 = pending(dir, "b")
    model = Golden::ReviewModel.new([p1, p2], dir)

    key = Tea.key('S')
    model2, cmd = model.update(key)

    model2 = model2.as(Golden::ReviewModel)
    model2.actions.size.should eq(2)
    model2.actions.should eq([{"a", "skipped"}, {"b", "skipped"}])
    cmd.should_not be_nil
    # Files should remain on disk
    File.exists?(p1).should be_true
    File.exists?(p2).should be_true
  end

  it "navigates to top on 'g'" do
    dir = temp_dir
    p1 = pending(dir, "a")
    p2 = pending(dir, "b")
    p3 = pending(dir, "c")
    model = Golden::ReviewModel.new([p1, p2, p3], dir)

    # Move down twice then go to top
    model.update(Tea.key(Tea::KeyDown))
    model.update(Tea.key(Tea::KeyDown))
    model.list.index.should eq(2)

    model.update(Tea.key('g'))
    model.list.index.should eq(0)
  end

  it "navigates to bottom on 'G'" do
    dir = temp_dir
    p1 = pending(dir, "a")
    p2 = pending(dir, "b")
    p3 = pending(dir, "c")
    model = Golden::ReviewModel.new([p1, p2, p3], dir)

    model.update(Tea.key('G'))
    model.list.index.should eq(2)
  end

  it "help overlay shown on '?'" do
    model = Golden::ReviewModel.new([] of String)
    view = model.view
    view.content.should contain("[y] Accept")

    # Activate help
    model2, _ = model.update(Tea.key('?'))
    model2 = model2.as(Golden::ReviewModel)
    model2.show_help?.should be_true
    view2 = model2.view
    view2.content.should contain("Keybindings")
  end

  it "help overlay dismissed on repeat '?'" do
    model = Golden::ReviewModel.new([] of String)
    model2, _ = model.update(Tea.key('?'))
    model2 = model2.as(Golden::ReviewModel)
    model3, _ = model2.update(Tea.key('?'))
    model3 = model3.as(Golden::ReviewModel)
    model3.show_help?.should be_false
  end

  it "accept_all_remaining on upper-case A" do
    dir = temp_dir
    p1 = pending(dir, "x")
    p2 = pending(dir, "y")
    p3 = pending(dir, "z")
    model = Golden::ReviewModel.new([p1, p2, p3], dir)

    # Accept first, then accept all remaining
    model.update(Tea.key('y'))
    model.update(Tea.key('A'))

    model.actions.size.should eq(3)
    model.actions.should eq([{"x", "accepted"}, {"y", "accepted"}, {"z", "accepted"}])
  end

  # --- Diff Display (Phase 1.1) ---

  it "ReviewItem holds content and diff info" do
    dir = temp_dir
    p = pending(dir, "diff_snap", "new content")
    File.write(File.join(dir, "diff_snap.golden"), "old content")
    item = Golden::ReviewItem.new("diff_snap", p)
    item.has_existing?.should be_true
    item.new_content.should eq("new content")
    item.old_content.should eq("old content")
  end

  it "ReviewItem detects new snapshot (no existing golden)" do
    dir = temp_dir
    p = pending(dir, "new_snap", "new content")
    item = Golden::ReviewItem.new("new_snap", p)
    item.has_existing?.should be_false
    item.old_content.should be_nil
  end

  it "ReviewItem generates diff when existing golden present" do
    dir = temp_dir
    p = pending(dir, "diff_snap", "line1\nline2\nline3")
    File.write(File.join(dir, "diff_snap.golden"), "line1\nchanged\nline3")
    item = Golden::ReviewItem.new("diff_snap", p)
    item.diff.should contain("-changed")
    item.diff.should contain("+line2")
  end

  it "ReviewItem shows (new snapshot) label when no existing golden" do
    dir = temp_dir
    p = pending(dir, "brand_new", "content")
    item = Golden::ReviewItem.new("brand_new", p)
    item.has_existing?.should be_false
  end

  it "toggles diff display on 'd'" do
    dir = temp_dir
    p = pending(dir, "test_snap", "content")
    model = Golden::ReviewModel.new([p], dir)
    model.show_diff?.should be_false

    model2, _ = model.update(Tea.key('d'))
    model2 = model2.as(Golden::ReviewModel)
    model2.show_diff?.should be_true
  end

  it "diff view shown when pressing 'd'" do
    dir = temp_dir
    p = pending(dir, "diff_test", "new line")
    File.write(File.join(dir, "diff_test.golden"), "old line")
    model = Golden::ReviewModel.new([p], dir)
    model2, _ = model.update(Tea.key('d'))
    model2 = model2.as(Golden::ReviewModel)
    view = model2.view
    view.content.should contain("\e[") # ANSI highlighted diff
  end

  # --- Source Context Display (Phase 1.4) ---

  it "ReviewItem reads metadata from .golden.meta" do
    dir = temp_dir
    p = pending(dir, "meta_snap", "content")
    meta_path = File.join(dir, "meta_snap.golden.meta")
    File.write(meta_path, %({"name":"meta_snap","line":42,"created_at":"2024-01-01T00:00:00Z"}))
    item = Golden::ReviewItem.new("meta_snap", p)
    item.metadata_line.should eq(42)
    item.metadata_source_file.should be_nil
  end

  it "ReviewItem reads source_file from metadata" do
    dir = temp_dir
    p = pending(dir, "src_snap", "content")
    meta_path = File.join(dir, "src_snap.golden.meta")
    File.write(meta_path, %({"name":"src_snap","line":10,"source_file":"spec/my_test.cr","created_at":"2024-01-01T00:00:00Z"}))
    item = Golden::ReviewItem.new("src_snap", p)
    item.metadata_line.should eq(10)
    item.metadata_source_file.should eq("spec/my_test.cr")
  end

  it "ReviewItem shows empty source context when no metadata" do
    dir = temp_dir
    p = pending(dir, "no_meta", "content")
    item = Golden::ReviewItem.new("no_meta", p)
    item.source_context.should be_empty
  end

  it "ReviewItem reads source context lines from source file" do
    dir = temp_dir
    p = pending(dir, "ctx_snap", "content")
    meta_path = File.join(dir, "ctx_snap.golden.meta")
    File.write(meta_path, %({"name":"ctx_snap","line":7,"source_file":"#{dir}/source.cr","created_at":"2024-01-01T00:00:00Z"}))
    File.write(File.join(dir, "source.cr"), "line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8")
    item = Golden::ReviewItem.new("ctx_snap", p)
    item.source_context.should contain("line4")
    item.source_context.should contain("line5")
    item.source_context.should contain("line6")
  end

  it "toggles info display on 'i'" do
    dir = temp_dir
    p = pending(dir, "info_snap", "content")
    model = Golden::ReviewModel.new([p], dir)
    model.show_info?.should be_false

    model2, _ = model.update(Tea.key('i'))
    model2 = model2.as(Golden::ReviewModel)
    model2.show_info?.should be_true
  end

  it "info view shows source context when pressing 'i'" do
    dir = temp_dir
    p = pending(dir, "info_ctx", "actual")
    meta_path = File.join(dir, "info_ctx.golden.meta")
    File.write(meta_path, %({"name":"info_ctx","line":5,"source_file":"#{dir}/info_source.cr","created_at":"2024-01-01T00:00:00Z"}))
    File.write(File.join(dir, "info_source.cr"), "a\nb\nc\nd\ne\nf")
    model = Golden::ReviewModel.new([p], dir)
    model2, _ = model.update(Tea.key('i'))
    model2 = model2.as(Golden::ReviewModel)
    view = model2.view
    view.content.should contain("Snapshot")
    view.content.should contain("Line")
  end

  # --- Inline Word-Level Diff (Phase 1.6) ---

  it "ReviewItem generates inline diff with ANSI highlighting for replace ops" do
    dir = temp_dir
    p = pending(dir, "inline_snap", "hello world\nsame line\n")
    File.write(File.join(dir, "inline_snap.golden"), "hello there\nsame line\n")
    item = Golden::ReviewItem.new("inline_snap", p)
    item.inline_diff.should contain("\e[") # ANSI escape sequences present
    item.inline_diff.should contain("world")
    item.inline_diff.should contain("there")
  end

  it "ReviewItem inline diff is empty for new snapshot" do
    dir = temp_dir
    p = pending(dir, "new_inline", "content")
    item = Golden::ReviewItem.new("new_inline", p)
    item.inline_diff.should eq("")
  end

  it "ReviewItem inline diff is plain for exact match" do
    dir = temp_dir
    p = pending(dir, "same_inline", "same content\n")
    File.write(File.join(dir, "same_inline.golden"), "same content\n")
    item = Golden::ReviewItem.new("same_inline", p)
    item.inline_diff.should eq("")
  end

  it "diff view shows ANSI-highlighted content when d is pressed" do
    dir = temp_dir
    p = pending(dir, "ansi_diff", "hello world\n")
    File.write(File.join(dir, "ansi_diff.golden"), "hello there\n")
    model = Golden::ReviewModel.new([p], dir)
    model2, _ = model.update(Tea.key('d'))
    model2 = model2.as(Golden::ReviewModel)
    view = model2.view
    view.content.should contain("\e[")
  end

  it "review summary returns structured results" do
    dir = temp_dir
    p1 = pending(dir, "snap_a")
    p2 = pending(dir, "snap_b")
    p3 = pending(dir, "snap_c")
    model = Golden::ReviewModel.new([p1, p2, p3], dir)

    model.update(Tea.key('y')) # accept snap_a
    model.update(Tea.key('s')) # skip snap_b
    model.update(Tea.key('n')) # reject snap_c

    model.accepted.should eq(1)
    model.skipped.should eq(1)
    model.rejected.should eq(1)
    model.total.should eq(3)
  end
end

describe "Golden.review!" do
  it "returns empty when directory does not exist" do
    Golden.review!("/nonexistent/path/xyz").should be_empty
  end

  it "returns empty when no pending snapshots" do
    dir = temp_dir
    Golden.review!(dir).should be_empty
  end
end

describe "Golden.report_pending!" do
  it "prints nothing when no pending snapshots" do
    dir = temp_dir
    Golden.report_pending!(dir).should eq("")
  end

  it "reports pending snapshots to stderr" do
    dir = temp_dir
    pending(dir, "snap_a")
    pending(dir, "snap_b")
    result = Golden.report_pending!(dir)
    result.should contain("2 pending snapshot(s)")
    result.should contain("snap_a.golden.new")
    result.should contain("snap_b.golden.new")
  end

  it "defaults to Golden.dir" do
    old_dir = Golden.dir
    begin
      dir = temp_dir
      Golden.dir = dir
      pending(dir, "default_test")
      result = Golden.report_pending!
      result.should contain("default_test.golden.new")
    ensure
      Golden.dir = old_dir
    end
  end
end
