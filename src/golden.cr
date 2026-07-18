require "base64"
require "file_utils"
require "set"
require "similar"
require "yaml"

module Golden
  VERSION = "0.2.0"

  enum UpdateMode
    Auto
    Always
    No
    New
    Unseen
  end

  struct Redaction
    getter pattern : Regex
    getter replacement : String

    def initialize(@pattern : Regex, @replacement : String)
    end

    def apply(input : String) : String
      input.gsub(@pattern, @replacement)
    end
  end

  module Comparator
    abstract def matches?(expected : String, actual : String) : Bool
  end

  class FuzzyComparator
    include Comparator
    getter threshold : Float64

    def initialize(@threshold : Float64 = 0.01)
    end

    def matches?(expected : String, actual : String) : Bool
      exp_tokens = expected.split
      act_tokens = actual.split

      return false if exp_tokens.size != act_tokens.size

      exp_tokens.zip(act_tokens).all? do |e, a|
        if e == a
          true
        else
          ef = e.to_f?
          af = a.to_f?
          if ef && af
            (ef - af).abs <= @threshold
          else
            false
          end
        end
      end
    end
  end

  class Settings
    property update_mode : UpdateMode
    property dir : String
    property filters : Array(String -> String)
    property redactions : Array(Redaction)
    property comparator : Comparator?

    def initialize(@update_mode = UpdateMode::Auto, @dir = "testdata")
      @filters = [] of String -> String
      @redactions = [] of Redaction
      @comparator = nil
    end
  end

  @@settings = Settings.new

  def self.settings : Settings
    @@settings
  end

  def self.settings=(s : Settings)
    @@settings = s
  end

  def self.with_settings(update_mode : UpdateMode? = nil, dir : String? = nil)
    old = @@settings
    begin
      if um = update_mode
        @@settings = Settings.new(um, @@settings.dir)
        @@settings.filters = old.filters.dup
        @@settings.redactions = old.redactions.dup
        @@settings.comparator = old.comparator
      end
      if d = dir
        @@settings = Settings.new(@@settings.update_mode, d)
        @@settings.filters = old.filters.dup
        @@settings.redactions = old.redactions.dup
        @@settings.comparator = old.comparator
      end
      yield
    ensure
      @@settings = old
    end
  end

  def self.add_filter(pattern : Regex, replacement : String)
    @@settings.filters << ->(s : String) { s.gsub(pattern, replacement) }
  end

  def self.add_filter(&block : String -> String)
    @@settings.filters << block
  end

  def self.add_redaction(pattern : Regex, replacement : String)
    @@settings.redactions << Redaction.new(pattern, replacement)
  end

  def self.init
    if ENV["GOLDEN_UPDATE"]? == "1"
      @@settings.update_mode = UpdateMode::Always
    end
  end

  def self.update=(value : Bool)
    @@settings.update_mode = value ? UpdateMode::Always : UpdateMode::No
  end

  def self.update? : Bool
    @@settings.update_mode.always?
  end

  def self.configure_with(path : String)
    raise "Config file not found: #{path}" unless File.exists?(path)
    raw = File.read(path)
    config = YAML.parse(raw)
    if um = config["update_mode"]?
      mode = um.to_s.downcase
      case mode
      when "auto"   then @@settings.update_mode = UpdateMode::Auto
      when "always" then @@settings.update_mode = UpdateMode::Always
      when "no"     then @@settings.update_mode = UpdateMode::No
      when "new"    then @@settings.update_mode = UpdateMode::New
      when "unseen" then @@settings.update_mode = UpdateMode::Unseen
      end
    end
    if d = config["dir"]?
      @@settings.dir = d.to_s
    end
    config["filters"]?.try do |filters_val|
      filters_val.as_a.each do |f|
        add_filter(Regex.new(f["pattern"].to_s), f["replacement"].to_s)
      end
    end
    config["redactions"]?.try do |redactions_val|
      redactions_val.as_a.each do |r|
        add_redaction(Regex.new(r["pattern"].to_s), r["replacement"].to_s)
      end
    end
  end

  def self.auto_configure!(start_dir : String = Dir.current)
    if root = find_project_root(start_dir)
      config_path = File.join(root, ".golden.yml")
      if File.exists?(config_path)
        configure_with(config_path)
      end
    end
  end

  @@accessed_snapshots = Set(String).new

  def self.reset_tracking!
    @@accessed_snapshots = Set(String).new
  end

  def self.unreferenced_snapshots(dir : String? = nil) : Array(String)
    search_dir = dir || @@settings.dir
    all = Dir.glob(File.join(search_dir, "**/*.golden")).sort
    all.reject { |path| @@accessed_snapshots.includes?(path) }
  end

  def self.cleanup!(dir : String? = nil, dry_run : Bool = false) : Array(String)
    orphans = unreferenced_snapshots(dir)
    unless dry_run
      orphans.each do |path|
        File.delete(path)
        meta = path + ".meta"
        File.delete(meta) if File.exists?(meta)
      end
    end
    orphans
  end

  @@group = ""

  def self.group=(group : String)
    @@group = group
  end

  def self.group : String
    @@group
  end

  def self.dir=(dir : String)
    @@settings.dir = dir
  end

  def self.dir : String
    @@settings.dir
  end

  macro assert_snapshot(*args)
    {% if args.size == 2 %}
      Golden.require_equal({{args[0]}}, {{args[1]}}, metadata_line: __LINE__)
    {% elsif @def %}
      Golden.require_equal({{@type.name.id.stringify}} + "/" + {{@def.name.stringify}}, {{args[0]}}, metadata_line: __LINE__)
    {% else %}
      Golden.require_equal({{@type.name.id.stringify}} + "/snapshot_at_{{__LINE__}}", {{args[0]}}, metadata_line: __LINE__)
    {% end %}
  end

  macro assert_json_snapshot(*args)
    {% if args.size == 2 %}
      Golden.require_equal({{args[0]}}, {{args[1]}}.to_pretty_json, metadata_line: __LINE__)
    {% elsif @def %}
      Golden.require_equal({{@type.name.id.stringify}} + "/" + {{@def.name.stringify}}, {{args[0]}}.to_pretty_json, metadata_line: __LINE__)
    {% else %}
      Golden.require_equal({{@type.name.id.stringify}} + "/snapshot_at_{{__LINE__}}", {{args[0]}}.to_pretty_json, metadata_line: __LINE__)
    {% end %}
  end

  macro assert_yaml_snapshot(*args)
    {% if args.size == 2 %}
      Golden.require_equal({{args[0]}}, {{args[1]}}.to_yaml, metadata_line: __LINE__)
    {% elsif @def %}
      Golden.require_equal({{@type.name.id.stringify}} + "/" + {{@def.name.stringify}}, {{args[0]}}.to_yaml, metadata_line: __LINE__)
    {% else %}
      Golden.require_equal({{@type.name.id.stringify}} + "/snapshot_at_{{__LINE__}}", {{args[0]}}.to_yaml, metadata_line: __LINE__)
    {% end %}
  end

  macro assert_binary_snapshot(*args)
    {% if args.size == 2 %}
      Golden.require_equal({{args[0]}}, Base64.encode({{args[1]}}), metadata_line: __LINE__)
    {% elsif @def %}
      Golden.require_equal({{@type.name.id.stringify}} + "/" + {{@def.name.stringify}}, Base64.encode({{args[0]}}), metadata_line: __LINE__)
    {% else %}
      Golden.require_equal({{@type.name.id.stringify}} + "/snapshot_at_{{__LINE__}}", Base64.encode({{args[0]}}), metadata_line: __LINE__)
    {% end %}
  end

  def self.find_spec_dir(start_dir : String = Dir.current) : String?
    dir = start_dir
    while true
      spec_dir = File.join(dir, "spec")
      if Dir.exists?(spec_dir)
        return spec_dir
      end
      parent = File.dirname(dir)
      break if parent == dir
      dir = parent
    end
    nil
  end

  def self.find_project_root(start_dir : String = Dir.current) : String?
    dir = start_dir
    while true
      shard_yml = File.join(dir, "shard.yml")
      if File.exists?(shard_yml)
        return dir
      end
      parent = File.dirname(dir)
      break if parent == dir
      dir = parent
    end
    nil
  end

  def self.pending_snapshots(dir : String? = nil) : Array(String)
    search_dir = dir || @@settings.dir
    Dir.glob(File.join(search_dir, "**/*.golden.new")).sort
  end

  def self.accept_all!(dir : String? = nil) : Array(String)
    search_dir = dir || @@settings.dir
    pending = Dir.glob(File.join(search_dir, "**/*.golden.new")).sort
    pending.each do |pending_path|
      golden_path = pending_path.rchop(".new")
      FileUtils.mv(pending_path, golden_path)
      write_metadata(golden_path, File.basename(golden_path, ".golden"), nil)
    end
    pending.map { |p| p.rchop(".new") }
  end

  def self.reject_all!(dir : String? = nil) : Array(String)
    search_dir = dir || @@settings.dir
    pending = Dir.glob(File.join(search_dir, "**/*.golden.new")).sort
    pending.each { |p| File.delete(p) }
    pending
  end

  def self.glob_snapshots(pattern : String, test_data_dir : String? = nil, &block : String -> String)
    Dir.glob(pattern).sort.each do |path|
      test_name = File.basename(path, File.extname(path))
      output = yield path
      require_equal(test_name, output, test_data_dir: test_data_dir)
    end
  end

  def self.spec_test_data_dir : String?
    if spec_dir = find_spec_dir
      File.join(spec_dir, "testdata")
    else
      nil
    end
  end

  def self.require_equal(test_name : String, output : String | Bytes, test_data_dir : String? = nil, metadata_line : Int32? = nil)
    dir = test_data_dir || @@settings.dir
    full_name = @@group.empty? ? test_name : File.join(@@group, test_name)
    golden_path = File.join(dir, "#{full_name}.golden")
    pending_path = golden_path + ".new"
    output_str = output.is_a?(Bytes) ? String.new(output) : output
    processed_output = process_output(output_str)
    @@accessed_snapshots.add(golden_path)

    mode = effective_update_mode

    case mode
    in UpdateMode::Always
      write_file(golden_path, processed_output)
      write_metadata(golden_path, full_name, metadata_line)
    in UpdateMode::No
      compare_strict(golden_path, processed_output)
    in UpdateMode::New
      handle_pending(golden_path, pending_path, processed_output)
    in UpdateMode::Unseen
      handle_unseen(golden_path, pending_path, processed_output, full_name, metadata_line)
    in UpdateMode::Auto
      if ci?
        compare_strict(golden_path, processed_output)
      else
        handle_pending(golden_path, pending_path, processed_output)
      end
    end
  end

  private def self.effective_update_mode : UpdateMode
    @@settings.update_mode
  end

  private def self.ci? : Bool
    ENV["CI"]? == "true" || ENV["TF_BUILD"]? != nil
  end

  private def self.write_file(path : String, content : String)
    FileUtils.mkdir_p(File.dirname(path), mode: 0o750)
    File.write(path, content, perm: 0o600)
  end

  def self.write_metadata(golden_path : String, name : String, line : Int32?)
    meta_path = golden_path + ".meta"
    File.write(meta_path, {
      name:       name,
      created_at: Time.utc.to_rfc3339,
      line:       line,
    }.to_pretty_json)
  end

  def self.snapshot_metadata(name : String, test_data_dir : String? = nil) : Hash(String, JSON::Any)?
    dir = test_data_dir || @@settings.dir
    full_name = @@group.empty? ? name : File.join(@@group, name)
    meta_path = File.join(dir, "#{full_name}.golden.meta")
    return nil unless File.exists?(meta_path)
    JSON.parse(File.read(meta_path)).as_h
  end

  private def self.process_output(input : String) : String
    result = input
    @@settings.redactions.each { |r| result = r.apply(result) }
    @@settings.filters.each { |f| result = f.call(result) }
    result
  end

  private def self.compare_outputs(expected : String, actual : String) : Bool
    if cmp = @@settings.comparator
      cmp.matches?(expected, actual)
    else
      expected == actual
    end
  end

  private def self.compare_strict(golden_path : String, output : String)
    unless File.exists?(golden_path)
      raise "No golden file found at #{golden_path}. Set update mode to Always or New to create it."
    end

    golden_content = File.read(golden_path)
    golden_str = normalize(golden_content)
    out_str = normalize(output)

    unless compare_outputs(golden_str, out_str)
      diff = unified_diff("golden", "run", golden_str, out_str)
      raise "output does not match, expected:\n\n#{golden_str}\n\ngot:\n\n#{out_str}\n\ndiff:\n\n#{diff}"
    end
  end

  private def self.handle_pending(golden_path : String, pending_path : String, output : String)
    if File.exists?(golden_path)
      golden_content = File.read(golden_path)
      golden_str = normalize(golden_content)
      out_str = normalize(output)

      if compare_outputs(golden_str, out_str)
        delete_file(pending_path)
        return
      end

      write_file(pending_path, output)
      diff = unified_diff("golden", "run", golden_str, out_str)
      raise "output does not match, expected:\n\n#{golden_str}\n\ngot:\n\n#{out_str}\n\ndiff:\n\n#{diff}"
    else
      write_file(pending_path, output)
      raise "New golden file: #{golden_path}. Run with GOLDEN_UPDATE=1 or cargo-insta to accept."
    end
  end

  private def self.handle_unseen(golden_path : String, pending_path : String, output : String, test_name : String? = nil, metadata_line : Int32? = nil)
    unless File.exists?(golden_path)
      write_file(golden_path, output)
      write_metadata(golden_path, test_name || "", metadata_line) if test_name
      return
    end

    golden_content = File.read(golden_path)
    golden_str = normalize(golden_content)
    out_str = normalize(output)

    if compare_outputs(golden_str, out_str)
      delete_file(pending_path)
      return
    end

    write_file(pending_path, output)
    diff = unified_diff("golden", "run", golden_str, out_str)
    raise "output does not match, expected:\n\n#{golden_str}\n\ngot:\n\n#{out_str}\n\ndiff:\n\n#{diff}"
  end

  private def self.delete_file(path : String)
    File.delete(path) if File.exists?(path)
  end

  private def self.normalize(input : String) : String
    str = normalize_windows_line_breaks(input)
    escape_seqs(str)
  end

  private def self.escape_seqs(input : String) : String
    input.split("\n").map do |line|
      line.inspect[1..-2]
    end.join("\n")
  end

  private def self.normalize_windows_line_breaks(str : String) : String
    if {% if flag?(:win32) %}true{% else %}false{% end %}
      str.gsub("\r\n", "\n")
    else
      str
    end
  end

  private def self.unified_diff(a_label : String, b_label : String, a : String, b : String) : String
    diff = Similar::TextDiff.from_lines(a, b)
    diff.unified_diff.header(a_label, b_label).to_s
  end
end
