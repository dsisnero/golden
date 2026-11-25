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

  @@serializers = {} of Symbol => String -> String

  def self.register_serializer(name : Symbol, serializer : String -> String)
    @@serializers[name] = serializer
  end

  def self.serialize(value : String, name : Symbol) : String
    if s = @@serializers[name]?
      s.call(value)
    else
      raise "Unknown serializer: #{name.inspect}"
    end
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
    property path_redactions : Array({path: String, replacement: String})
    property comparator : Comparator?
    property serializer : Symbol?
    property description : String?
    property info : String?
    property input_file : String?
    property? omit_expression : Bool
    property snapshot_suffix : String
    property? prepend_module_to_snapshot : Bool
    property? allow_duplicates : Bool

    def initialize(@update_mode = UpdateMode::Auto, @dir = "testdata",
                   @description : String? = nil, @info : String? = nil,
                   @input_file : String? = nil, @omit_expression = false,
                   @snapshot_suffix = "", @prepend_module_to_snapshot = false,
                   @allow_duplicates = false)
      @filters = [] of String -> String
      @redactions = [] of Redaction
      @path_redactions = [] of {path: String, replacement: String}
      @comparator = nil
      @serializer = nil
    end
  end

  @@settings = Settings.new
  @@duplicate_snapshots = {} of String => String

  def self.settings : Settings
    @@settings
  end

  def self.settings=(s : Settings)
    @@settings = s
  end

  private def self.clone_settings : Settings
    s = Settings.new(@@settings.update_mode, @@settings.dir,
      @@settings.description, @@settings.info, @@settings.input_file,
      @@settings.omit_expression?, @@settings.snapshot_suffix,
      @@settings.prepend_module_to_snapshot?, @@settings.allow_duplicates?)
    s.filters = @@settings.filters.dup
    s.redactions = @@settings.redactions.dup
    s.path_redactions = @@settings.path_redactions.dup
    s.comparator = @@settings.comparator
    s.serializer = @@settings.serializer
    s
  end

  def self.with_settings(update_mode : UpdateMode? = nil, dir : String? = nil, serializer : Symbol? = nil,
                         description : String? = nil, info : String? = nil,
                         input_file : String? = nil, omit_expression : Bool? = nil,
                         snapshot_suffix : String? = nil, prepend_module_to_snapshot : Bool? = nil,
                         allow_duplicates : Bool? = nil, &)
    old = @@settings
    begin
      s = clone_settings
      if um = update_mode
        s.update_mode = um
      end
      if d = dir
        s.dir = d
      end
      if ser = serializer
        s.serializer = ser
      end
      if desc = description
        s.description = desc
      end
      if inf = info
        s.info = inf
      end
      if inp = input_file
        s.input_file = inp
      end
      if oe = omit_expression
        s.omit_expression = oe
      end
      if sfx = snapshot_suffix
        s.snapshot_suffix = sfx
      end
      if pms = prepend_module_to_snapshot
        s.prepend_module_to_snapshot = pms
      end
      if ad = allow_duplicates
        s.allow_duplicates = ad
      end
      @@settings = s
      yield
    ensure
      @@settings = old
    end
  end

  # Allows repeated assertions with the same snapshot name inside the block.
  # Repeated names must produce identical content; a mismatch raises.
  def self.allow_duplicates(&)
    old = @@settings
    begin
      s = clone_settings
      s.allow_duplicates = true
      @@settings = s
      @@duplicate_snapshots = {} of String => String
      yield
    ensure
      @@settings = old
      @@duplicate_snapshots = {} of String => String
    end
  end

  def self.allow_duplicates? : Bool
    @@settings.allow_duplicates?
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

  def self.add_path_redaction(path : String, replacement : String)
    @@settings.path_redactions << {path: path, replacement: replacement}
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
      filters_val.as_a.each do |filter_json|
        add_filter(Regex.new(filter_json["pattern"].to_s), filter_json["replacement"].to_s)
      end
    end
    config["redactions"]?.try do |redactions_val|
      redactions_val.as_a.each do |redaction_json|
        add_redaction(Regex.new(redaction_json["pattern"].to_s), redaction_json["replacement"].to_s)
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

  def self.status(dir : String? = nil) : Hash(String, Int32)
    search_dir = dir || @@settings.dir
    all_golden = Dir.glob(File.join(search_dir, "**/*.golden")).sort
    snapshots = all_golden.count { |path| !path.ends_with?(".golden.new") && !path.ends_with?(".golden.meta") }
    pending = Dir.glob(File.join(search_dir, "**/*.golden.new")).size
    meta_count = Dir.glob(File.join(search_dir, "**/*.golden.meta")).size
    orphans = unreferenced_snapshots(search_dir).size
    {"snapshots" => snapshots, "pending" => pending, "metadata" => meta_count, "orphans" => orphans}
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

  def self.show_snapshot(path : String) : String?
    File.read(path) if File.exists?(path)
  end

  def self.test_and_review!(spec_cmd : String = "crystal spec", snapshot_dir : String? = nil) : Array(Tuple(String, String))
    result = Process.run(spec_cmd, shell: true)
    if result.success?
      review!(snapshot_dir)
    else
      [{"error", "spec command '#{spec_cmd}' failed with exit code #{result.exit_code}"}]
    end
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
      Golden.require_equal({{ args[0] }}, {{ args[1] }}, metadata_line: __LINE__, expression: {{ args[1].stringify }}, source_file: __FILE__, module_name: {{ @type.name.id.stringify }})
    {% elsif @def %}
      Golden.require_equal({{ @type.name.id.stringify }} + "/" + {{ @def.name.stringify }}, {{ args[0] }}, metadata_line: __LINE__, expression: {{ args[0].stringify }}, source_file: __FILE__, module_name: {{ @type.name.id.stringify }})
    {% else %}
      Golden.require_equal({{ @type.name.id.stringify }} + "/snapshot_at_{{ __LINE__ }}", {{ args[0] }}, metadata_line: __LINE__, expression: {{ args[0].stringify }}, source_file: __FILE__, module_name: {{ @type.name.id.stringify }})
    {% end %}
  end

  macro assert_json_snapshot(*args)
    {% if args.size == 2 %}
      Golden.require_equal({{ args[0] }}, Golden.apply_path_redactions({{ args[1] }}.to_pretty_json), metadata_line: __LINE__, expression: {{ args[1].stringify }}, source_file: __FILE__, module_name: {{ @type.name.id.stringify }})
    {% elsif @def %}
      Golden.require_equal({{ @type.name.id.stringify }} + "/" + {{ @def.name.stringify }}, Golden.apply_path_redactions({{ args[0] }}.to_pretty_json), metadata_line: __LINE__, expression: {{ args[0].stringify }}, source_file: __FILE__, module_name: {{ @type.name.id.stringify }})
    {% else %}
      Golden.require_equal({{ @type.name.id.stringify }} + "/snapshot_at_{{ __LINE__ }}", Golden.apply_path_redactions({{ args[0] }}.to_pretty_json), metadata_line: __LINE__, expression: {{ args[0].stringify }}, source_file: __FILE__, module_name: {{ @type.name.id.stringify }})
    {% end %}
  end

  macro assert_yaml_snapshot(*args)
    {% if args.size == 2 %}
      Golden.require_equal({{ args[0] }}, Golden.apply_path_redactions({{ args[1] }}.to_yaml), metadata_line: __LINE__, expression: {{ args[1].stringify }}, source_file: __FILE__, module_name: {{ @type.name.id.stringify }})
    {% elsif @def %}
      Golden.require_equal({{ @type.name.id.stringify }} + "/" + {{ @def.name.stringify }}, Golden.apply_path_redactions({{ args[0] }}.to_yaml), metadata_line: __LINE__, expression: {{ args[0].stringify }}, source_file: __FILE__, module_name: {{ @type.name.id.stringify }})
    {% else %}
      Golden.require_equal({{ @type.name.id.stringify }} + "/snapshot_at_{{ __LINE__ }}", Golden.apply_path_redactions({{ args[0] }}.to_yaml), metadata_line: __LINE__, expression: {{ args[0].stringify }}, source_file: __FILE__, module_name: {{ @type.name.id.stringify }})
    {% end %}
  end

  macro assert_binary_snapshot(*args)
    {% if args.size == 2 %}
      Golden.require_equal({{ args[0] }}, Base64.encode({{ args[1] }}), metadata_line: __LINE__, expression: {{ args[1].stringify }}, source_file: __FILE__, module_name: {{ @type.name.id.stringify }})
    {% elsif @def %}
      Golden.require_equal({{ @type.name.id.stringify }} + "/" + {{ @def.name.stringify }}, Base64.encode({{ args[0] }}), metadata_line: __LINE__, expression: {{ args[0].stringify }}, source_file: __FILE__, module_name: {{ @type.name.id.stringify }})
    {% else %}
      Golden.require_equal({{ @type.name.id.stringify }} + "/snapshot_at_{{ __LINE__ }}", Base64.encode({{ args[0] }}), metadata_line: __LINE__, expression: {{ args[0].stringify }}, source_file: __FILE__, module_name: {{ @type.name.id.stringify }})
    {% end %}
  end

  def self.find_spec_dir(start_dir : String = Dir.current) : String?
    dir = start_dir
    loop do
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
    loop do
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

  def self.report_pending!(dir : String? = nil) : String
    search_dir = dir || @@settings.dir
    pending = pending_snapshots(search_dir)
    return "" if pending.empty?
    msg = String.build do |io|
      io << "\n#{pending.size} pending snapshot(s) found.\n"
      pending.each { |pending_path| io << "  #{pending_path}\n" }
      io << "Run `Golden.review!` to review them."
    end
    STDERR.puts msg
    msg
  end

  def self.accept_all!(dir : String? = nil) : Array(String)
    search_dir = dir || @@settings.dir
    pending = Dir.glob(File.join(search_dir, "**/*.golden.new")).sort
    pending.each do |pending_path|
      promote_pending!(pending_path)
    end
    pending.map(&.rchop(".new"))
  end

  def self.reject_all!(dir : String? = nil) : Array(String)
    search_dir = dir || @@settings.dir
    pending = Dir.glob(File.join(search_dir, "**/*.golden.new")).sort
    pending.each { |pending_path| discard_pending!(pending_path) }
    pending
  end

  def self.glob_snapshots(pattern : String, test_data_dir : String? = nil, & : String -> String)
    Dir.glob(pattern).sort.each do |path|
      test_name = File.basename(path, File.extname(path))
      output = yield path
      require_equal(test_name, output, test_data_dir, input_file: path)
    end
  end

  def self.spec_test_data_dir : String?
    if spec_dir = find_spec_dir
      File.join(spec_dir, "testdata")
    end
  end

  def self.require_equal(test_name : String, output : String | Bytes, test_data_dir : String? = nil,
                         metadata_line : Int32? = nil, expression : String? = nil,
                         source_file : String? = nil, input_file : String? = nil,
                         module_name : String? = nil)
    dir = test_data_dir || @@settings.dir
    full_name = compose_snapshot_name(test_name, module_name)
    golden_path = File.join(dir, "#{full_name}.golden")
    pending_path = golden_path + ".new"
    output_str = output.is_a?(Bytes) ? String.new(output) : output
    processed_output = process_output(output_str)
    if (ser_name = @@settings.serializer) && (ser = @@serializers[ser_name]?)
      processed_output = ser.call(processed_output)
    end
    check_duplicate!(full_name, processed_output)
    @@accessed_snapshots.add(golden_path)

    mode = effective_update_mode

    case mode
    in UpdateMode::Always
      write_file(golden_path, processed_output)
      write_metadata(golden_path, full_name, metadata_line,
        expression: expression, source_file: source_file, input_file: input_file)
    in UpdateMode::No
      compare_strict(golden_path, processed_output)
    in UpdateMode::New
      handle_pending(golden_path, pending_path, processed_output,
        full_name, metadata_line, expression, source_file, input_file)
    in UpdateMode::Unseen
      handle_unseen(golden_path, pending_path, processed_output,
        full_name, metadata_line, expression, source_file, input_file)
    in UpdateMode::Auto
      if ci?
        compare_strict(golden_path, processed_output)
      else
        handle_pending(golden_path, pending_path, processed_output,
          full_name, metadata_line, expression, source_file, input_file)
      end
    end
  end

  private def self.effective_update_mode : UpdateMode
    @@settings.update_mode
  end

  private def self.ci? : Bool
    ENV["CI"]? == "true" || ENV["TF_BUILD"]? != nil
  end

  private def self.force_pass? : Bool
    ENV["GOLDEN_FORCE_PASS"]? == "1"
  end

  private def self.write_file(path : String, content : String)
    FileUtils.mkdir_p(File.dirname(path), mode: 0o750)
    tmp = File.join(File.dirname(path), ".golden_tmp_#{Process.pid}_#{Random.rand(10_000)}")
    File.write(tmp, content, perm: 0o600)
    File.rename(tmp, path)
  end

  def self.write_metadata(golden_path : String, name : String, line : Int32?,
                          expression : String? = nil, source_file : String? = nil,
                          input_file : String? = nil)
    write_metadata_file(golden_path + ".meta",
      build_metadata(name, line, expression, source_file, input_file))
  end

  private def self.write_metadata_file(meta_path : String, fields : Hash(String, JSON::Any)) : Nil
    File.write(meta_path, fields.to_pretty_json)
  end

  # Promotes a pending snapshot to a golden file, carrying its metadata sidecar.
  def self.promote_pending!(pending_path : String, name : String? = nil) : String
    golden_path = pending_path.rchop(".new")
    pending_meta = pending_path + ".meta"
    FileUtils.mv(pending_path, golden_path)
    if File.exists?(pending_meta)
      FileUtils.mv(pending_meta, golden_path + ".meta")
    else
      write_metadata(golden_path, name || File.basename(golden_path, ".golden"), nil)
    end
    golden_path
  end

  # Removes a pending snapshot and its metadata sidecar.
  def self.discard_pending!(pending_path : String)
    delete_file(pending_path)
    delete_file(pending_path + ".meta")
  end

  private def self.build_metadata(name : String, line : Int32?, expression : String?,
                                  source_file : String?, input_file : String?) : Hash(String, JSON::Any)
    fields = {} of String => JSON::Any
    fields["name"] = JSON::Any.new(name)
    fields["created_at"] = JSON::Any.new(Time.utc.to_rfc3339)
    fields["line"] = line ? JSON::Any.new(line.to_i64) : JSON::Any.new(nil)
    unless @@settings.omit_expression?
      if exp = expression
        fields["expression"] = JSON::Any.new(exp)
      end
    end
    if desc = @@settings.description
      fields["description"] = JSON::Any.new(desc)
    end
    if inf = @@settings.info
      fields["info"] = JSON::Any.new(inf)
    end
    if inp = input_file || @@settings.input_file
      fields["input_file"] = JSON::Any.new(inp)
    end
    if src = relative_source(source_file)
      fields["source_file"] = JSON::Any.new(src)
    end
    fields
  end

  private def self.relative_source(source_file : String?) : String?
    return nil unless source_file
    return source_file unless Path[source_file].absolute?
    if root = find_project_root(Dir.current)
      root_abs = File.expand_path(root)
      prefix = root_abs.ends_with?(File::SEPARATOR) ? root_abs : root_abs + File::SEPARATOR
      abs = File.expand_path(source_file)
      return abs[prefix.size..] if abs.starts_with?(prefix)
    end
    source_file
  end

  def self.snapshot_metadata(name : String, test_data_dir : String? = nil) : Hash(String, JSON::Any)?
    dir = test_data_dir || @@settings.dir
    full_name = compose_snapshot_name(name, nil)
    meta_path = File.join(dir, "#{full_name}.golden.meta")
    return unless File.exists?(meta_path)
    JSON.parse(File.read(meta_path)).as_h
  end

  private def self.compose_snapshot_name(test_name : String, module_name : String?) : String
    name = test_name
    if @@settings.prepend_module_to_snapshot?
      if mod = module_name
        unless mod.empty? || name.starts_with?(mod + "/")
          name = File.join(mod, name)
        end
      end
    end
    unless @@settings.snapshot_suffix.empty?
      name = "#{name}@#{@@settings.snapshot_suffix}"
    end
    @@group.empty? ? name : File.join(@@group, name)
  end

  private def self.check_duplicate!(name : String, content : String)
    return unless @@settings.allow_duplicates?
    if previous = @@duplicate_snapshots[name]?
      unless previous == content
        raise "snapshot assertion for '#{name}' does not match the previous snapshot in the allow-duplicates block"
      end
    else
      @@duplicate_snapshots[name] = content
    end
  end

  def self.apply_path_redactions(output : String) : String
    return output if @@settings.path_redactions.empty?
    begin
      parsed = JSON.parse(output)
      @@settings.path_redactions.each do |path_redaction|
        parsed = walk_and_replace_json(parsed, parse_path(path_redaction[:path]), JSON::Any.new(path_redaction[:replacement].strip('"')))
      end
      parsed.to_pretty_json
    rescue
      output
    end
  end

  private def self.parse_path(path : String) : Array(String)
    segments = [] of String
    path.split(".").each do |part|
      if bracket_idx = part.index('[')
        segments << part[0...bracket_idx] if part[0...bracket_idx] != ""
        inner = part[bracket_idx..]
        inner.scan(/\[([^\]]+)\]/) do |match|
          segments << match[1]
        end
      else
        segments << part
      end
    end
    segments
  end

  private def self.walk_and_replace_json(node : JSON::Any, segs : Array(String), replacement : JSON::Any) : JSON::Any
    return replacement if segs.empty?
    head = segs.first
    tail = segs[1..]
    case node.raw
    when Hash
      h = node.as_h
      if h.has_key?(head)
        h[head] = walk_and_replace_json(h[head], tail, replacement)
      end
      JSON::Any.new(h)
    when Array
      a = node.as_a
      if head == "*"
        a = a.map { |elem| walk_and_replace_json(elem, tail, replacement) }
      elsif idx = head.to_i?
        a[idx] = walk_and_replace_json(a[idx], tail, replacement) if idx < a.size
      end
      JSON::Any.new(a)
    else
      node
    end
  end

  private def self.process_output(input : String) : String
    result = input
    @@settings.redactions.each { |redaction| result = redaction.apply(result) }
    @@settings.filters.each { |filter| result = filter.call(result) }
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

  private def self.handle_pending(golden_path : String, pending_path : String, output : String,
                                  test_name : String? = nil, metadata_line : Int32? = nil,
                                  expression : String? = nil, source_file : String? = nil,
                                  input_file : String? = nil)
    pending_meta = pending_path + ".meta"
    if File.exists?(golden_path)
      golden_content = File.read(golden_path)
      golden_str = normalize(golden_content)
      out_str = normalize(output)

      if compare_outputs(golden_str, out_str)
        delete_file(pending_path)
        delete_file(pending_meta)
        return
      end

      write_file(pending_path, output)
      write_pending_metadata(pending_meta, test_name, metadata_line, expression, source_file, input_file)
      if force_pass?
        return
      end
      diff = unified_diff("golden", "run", golden_str, out_str)
      raise "output does not match, expected:\n\n#{golden_str}\n\ngot:\n\n#{out_str}\n\ndiff:\n\n#{diff}"
    else
      write_file(pending_path, output)
      write_pending_metadata(pending_meta, test_name, metadata_line, expression, source_file, input_file)
      if force_pass?
        return
      end
      raise "New golden file: #{golden_path}. Run with GOLDEN_UPDATE=1 or cargo-insta to accept."
    end
  end

  private def self.write_pending_metadata(pending_meta : String, test_name : String?,
                                          metadata_line : Int32?, expression : String?,
                                          source_file : String?, input_file : String?)
    return unless test_name
    write_metadata_file(pending_meta,
      build_metadata(test_name, metadata_line, expression, source_file, input_file))
  end

  private def self.handle_unseen(golden_path : String, pending_path : String, output : String,
                                 test_name : String? = nil, metadata_line : Int32? = nil,
                                 expression : String? = nil, source_file : String? = nil,
                                 input_file : String? = nil)
    unless File.exists?(golden_path)
      write_file(golden_path, output)
      if test_name
        write_metadata(golden_path, test_name, metadata_line,
          expression: expression, source_file: source_file, input_file: input_file)
      end
      return
    end

    golden_content = File.read(golden_path)
    golden_str = normalize(golden_content)
    out_str = normalize(output)

    if compare_outputs(golden_str, out_str)
      delete_file(pending_path)
      delete_file(pending_path + ".meta")
      return
    end

    write_file(pending_path, output)
    write_pending_metadata(pending_path + ".meta", test_name, metadata_line, expression, source_file, input_file)
    diff = unified_diff("golden", "run", golden_str, out_str)
    raise "output does not match, expected:\n\n#{golden_str}\n\ngot:\n\n#{out_str}\n\ndiff:\n\n#{diff}"
  end

  private def self.delete_file(path : String)
    File.delete(path) if File.exists?(path)
  end

  def self.normalize(input : String) : String
    str = normalize_windows_line_breaks(input)
    escape_seqs(str)
  end

  def self.unified_diff(a_label : String, b_label : String, a : String, b : String) : String
    diff = Similar::TextDiff.from_lines(a, b)
    diff.unified_diff.header(a_label, b_label).to_s
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
end
