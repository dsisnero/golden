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
  it "has name and path" do
    item = Golden::ReviewItem.new("test", "/path/test.golden.new")
    item.name.should eq("test")
    item.path.should eq("/path/test.golden.new")
  end

  it "provides DefaultItem interface" do
    item = Golden::ReviewItem.new("test", "/path/test.golden.new")
    item.title.should eq("test")
    item.description.should eq("pending")
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
