# Advanced features: filters, redactions, custom comparators, config, metadata
#
# Run: crystal spec examples/advanced.cr

require "spec"
require "../src/golden"

describe "advanced" do
  temp_dir = File.join(Dir.tempdir, Random::Secure.hex(8))

  before_each do
    FileUtils.mkdir_p(temp_dir)
  end

  after_each do
    FileUtils.rm_rf(temp_dir)
  end

  it "filters dynamic content" do
    Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
      Golden.add_filter(/\d{4}-\d{2}-\d{2}/, "[DATE]")
      Golden.assert_snapshot("filtered", "Date: 2026-07-18")
    end
    File.read(File.join(temp_dir, "filtered.golden")).should eq("Date: [DATE]")
  end

  it "redacts sensitive data" do
    Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
      Golden.add_redaction(/token=\w+/, "token=REDACTED")
      Golden.assert_snapshot("redacted", "token=abc123; role=admin")
    end
    content = File.read(File.join(temp_dir, "redacted.golden"))
    content.should_not contain("abc123")
    content.should contain("token=REDACTED")
  end

  it "uses fuzzy comparator with tolerance" do
    File.write(File.join(temp_dir, "numeric.golden"), "result: 3.14159\ncount: 42\n")
    Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
      Golden.settings.comparator = Golden::FuzzyComparator.new(0.001)
      Golden.assert_snapshot("numeric", "result: 3.14150\ncount: 42\n")
    end
  end

  it "reads snapshot metadata" do
    Golden.with_settings(update_mode: Golden::UpdateMode::Always, dir: temp_dir) do
      Golden.assert_snapshot("with_meta", "content")
    end
    meta = Golden.snapshot_metadata("with_meta", temp_dir)
    meta.should_not be_nil
  end

  it "scopes settings with with_settings" do
    old_mode = Golden.settings.update_mode
    Golden.with_settings(update_mode: Golden::UpdateMode::No, dir: temp_dir) do
      Golden.settings.update_mode.should eq(Golden::UpdateMode::No)
    end
    Golden.settings.update_mode.should eq(old_mode)
  end
end
