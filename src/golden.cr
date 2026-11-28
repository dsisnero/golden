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

  # What to do with snapshot files no assertion referenced during the run.
  # Mirrors insta's `test.unreferenced` / `cargo insta test --unreferenced`.
  enum UnreferencedMode
    Auto
    Reject
    Delete
    Warn
    Ignore

    # Parses the CLI/config spellings; `error` is accepted as a Reject alias.
    def self.parse(value : String) : UnreferencedMode?
      case value.strip.downcase
      when "auto"            then Auto
      when "reject", "error" then Reject
      when "delete"          then Delete
      when "warn"            then Warn
      when "ignore"          then Ignore
      end
    end

    # `Auto` means Reject in CI and Delete locally, like cargo-insta.
    def resolve(ci : Bool) : UnreferencedMode
      return self unless self.auto?
      ci ? Reject : Delete
    end

    # Lower-case spelling used in configs, env vars, and CLI flags.
    def config_name : String
      to_s.downcase
    end
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

  # Outcome of attempting to patch one pending inline snapshot into its source.
  struct InlinePatchResult
    getter file : String
    getter line : Int32
    getter? patched : Bool
    getter error : String?

    def initialize(@file : String, @line : Int32, @patched : Bool, @error : String? = nil)
    end
  end

  # A pending inline snapshot recorded when the value differs from the literal
  # in the source.
  struct InlineSnapshotPending
    getter file : String
    getter line : Int32
    getter name : String?
    getter old_content : String
    getter new_content : String
    getter created_at : String

    def initialize(@file : String, @line : Int32, @name : String?,
                   @old_content : String, @new_content : String, @created_at : String)
    end
  end

  # Escape sequences understood when decoding inline string literals.
  INLINE_ESCAPES = {
    'n'  => '\n',
    't'  => '\t',
    'r'  => '\r',
    '0'  => '\0',
    'e'  => '\e',
    's'  => ' ',
    'a'  => '\a',
    'b'  => '\b',
    'f'  => '\f',
    'v'  => '\v',
    '\\' => '\\',
    '"'  => '"',
    '\'' => '\'',
  }

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

  # Post-run policy for snapshot files no assertion referenced.
  @@unreferenced = UnreferencedMode::Ignore

  def self.unreferenced : UnreferencedMode
    @@unreferenced
  end

  def self.unreferenced=(mode : UnreferencedMode)
    @@unreferenced = mode
  end

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
    if raw = ENV["GOLDEN_UNREFERENCED"]? || ENV["INSTA_UNREFERENCED"]?
      mode = UnreferencedMode.parse(raw)
      raise "invalid unreferenced mode in GOLDEN_UNREFERENCED: #{raw}" unless mode
      @@unreferenced = mode
    end
    install_exit_reporter! if report_pending_on_exit?
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
    if ur = config["unreferenced"]?
      raw = ur.to_s
      mode = UnreferencedMode.parse(raw)
      raise "invalid unreferenced mode in #{path}: #{raw}" unless mode
      @@unreferenced = mode
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
  @@inline_seen = Set(String).new
  @@exit_reporter_installed = false
  @@exit_report_done = false

  def self.reset_tracking!
    @@accessed_snapshots = Set(String).new
    @@inline_seen = Set(String).new
  end

  def self.unreferenced_snapshots(dir : String? = nil) : Array(String)
    search_dir = dir || @@settings.dir
    referenced = referenced_snapshot_paths
    Dir.glob(File.join(search_dir, "**/*.golden")).sort.reject do |path|
      referenced.includes?(File.expand_path(path))
    end
  end

  # Path of the file the test runner uses to record which snapshots were
  # referenced, from `GOLDEN_SNAPSHOT_REFERENCES_FILE` (or upstream's
  # `INSTA_SNAPSHOT_REFERENCES_FILE`).
  def self.snapshot_references_file : String?
    raw = ENV["GOLDEN_SNAPSHOT_REFERENCES_FILE"]? || ENV["INSTA_SNAPSHOT_REFERENCES_FILE"]?
    return nil if raw.nil?
    path = raw.strip
    path.empty? ? nil : path
  end

  # Appends a snapshot path to the references file so the runner can detect
  # snapshots no assertion touched (upstream `memoize_snapshot_file`). Raises
  # on IO errors, matching upstream's `unwrap`.
  def self.memoize_snapshot_file(snapshot_file : String) : Nil
    return unless path = snapshot_references_file
    File.open(path, "a", &.puts(snapshot_file))
  end

  private def self.clear_snapshot_references_file : Nil
    if path = snapshot_references_file
      File.delete(path) if File.exists?(path)
    end
  end

  private def self.referenced_snapshot_paths : Set(String)
    paths = Set(String).new
    @@accessed_snapshots.each { |path| paths << File.expand_path(path) }
    if ref = snapshot_references_file
      if File.exists?(ref)
        File.read_lines(ref).each do |line|
          value = line.strip
          paths << File.expand_path(value) unless value.empty?
        end
      end
    end
    paths
  end

  # Raised by `handle_unreferenced_snapshots!` under the `reject` policy so the
  # runner fails the run.
  class UnreferencedSnapshotsError < Exception
  end

  # Applies the configured `unreferenced` policy to snapshot files that no
  # assertion referenced. Mirrors cargo-insta's post-run handling: prints to
  # stderr, deletes under `delete`, raises under `reject`, and removes the
  # references file afterwards. `ignore` is a no-op and the default.
  def self.handle_unreferenced_snapshots!(dir : String? = nil,
                                          mode : UnreferencedMode? = nil) : Array(String)
    action = (mode || @@unreferenced).resolve(ci?)
    return [] of String if action.ignore?

    files = unreferenced_snapshots(dir)
    if files.empty?
      STDERR.puts "no unreferenced snapshots found"
    elsif action.delete?
      STDERR.puts "deleted unreferenced snapshots:"
      files.each do |path|
        STDERR.puts "  #{path}"
        delete_file(path)
        delete_file(path + ".meta")
      end
    else
      STDERR.puts "encountered unreferenced snapshots:"
      files.each { |path| STDERR.puts "  #{path}" }
    end
    clear_snapshot_references_file
    if !files.empty? && action.reject?
      raise UnreferencedSnapshotsError.new("aborting because of unreferenced snapshots")
    end
    files
  end

  def self.status(dir : String? = nil) : Hash(String, Int32)
    search_dir = dir || @@settings.dir
    all_golden = Dir.glob(File.join(search_dir, "**/*.golden")).sort
    snapshots = all_golden.count { |path| !path.ends_with?(".golden.new") && !path.ends_with?(".golden.meta") }
    pending = pending_snapshots(search_dir).size
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

  def self.test_and_review!(spec_cmd : String = "crystal spec", snapshot_dir : String? = nil,
                            unreferenced : UnreferencedMode? = nil) : Array(Tuple(String, String))
    env = unreferenced ? {"GOLDEN_UNREFERENCED" => unreferenced.config_name} : nil
    result = Process.run(spec_cmd, shell: true, env: env)
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

  # Compares a value with a literal stored in the source. On mismatch a pending
  # record is stored in `.golden-inline.json` (under `Golden.dir`).
  macro assert_inline_snapshot(value, expected, name = nil)
    Golden.assert_inline({{ value }}, {{ expected }}, {{ name }}, file: __FILE__, line: __LINE__)
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

  # External directory for pending snapshots, from `GOLDEN_PENDING_DIR` (or
  # upstream's `INSTA_PENDING_DIR`). An empty value behaves as unset.
  def self.pending_dir : String?
    raw = ENV["GOLDEN_PENDING_DIR"]? || ENV["INSTA_PENDING_DIR"]?
    return nil if raw.nil?
    dir = raw.strip
    dir.empty? ? nil : dir
  end

  # Path that receives a pending snapshot for `golden_path`. With an external
  # pending directory configured, the path mirrors the snapshot's path relative
  # to `dir` under that directory (upstream `pending_snapshot_path`).
  def self.pending_snapshot_path(golden_path : String, dir : String? = nil) : String
    external = pending_dir
    return golden_path + ".new" unless external

    base = dir || @@settings.dir
    relative = relative_to_dir(golden_path, base)
    if relative.split(File::SEPARATOR).includes?("..")
      raise "GOLDEN_PENDING_DIR is set but snapshot path #{golden_path} " \
            "would escape the pending directory (relative path contains \"..\")"
    end
    File.join(external, relative + ".new")
  end

  # Inverse of `pending_snapshot_path`: the `.golden` path a pending snapshot
  # would be promoted to.
  def self.golden_path_for_pending(pending_path : String, dir : String? = nil) : String
    external = pending_dir
    return pending_path.rchop(".new") unless external

    base = dir || @@settings.dir
    prefix = external.ends_with?(File::SEPARATOR) ? external : external + File::SEPARATOR
    unless pending_path.starts_with?(prefix)
      raise "pending snapshot #{pending_path} is outside GOLDEN_PENDING_DIR #{external}"
    end
    File.join(base, pending_path[prefix.size..].rchop(".new"))
  end

  private def self.relative_to_dir(path : String, base : String) : String
    prefix = base.ends_with?(File::SEPARATOR) ? base : base + File::SEPARATOR
    return path[prefix.size..] if path.starts_with?(prefix)
    normalized_base = File.expand_path(base)
    normalized_path = File.expand_path(path)
    normalized_prefix = normalized_base.ends_with?(File::SEPARATOR) ? normalized_base : normalized_base + File::SEPARATOR
    if normalized_path.starts_with?(normalized_prefix)
      return normalized_path[normalized_prefix.size..]
    end
    path
  end

  def self.pending_snapshots(dir : String? = nil) : Array(String)
    search_dir = dir || @@settings.dir
    root = pending_dir || search_dir
    Dir.glob(File.join(root, "**/*.golden.new")).sort
  end

  def self.report_pending!(dir : String? = nil) : String
    search_dir = dir || @@settings.dir
    pending = pending_snapshots(search_dir)
    inline = pending_inline_snapshots(search_dir)
    return "" if pending.empty? && inline.empty?
    msg = String.build do |io|
      io << "\n#{pending.size + inline.size} pending snapshot(s) found.\n"
      pending.each { |pending_path| io << "  #{pending_path}\n" }
      inline.each { |entry| io << "  #{entry.file}:#{entry.line} (inline)\n" }
      io << "Run `golden review` to review them."
    end
    STDERR.puts msg
    msg
  end

  # Whether `Golden.init` installs the end-of-run reporter. Enabled by
  # default; `GOLDEN_REPORT_PENDING=0` (or `false`/`no`/`off`) disables it.
  def self.report_pending_on_exit? : Bool
    value = ENV["GOLDEN_REPORT_PENDING"]?
    return true if value.nil?
    !%w[0 false no off].includes?(value.strip.downcase)
  end

  # Installs a suite/process-end hook that reports pending file and inline
  # snapshots. Mirrors insta-ruby's `PendingReporter.flush_and_report!` wired
  # through RSpec's `after(:suite)` and Minitest's `after_run`: the report is
  # advisory (stderr only) and never changes the exit status. Idempotent.
  #
  # When `spec` is part of the program, the hook runs as
  # `Spec.after_suite` (after the examples). It must not also register
  # `at_exit`: our handler would run *before* the spec runner's own handler,
  # report stale state, and consume the one-shot guard.
  def self.install_exit_reporter! : Nil
    return if @@exit_reporter_installed
    @@exit_reporter_installed = true
    {% if @top_level.has_constant?("Spec") %}
      Spec.after_suite do
        Golden.run_exit_report
      end
    {% else %}
      at_exit do
        Golden.run_exit_report
      end
    {% end %}
  end

  # :nodoc:
  # Runs the end-of-run reports at most once per process: pending snapshots
  # first (errors swallowed), then the unreferenced-snapshot policy (whose
  # `reject` mode intentionally raises so the runner fails).
  def self.run_exit_report
    return if @@exit_report_done
    @@exit_report_done = true
    begin
      report_pending!
    rescue
    end
    handle_unreferenced_snapshots!
  end

  def self.exit_reporter_installed? : Bool
    @@exit_reporter_installed
  end

  def self.accept_all!(dir : String? = nil) : Array(String)
    search_dir = dir || @@settings.dir
    pending = pending_snapshots(search_dir)
    pending.each do |pending_path|
      promote_pending!(pending_path, dir: search_dir)
    end
    pending.map { |pending_path| golden_path_for_pending(pending_path, search_dir) }
  end

  def self.reject_all!(dir : String? = nil) : Array(String)
    search_dir = dir || @@settings.dir
    pending = pending_snapshots(search_dir)
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
    pending_path = pending_snapshot_path(golden_path, dir)
    output_str = output.is_a?(Bytes) ? String.new(output) : output
    processed_output = process_output(output_str)
    if (ser_name = @@settings.serializer) && (ser = @@serializers[ser_name]?)
      processed_output = ser.call(processed_output)
    end
    check_duplicate!(full_name, processed_output)
    @@accessed_snapshots.add(golden_path)
    memoize_snapshot_file(golden_path)

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

  # Asserts an inline snapshot stored in the source. `file` and `line` are
  # supplied by the `assert_inline_snapshot` macro.
  def self.assert_inline(output : String, expected : String, name : String? = nil,
                         *, file : String, line : Int32, root : String? = nil)
    guard_inline_duplicate!(file, line)
    observed = normalize_inline(output)
    wanted = normalize_inline(expected)

    if compare_outputs(wanted, observed)
      clear_inline_pending(file, line)
      return
    end

    record_inline_pending(file, line, name, wanted, observed)

    if @@settings.update_mode.always?
      pending = InlineSnapshotPending.new(file, line, name, wanted, observed, Time.utc.to_rfc3339)
      result = patch_inline_pending(pending, root)
      if result.patched?
        clear_inline_pending(file, line)
        return
      end
      diff = unified_diff("inline", "observed", wanted, observed)
      raise "inline snapshot mismatch at #{file}:#{line}; automatic patch failed: " \
            "#{result.error}\n\n#{diff}"
    end

    return if force_pass?

    diff = unified_diff("inline", "observed", wanted, observed)
    raise "inline snapshot mismatch at #{file}:#{line}\n\n#{diff}\n\n" \
          "Recorded a pending inline snapshot in #{inline_pending_path}."
  end

  # Strips the common indentation and surrounding blank lines of inline
  # snapshot text.
  def self.normalize_inline(input : String) : String
    lines = input.split('\n', remove_empty: false)
    while !lines.empty? && lines.first.strip.empty?
      lines.shift
    end
    while !lines.empty? && lines.last.strip.empty?
      lines.pop
    end
    return "" if lines.empty?

    indents = lines.reject(&.strip.empty?).map { |line| line.size - line.lstrip.size }
    common = indents.min? || 0
    lines.map { |line| common.zero? ? line : (line.size >= common ? line[common..] : line.strip) }.join("\n")
  end

  # Path of the pending inline registry, stored under the snapshot directory.
  def self.inline_pending_path(dir : String? = nil) : String
    File.join(dir || @@settings.dir, ".golden-inline.json")
  end

  def self.pending_inline_snapshots(dir : String? = nil) : Array(InlineSnapshotPending)
    load_inline_registry(dir).values.compact_map do |entry|
      file = entry["file"]?.try(&.as_s?)
      line = entry["line"]?.try(&.as_i?)
      next unless file && line
      InlineSnapshotPending.new(
        file,
        line,
        entry["name"]?.try(&.as_s?),
        entry["old"]?.try(&.as_s?) || "",
        entry["new"]?.try(&.as_s?) || "",
        entry["created_at"]?.try(&.as_s?) || ""
      )
    end
  end

  def self.reject_inline_snapshots!(dir : String? = nil)
    path = inline_pending_path(dir)
    delete_file(path) if File.exists?(path)
  end

  # Patches one pending inline snapshot into its source and drops the registry
  # entry on success. Failures leave the entry in place so it can be retried.
  def self.accept_inline_entry(pending : InlineSnapshotPending, dir : String? = nil,
                               root : String? = nil, dry_run : Bool = false) : InlinePatchResult
    result = patch_inline_pending(pending, root, write: !dry_run)
    if result.patched? && !dry_run
      registry = load_inline_registry(dir)
      if registry.delete(inline_registry_key(pending.file, pending.line))
        write_inline_registry(registry, dir)
      end
    end
    result
  end

  # Drops one pending inline snapshot without patching its source.
  def self.reject_inline_entry(pending : InlineSnapshotPending, dir : String? = nil)
    registry = load_inline_registry(dir)
    if registry.delete(inline_registry_key(pending.file, pending.line))
      write_inline_registry(registry, dir)
    end
  end

  private def self.inline_registry_key(file : String, line : Int32) : String
    "#{file}:#{line}"
  end

  # Applies every pending inline snapshot that can be patched safely. Failed
  # entries stay in the registry.
  def self.accept_inline!(dir : String? = nil, root : String? = nil,
                          dry_run : Bool = false) : Array(InlinePatchResult)
    registry = load_inline_registry(dir)
    results = [] of InlinePatchResult
    registry.keys.each do |key|
      entry = registry[key]?
      next unless entry
      pending = inline_pending_from_entry(entry)
      next unless pending
      result = patch_inline_pending(pending, root, write: !dry_run)
      results << result
      registry.delete(key) if result.patched? && !dry_run
    end
    write_inline_registry(registry, dir) unless dry_run
    results
  end

  private struct LiteralToken
    getter start : Int32
    getter finish : Int32
    getter value : String

    def initialize(@start : Int32, @finish : Int32, @value : String)
    end
  end

  private def self.patch_inline_pending(pending : InlineSnapshotPending, root : String? = nil,
                                        write : Bool = true) : InlinePatchResult
    root_dir = File.expand_path(root || find_project_root(Dir.current) || Dir.current)
    path = Path[pending.file].absolute? ? File.expand_path(pending.file) : File.expand_path(pending.file, root_dir)
    if error = inline_path_error(path, root_dir)
      return InlinePatchResult.new(pending.file, pending.line, false, error)
    end
    if pending.new_content.includes?('\n')
      return InlinePatchResult.new(pending.file, pending.line, false,
        "multi-line inline values cannot be patched")
    end

    apply_inline_patch(path, pending, write)
  rescue ex
    InlinePatchResult.new(pending.file, pending.line, false, ex.message || ex.class.name)
  end

  private def self.inline_path_error(path : String, root_dir : String) : String?
    prefix = root_dir.ends_with?(File::SEPARATOR) ? root_dir : root_dir + File::SEPARATOR
    unless path == root_dir || path.starts_with?(prefix)
      return "file is outside the project root"
    end
    return "file does not exist" unless File.exists?(path)
    nil
  end

  private def self.apply_inline_patch(path : String, pending : InlineSnapshotPending,
                                      write : Bool) : InlinePatchResult
    lines = File.read_lines(path, chomp: false)
    index = pending.line - 1
    unless 0 <= index < lines.size
      return InlinePatchResult.new(pending.file, pending.line, false, "line is outside the file")
    end

    original = lines[index]
    eol = original.ends_with?("\r\n") ? "\r\n" : (original.ends_with?('\n') ? "\n" : "")
    body = eol.empty? ? original : original[0...-eol.size]
    matches = scan_literals(body).select { |token| token.value == pending.old_content }
    if matches.size != 1
      return InlinePatchResult.new(pending.file, pending.line, false,
        "expected exactly one literal matching the old value, found #{matches.size}")
    end

    token = matches.first
    patched = body[0...token.start] + encode_literal(pending.new_content) + body[token.finish..]
    lines[index] = patched + eol
    write_source_file(path, lines.join) if write
    InlinePatchResult.new(pending.file, pending.line, true)
  rescue ex
    InlinePatchResult.new(pending.file, pending.line, false, ex.message || ex.class.name)
  end

  private def self.inline_pending_from_entry(entry : JSON::Any) : InlineSnapshotPending?
    file = entry["file"]?.try(&.as_s?)
    line = entry["line"]?.try(&.as_i?)
    return nil unless file && line
    InlineSnapshotPending.new(
      file,
      line,
      entry["name"]?.try(&.as_s?),
      entry["old"]?.try(&.as_s?) || "",
      entry["new"]?.try(&.as_s?) || "",
      entry["created_at"]?.try(&.as_s?) || ""
    )
  end

  private def self.write_inline_registry(registry : Hash(String, JSON::Any), dir : String? = nil)
    if registry.empty?
      reject_inline_snapshots!(dir)
    else
      write_file(inline_pending_path(dir), registry.to_pretty_json)
    end
  end

  private def self.write_source_file(path : String, content : String)
    tmp = File.join(File.dirname(path), ".golden_patch_#{Process.pid}_#{Random.rand(1_000_000)}")
    File.write(tmp, content)
    File.rename(tmp, path)
  end

  private def self.encode_literal(value : String) : String
    escaped = value.gsub("\\", "\\\\")
      .gsub("\"", "\\\"")
      .gsub("\n", "\\n")
      .gsub("\t", "\\t")
      .gsub("\r", "\\r")
      .gsub("\e", "\\e")
    "\"#{escaped}\""
  end

  private def self.scan_literals(line : String) : Array(LiteralToken)
    tokens = [] of LiteralToken
    idx = 0
    while idx < line.size
      token = case line[idx]
              when '"' then read_quoted_literal(line, idx)
              when '%' then read_percent_token(line, idx)
              end
      if token
        tokens << token
        idx = token.finish
      else
        idx += 1
      end
    end
    tokens
  end

  private def self.read_quoted_literal(line : String, start : Int32) : LiteralToken?
    idx = start + 1
    raw = String::Builder.new
    while idx < line.size
      current = line[idx]
      if current == '\\' && idx + 1 < line.size
        raw << current << line[idx + 1]
        idx += 2
      elsif current == '"'
        return LiteralToken.new(start, idx + 1, decode_literal(raw.to_s))
      else
        raw << current
        idx += 1
      end
    end
    nil
  end

  private def self.read_percent_token(line : String, start : Int32) : LiteralToken?
    if start + 1 < line.size && line[start + 1] == '('
      content, finish, closed = read_percent_literal(line, start + 2, true)
      return LiteralToken.new(start, finish, decode_literal(content)) if closed
    elsif start + 2 < line.size && line[start + 1] == 'q' && line[start + 2] == '('
      content, finish, closed = read_percent_literal(line, start + 3, false)
      return LiteralToken.new(start, finish, content) if closed
    end
    nil
  end

  private def self.read_percent_literal(text : String, idx : Int32,
                                        escape : Bool) : Tuple(String, Int32, Bool)
    depth = 1
    io = String::Builder.new
    while idx < text.size
      char = text[idx]
      if escape && char == '\\' && idx + 1 < text.size
        io << char << text[idx + 1]
        idx += 2
        next
      end
      case char
      when '('
        depth += 1
        io << char
      when ')'
        depth -= 1
        return {io.to_s, idx + 1, true} if depth.zero?
        io << char
      else
        io << char
      end
      idx += 1
    end
    {io.to_s, idx, false}
  end

  private def self.decode_literal(raw : String) : String
    io = String::Builder.new
    idx = 0
    while idx < raw.size
      char = raw[idx]
      if char != '\\'
        io << char
        idx += 1
        next
      end
      idx += 1
      break if idx >= raw.size
      escape = raw[idx]
      idx += 1
      if decoded = INLINE_ESCAPES[escape]?
        io << decoded
      elsif escape == 'x' || escape == 'u'
        digits = escape == 'x' ? 2 : 4
        code = raw[idx, digits]?.try(&.to_i?(16))
        if code && 0 <= code <= 0x10FFFF
          idx += digits
          io << code.chr
        else
          io << escape
        end
      else
        io << '\\' << escape
      end
    end
    io.to_s
  end

  private def self.load_inline_registry(dir : String? = nil) : Hash(String, JSON::Any)
    path = inline_pending_path(dir)
    return {} of String => JSON::Any unless File.exists?(path)
    JSON.parse(File.read(path)).as_h
  rescue
    {} of String => JSON::Any
  end

  private def self.record_inline_pending(file : String, line : Int32, name : String?,
                                         old_content : String, new_content : String)
    registry = load_inline_registry
    entry = {} of String => JSON::Any
    entry["file"] = JSON::Any.new(file)
    entry["line"] = JSON::Any.new(line.to_i64)
    entry["name"] = name ? JSON::Any.new(name) : JSON::Any.new(nil)
    entry["old"] = JSON::Any.new(old_content)
    entry["new"] = JSON::Any.new(new_content)
    entry["created_at"] = JSON::Any.new(Time.utc.to_rfc3339)
    registry["#{file}:#{line}"] = JSON::Any.new(entry)
    write_file(inline_pending_path, registry.to_pretty_json)
  end

  private def self.clear_inline_pending(file : String, line : Int32)
    registry = load_inline_registry
    key = "#{file}:#{line}"
    return unless registry.has_key?(key)
    registry.delete(key)
    if registry.empty?
      delete_file(inline_pending_path)
    else
      write_file(inline_pending_path, registry.to_pretty_json)
    end
  end

  private def self.guard_inline_duplicate!(file : String, line : Int32)
    return if @@settings.allow_duplicates?
    key = "#{file}:#{line}"
    unless @@inline_seen.add?(key)
      raise "inline snapshot assertion at #{file}:#{line} ran more than once; " \
            "wrap the assertion in Golden.allow_duplicates"
    end
  end

  private def self.effective_update_mode : UpdateMode
    @@settings.update_mode
  end

  private def self.ci? : Bool
    case ENV["CI"]?
    when "false", "0", "" then false
    when nil              then !ENV["TF_BUILD"]?.nil?
    else                       true
    end
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
  def self.promote_pending!(pending_path : String, name : String? = nil,
                            dir : String? = nil) : String
    golden_path = golden_path_for_pending(pending_path, dir)
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
