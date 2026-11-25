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

  # One segment of a path selector such as `.users[].id`.
  enum SegmentKind
    Key
    Index
    Wildcard
    DeepWildcard
    Range
  end

  struct SelectorSegment
    getter kind : SegmentKind
    getter key : String?
    getter index : Int32?
    getter from : Int32?
    getter to : Int32?

    def initialize(@kind, @key = nil, @index = nil, @from = nil, @to = nil)
    end
  end

  # A value transform used by path redactions.
  struct ValueRedaction
    getter transform : Proc(JSON::Any, String, JSON::Any)

    def initialize(@transform : Proc(JSON::Any, String, JSON::Any))
    end
  end

  # A selector bound to a value transform.
  struct PathRedaction
    getter selector : String
    getter segments : Array(Array(SelectorSegment))
    getter transform : Proc(JSON::Any, String, JSON::Any)

    def initialize(@selector : String, @segments : Array(Array(SelectorSegment)),
                   @transform : Proc(JSON::Any, String, JSON::Any))
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
    property path_redactions : Array(PathRedaction)
    property comparator : Comparator?
    property serializer : Symbol?
    property description : String?
    property info : String?
    property input_file : String?
    property? omit_expression : Bool
    property? strip_ansi_escape_codes : Bool
    property? sort_maps : Bool
    property sort_selector : String?
    property? allow_empty_glob : Bool
    property snapshot_suffix : String
    property? prepend_module_to_snapshot : Bool
    property? allow_duplicates : Bool

    def initialize(@update_mode = UpdateMode::Auto, @dir = "testdata",
                   @description : String? = nil, @info : String? = nil,
                   @input_file : String? = nil, @omit_expression = false,
                   @snapshot_suffix = "", @prepend_module_to_snapshot = false,
                   @allow_duplicates = false, @strip_ansi_escape_codes = false,
                   @sort_maps = false, @allow_empty_glob = false, @sort_selector : String? = nil)
      @filters = [] of String -> String
      @redactions = [] of Redaction
      @path_redactions = [] of PathRedaction
      @comparator = nil
      @serializer = nil
    end

    def has_info? : Bool
      !@info.nil?
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
      @@settings.prepend_module_to_snapshot?, @@settings.allow_duplicates?,
      @@settings.strip_ansi_escape_codes?, @@settings.sort_maps?,
      @@settings.allow_empty_glob?, @@settings.sort_selector)
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
                         allow_duplicates : Bool? = nil, strip_ansi_escape_codes : Bool? = nil,
                         sort_maps : Bool? = nil, allow_empty_glob : Bool? = nil,
                         sort_selector : String? = nil, &)
    old = @@settings
    begin
      s = clone_settings
      apply_value_settings(s, update_mode, dir, serializer, description, info, input_file, omit_expression)
      apply_toggle_settings(s, snapshot_suffix, prepend_module_to_snapshot, allow_duplicates,
        strip_ansi_escape_codes, sort_maps, allow_empty_glob)
      s.sort_selector = sort_selector || s.sort_selector
      @@settings = s
      yield
    ensure
      @@settings = old
    end
  end

  private def self.apply_value_settings(s : Settings, update_mode : UpdateMode?, dir : String?,
                                        serializer : Symbol?, description : String?, info : String?,
                                        input_file : String?, omit_expression : Bool?) : Nil
    s.update_mode = update_mode || s.update_mode
    s.dir = dir || s.dir
    s.serializer = serializer || s.serializer
    s.description = description || s.description
    s.info = info || s.info
    s.input_file = input_file || s.input_file
    s.omit_expression = omit_expression || s.omit_expression?
  end

  private def self.apply_toggle_settings(s : Settings, snapshot_suffix : String?,
                                         prepend_module_to_snapshot : Bool?, allow_duplicates : Bool?,
                                         strip_ansi_escape_codes : Bool?, sort_maps : Bool?,
                                         allow_empty_glob : Bool?) : Nil
    s.snapshot_suffix = snapshot_suffix || s.snapshot_suffix
    s.prepend_module_to_snapshot = prepend_module_to_snapshot || s.prepend_module_to_snapshot?
    s.allow_duplicates = allow_duplicates || s.allow_duplicates?
    s.strip_ansi_escape_codes = strip_ansi_escape_codes || s.strip_ansi_escape_codes?
    s.sort_maps = sort_maps || s.sort_maps?
    s.allow_empty_glob = allow_empty_glob || s.allow_empty_glob?
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

  def self.add_path_redaction(selector : String, replacement : String)
    add_path_redaction(selector, ValueRedaction.new(->(_value : JSON::Any, _path : String) { JSON::Any.new(replacement) }))
  end

  def self.add_path_redaction(selector : String, redaction : ValueRedaction)
    @@settings.path_redactions << PathRedaction.new(selector, parse_selectors(selector), redaction.transform)
  end

  def self.add_dynamic_redaction(selector : String, &block : JSON::Any, String -> JSON::Any)
    add_path_redaction(selector, dynamic_redaction(&block))
  end

  # Builds a redaction whose replacement is computed from the matched value and
  # its dotted path (for example `.user.email`).
  def self.dynamic_redaction(&block : JSON::Any, String -> JSON::Any) : ValueRedaction
    ValueRedaction.new(block)
  end

  # Rounds floating point numbers at the matched path to `decimals` places.
  def self.rounded_redaction(decimals : Int32 = 2) : ValueRedaction
    ValueRedaction.new(->(value : JSON::Any, _path : String) { round_json_number(value, decimals) })
  end

  # Sorts arrays and object keys at the matched path.
  def self.sorted_redaction : ValueRedaction
    ValueRedaction.new(->(value : JSON::Any, _path : String) { sort_json_collection(value) })
  end

  def self.clear_filters
    @@settings.filters.clear
  end

  def self.clear_redactions
    @@settings.redactions.clear
    @@settings.path_redactions.clear
  end

  def self.remove_description
    @@settings.description = nil
  end

  def self.remove_info
    @@settings.info = nil
  end

  def self.remove_input_file
    @@settings.input_file = nil
  end

  def self.remove_snapshot_suffix
    @@settings.snapshot_suffix = ""
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
      Golden.require_equal({{ args[0] }}, Golden.apply_path_redactions(Golden.format_json({{ args[1] }})), metadata_line: __LINE__, expression: {{ args[1].stringify }}, source_file: __FILE__, module_name: {{ @type.name.id.stringify }})
    {% elsif @def %}
      Golden.require_equal({{ @type.name.id.stringify }} + "/" + {{ @def.name.stringify }}, Golden.apply_path_redactions(Golden.format_json({{ args[0] }})), metadata_line: __LINE__, expression: {{ args[0].stringify }}, source_file: __FILE__, module_name: {{ @type.name.id.stringify }})
    {% else %}
      Golden.require_equal({{ @type.name.id.stringify }} + "/snapshot_at_{{ __LINE__ }}", Golden.apply_path_redactions(Golden.format_json({{ args[0] }})), metadata_line: __LINE__, expression: {{ args[0].stringify }}, source_file: __FILE__, module_name: {{ @type.name.id.stringify }})
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
    matches = Dir.glob(pattern).sort
    if matches.empty? && !@@settings.allow_empty_glob?
      raise "glob pattern did not match any files: #{pattern}"
    end
    matches.each do |path|
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
      @@settings.path_redactions.each do |redaction|
        parsed = redact_json(parsed, redaction.segments, redaction.transform, [] of PathItem)
      end
      parsed.to_pretty_json
    rescue
      output
    end
  end

  private struct PathItem
    getter key : String?
    getter index : Int32?
    getter length : Int32?

    def initialize(@key = nil, @index = nil, @length = nil)
    end
  end

  private def self.redact_json(node : JSON::Any, selectors : Array(Array(SelectorSegment)),
                               transform : Proc(JSON::Any, String, JSON::Any),
                               path : Array(PathItem)) : JSON::Any
    if selectors.any? { |segments| selector_matches?(segments, path) }
      return transform.call(node, path_to_string(path))
    end

    case raw = node.raw
    when Hash
      updated = {} of String => JSON::Any
      raw.each do |key, value|
        updated[key] = redact_json(value, selectors, transform, path + [PathItem.new(key: key)])
      end
      JSON::Any.new(updated)
    when Array
      updated = raw.map_with_index do |value, index|
        redact_json(value, selectors, transform, path + [PathItem.new(index: index, length: raw.size)])
      end
      JSON::Any.new(updated)
    else
      node
    end
  end

  private def self.selector_matches?(segments : Array(SelectorSegment), path : Array(PathItem)) : Bool
    if deep_idx = segments.index(&.kind.deep_wildcard?)
      return false if path.size <= deep_idx
      segments[0...deep_idx].each_with_index do |segment, idx|
        return false unless segment_matches?(segment, path[idx])
      end
      backward = segments[(deep_idx + 1)..]
      backward.each_with_index do |segment, idx|
        return false unless segment_matches?(segment, path[path.size - 1 - idx])
      end
      true
    else
      return false unless segments.size == path.size
      segments.each_with_index.all? { |segment, idx| segment_matches?(segment, path[idx]) }
    end
  end

  private def self.segment_matches?(segment : SelectorSegment, item : PathItem) : Bool
    case segment.kind
    when SegmentKind::Wildcard, SegmentKind::DeepWildcard
      true
    when SegmentKind::Key
      item.key == segment.key
    when SegmentKind::Index
      item.index == segment.index
    when SegmentKind::Range
      index = item.index
      return false unless index
      length = item.length || 0
      from = segment.from
      to = segment.to
      lower = from ? (from < 0 ? {length + from, 0}.max : from) : 0
      upper = to ? (to < 0 ? {length + to, 0}.max : to) : length
      index >= lower && index < upper
    else
      false
    end
  end

  private def self.path_to_string(path : Array(PathItem)) : String
    path.map { |item| item.key ? ".#{item.key}" : ".#{item.index}" }.join
  end

  private def self.parse_selectors(selector : String) : Array(Array(SelectorSegment))
    split_selectors(selector).map { |part| parse_segments(part, selector) }
  end

  private def self.split_selectors(input : String) : Array(String)
    parts = [] of String
    buffer = String::Builder.new
    in_string = false
    escaped = false
    depth = 0
    input.each_char do |char|
      if in_string
        buffer << char
        if escaped
          escaped = false
        elsif char == '\\'
          escaped = true
        elsif char == '"'
          in_string = false
        end
      else
        case char
        when '"'
          in_string = true
          buffer << char
        when '['
          depth += 1
          buffer << char
        when ']'
          depth -= 1
          buffer << char
        when ','
          if depth.zero?
            parts << buffer.to_s
            buffer = String::Builder.new
          else
            buffer << char
          end
        else
          buffer << char
        end
      end
    end
    parts << buffer.to_s
    parts.map(&.strip).reject(&.empty?)
  end

  private def self.parse_segments(selector : String, original : String) : Array(SelectorSegment)
    text = selector.strip.gsub("[*]", "[]")
    return [] of SelectorSegment if text.empty? || text == "."
    text = "." + text unless text.starts_with?('.')
    segments = [] of SelectorSegment
    idx = 0
    while idx < text.size
      case text[idx]
      when '.'
        idx = parse_dot_segment(text, idx + 1, segments, original)
      when '['
        close = closing_bracket(text, idx)
        raise ArgumentError.new("invalid selector: #{original}") unless close
        segments << parse_subscript(text[(idx + 1)...close].strip, original)
        idx = close + 1
      else
        raise ArgumentError.new("invalid selector: #{original}")
      end
    end
    segments
  end

  private def self.parse_dot_segment(text : String, idx : Int32,
                                     segments : Array(SelectorSegment), original : String) : Int32
    if idx < text.size && text[idx] == '['
      # A dot before a subscript is decorative (`.users[]`).
      return idx
    end

    if idx < text.size && text[idx] == '*'
      if idx + 1 < text.size && text[idx + 1] == '*'
        segments << SelectorSegment.new(SegmentKind::DeepWildcard)
        return idx + 2
      end
      segments << SelectorSegment.new(SegmentKind::Wildcard)
      return idx + 1
    end

    start = idx
    while idx < text.size && text[idx] != '.' && text[idx] != '['
      idx += 1
    end
    key = text[start...idx]
    raise ArgumentError.new("invalid selector: #{original}") if key.empty?
    segments << SelectorSegment.new(SegmentKind::Key, key: key)
    idx
  end

  private def self.closing_bracket(text : String, open : Int32) : Int32?
    in_string = false
    escaped = false
    idx = open + 1
    while idx < text.size
      char = text[idx]
      if in_string
        if escaped
          escaped = false
        elsif char == '\\'
          escaped = true
        elsif char == '"'
          in_string = false
        end
      else
        case char
        when '"' then in_string = true
        when ']' then return idx
        end
      end
      idx += 1
    end
    nil
  end

  private def self.parse_subscript(content : String, original : String) : SelectorSegment
    if content.empty?
      SelectorSegment.new(SegmentKind::Range)
    elsif content.starts_with?('"')
      key = content[1...-1].gsub("\\\\", "\\").gsub("\\\"", "\"")
      SelectorSegment.new(SegmentKind::Key, key: key)
    elsif content.includes?(':')
      parts = content.split(':', 2)
      from = parts[0].empty? ? nil : parts[0].to_i?
      to = parts[1].empty? ? nil : parts[1].to_i?
      raise ArgumentError.new("invalid selector: #{original}") if from.nil? && !parts[0].empty?
      raise ArgumentError.new("invalid selector: #{original}") if to.nil? && !parts[1].empty?
      SelectorSegment.new(SegmentKind::Range, from: from, to: to)
    else
      index = content.to_i?
      raise ArgumentError.new("invalid selector: #{original}") unless index
      SelectorSegment.new(SegmentKind::Index, index: index)
    end
  end

  private def self.round_json_number(value : JSON::Any, decimals : Int32) : JSON::Any
    raw = value.raw
    if raw.is_a?(Float64)
      scale = 10.0 ** decimals
      JSON::Any.new((raw * scale).round / scale)
    else
      value
    end
  end

  private def self.sort_json_collection(value : JSON::Any) : JSON::Any
    case raw = value.raw
    when Array
      compared = raw.sort do |a, b|
        compare_json_values(a, b)
      end
      JSON::Any.new(compared)
    when Hash
      sorted = {} of String => JSON::Any
      raw.keys.sort!.each { |key| sorted[key] = raw[key] }
      JSON::Any.new(sorted)
    else
      value
    end
  end

  private def self.compare_json_values(a : JSON::Any, b : JSON::Any) : Int32
    raw_a = a.raw
    raw_b = b.raw
    if raw_a.is_a?(Number) && raw_b.is_a?(Number)
      (raw_a.to_f <=> raw_b.to_f) || 0
    else
      a.to_json <=> b.to_json
    end
  end

  private def self.process_output(input : String) : String
    result = input
    if @@settings.strip_ansi_escape_codes?
      result = strip_ansi_escape_codes(result)
    end
    @@settings.redactions.each { |redaction| result = redaction.apply(result) }
    @@settings.filters.each { |filter| result = filter.call(result) }
    result
  end

  # Strips ANSI CSI escape sequences (colors, styles, cursor movement).
  def self.strip_ansi_escape_codes(input : String) : String
    return input unless input.includes?('\e')
    input.gsub(/\e\[[0-9;?]*[A-Za-z]/, "")
  end

  # Serializes a value as pretty JSON, sorting maps when `sort_maps` is set or
  # the objects selected by `sort_selector`.
  def self.format_json(value) : String
    json = value.to_pretty_json
    if selector = @@settings.sort_selector
      sorted = redact_json(JSON.parse(json), parse_selectors(selector),
        sorted_redaction.transform, [] of PathItem)
      sorted.to_pretty_json
    elsif @@settings.sort_maps?
      sort_json_maps(json)
    else
      json
    end
  end

  private def self.sort_json_maps(json : String) : String
    sort_json_value(JSON.parse(json)).to_pretty_json
  end

  private def self.sort_json_value(value : JSON::Any) : JSON::Any
    case raw = value.raw
    when Hash
      sorted = {} of String => JSON::Any
      raw.keys.sort!.each { |key| sorted[key] = sort_json_value(raw[key]) }
      JSON::Any.new(sorted)
    when Array
      JSON::Any.new(raw.map { |element| sort_json_value(element) })
    else
      value
    end
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
      raise mismatch_error(golden_path, golden_str, out_str)
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
      raise mismatch_error(golden_path, golden_str, out_str)
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
    raise mismatch_error(golden_path, golden_str, out_str)
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

  # Builds the mismatch message, delegating rendering to `GOLDEN_DIFF_TOOL`
  # (or `INSTA_DIFF_TOOL`) when set. The built-in diff is still computed with
  # `similar` and is the fallback.
  private def self.mismatch_error(golden_path : String, expected : String, actual : String) : String
    message = "output does not match, expected:\n\n#{expected}\n\ngot:\n\n#{actual}"
    if tool = ENV["GOLDEN_DIFF_TOOL"]? || ENV["INSTA_DIFF_TOOL"]?
      return message if invoke_external_diff_tool(tool, expected, actual, golden_path)
    end
    "#{message}\n\ndiff:\n\n#{unified_diff("golden", "run", expected, actual)}"
  end

  # Runs an external diff tool over temporary copies of the two snapshots.
  # Returns false when the tool cannot be created or exits non-zero.
  def self.invoke_external_diff_tool(tool : String, old_content : String, new_content : String,
                                     snapshot_file : String? = nil) : Bool
    dir = File.join(Dir.tempdir, "golden_diff_#{Process.pid}_#{Random.rand(1_000_000)}")
    base = snapshot_file ? File.basename(snapshot_file, ".golden") : "snapshot"
    old_path = File.join(dir, "#{base}.old.golden")
    new_path = File.join(dir, "#{base}.new.golden")
    FileUtils.mkdir_p(dir)
    File.write(old_path, old_content)
    File.write(new_path, new_content)
    command = "#{tool} #{shell_quote(old_path)} #{shell_quote(new_path)}"
    status = Process.run("sh", ["-c", command], chdir: dir, output: :inherit, error: :inherit)
    status.success?
  rescue
    false
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  private def self.shell_quote(value : String) : String
    "'" + value.gsub("'", "'\\''") + "'"
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
