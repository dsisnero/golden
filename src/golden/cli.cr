require "json"
require "option_parser"
require "../golden"
require "./review"

module Golden
  module CLI
    def self.dispatch(args : Array(String)) : String
      return usage if args.empty?

      command = args.first
      remaining = args[1..]

      snapshot_dir = nil
      root_dir = nil
      json_output = false
      dry_run = false
      spec_cmd = "crystal spec"
      unreferenced : String? = nil

      parser = OptionParser.new do |opts|
        opts.on("--snapshot DIR", "") { |dir| snapshot_dir = dir }
        opts.on("--root DIR", "") { |dir| root_dir = dir }
        opts.on("--json", "") { json_output = true }
        opts.on("--dry-run", "") { dry_run = true }
        opts.on("--spec-cmd CMD", "") { |cmd| spec_cmd = cmd }
        opts.on("--unreferenced MODE", "") { |mode| unreferenced = mode }
        opts.invalid_option { }
      end
      parser.parse(remaining)

      case command
      when "inline-pending", "inline-accept", "inline-reject"
        run_inline_command(command, snapshot_dir, root_dir, json_output, dry_run)
      else
        run_snapshot_command(command, remaining, snapshot_dir, root_dir, json_output, dry_run,
          spec_cmd, unreferenced)
      end
    rescue e : OptionParser::InvalidOption
      "Error: #{e.message}"
    end

    private def self.run_snapshot_command(command : String, remaining : Array(String),
                                          snapshot_dir : String?, root_dir : String?,
                                          json_output : Bool,
                                          dry_run : Bool, spec_cmd : String,
                                          unreferenced : String?) : String
      case command
      when "review"
        format_review(Golden.review!(snapshot_dir, root: root_dir))
      when "accept"
        format_strings(Golden.accept_all!(snapshot_dir))
      when "reject"
        format_strings(Golden.reject_all!(snapshot_dir))
      when "pending"
        list_pending(snapshot_dir, json_output)
      when "status"
        format_status(snapshot_dir)
      when "clean"
        format_strings(Golden.cleanup!(snapshot_dir, dry_run: dry_run))
      when "test-review"
        mode = parse_unreferenced(unreferenced)
        return mode if mode.is_a?(String)
        format_review(Golden.test_and_review!(spec_cmd, snapshot_dir, mode))
      when "show"
        show_snapshot_cli(remaining)
      else
        usage
      end
    end

    private def self.run_inline_command(command : String, snapshot_dir : String?,
                                        root_dir : String?, json_output : Bool,
                                        dry_run : Bool) : String
      case command
      when "inline-pending"
        list_inline_pending(snapshot_dir, json_output)
      when "inline-accept"
        format_inline_patches(Golden.accept_inline!(snapshot_dir, root: root_dir, dry_run: dry_run))
      else
        reject_inline(snapshot_dir)
      end
    end

    private def self.parse_unreferenced(value : String?) : UnreferencedMode? | String
      return nil unless value
      mode = UnreferencedMode.parse(value)
      return mode if mode
      "Error: unknown unreferenced mode '#{value}' " \
      "(expected auto, reject, delete, warn, or ignore)"
    end

    private def self.format_review(items : Array(Tuple(String, String))) : String
      items.map { |(name, action)| "#{name}: #{action}" }.join("\n")
    end

    private def self.format_strings(items : Array(String)) : String
      items.join("\n")
    end

    private def self.list_pending(dir : String?, json : Bool) : String
      pending = Golden.pending_snapshots(dir)
      if json
        items = pending.map do |path|
          name = File.basename(path, ".golden.new")
          {name: name, path: path}
        end
        items.to_json
      else
        pending.join("\n")
      end
    end

    private def self.format_status(dir : String?) : String
      stats = Golden.status(dir)
      String.build do |io|
        stats.each do |key, count|
          io << "#{key}: #{count}\n"
        end
      end
    end

    private def self.show_snapshot_cli(args : Array(String)) : String
      if args.empty?
        return "Usage: golden show <snapshot_path>"
      end
      path = args.first
      content = Golden.show_snapshot(path)
      if content
        content
      else
        "Snapshot not found: #{path}"
      end
    end

    private def self.list_inline_pending(dir : String?, json : Bool) : String
      pendings = Golden.pending_inline_snapshots(dir)
      if json
        pendings.map do |pending|
          {
            file:       pending.file,
            line:       pending.line,
            name:       pending.name,
            old:        pending.old_content,
            new:        pending.new_content,
            created_at: pending.created_at,
          }
        end.to_json
      else
        return "No pending inline snapshots." if pendings.empty?
        pendings.map do |pending|
          suffix = pending.name ? " (#{pending.name})" : ""
          "#{pending.file}:#{pending.line}#{suffix}"
        end.join("\n")
      end
    end

    private def self.format_inline_patches(results : Array(InlinePatchResult)) : String
      return "No pending inline snapshots." if results.empty?
      results.map do |result|
        if result.patched?
          "#{result.file}:#{result.line}: patched"
        else
          error = result.error ? " (#{result.error})" : ""
          "#{result.file}:#{result.line}: failed#{error}"
        end
      end.join("\n")
    end

    private def self.reject_inline(dir : String?) : String
      pendings = Golden.pending_inline_snapshots(dir)
      Golden.reject_inline_snapshots!(dir)
      return "No pending inline snapshots." if pendings.empty?
      "Rejected #{pendings.size} inline snapshot(s)."
    end

    private def self.usage : String
      String.build do |io|
        io << "Usage: golden <command> [options]\n\n"
        io << "Commands:\n"
        io << "  review              Interactive TUI review\n"
        io << "  accept              Accept all pending snapshots\n"
        io << "  reject              Reject all pending snapshots\n"
        io << "  pending             List pending snapshots\n"
        io << "  status              Snapshot overview\n"
        io << "  clean               Remove unreferenced snapshots\n"
        io << "  test-review         Run specs then launch review\n"
        io << "  show <path>         Display snapshot contents\n"
        io << "  inline-pending      List pending inline snapshots\n"
        io << "  inline-accept       Patch pending inline snapshots\n"
        io << "  inline-reject       Drop pending inline snapshots\n\n"
        io << "Options:\n"
        io << "  --snapshot DIR      Snapshot directory\n"
        io << "  --root DIR          Project root for inline patches\n"
        io << "  --json              JSON output (pending, inline-pending)\n"
        io << "  --spec-cmd CMD      Spec command (default: crystal spec)\n"
        io << "  --unreferenced MODE Unreferenced snapshot policy for test-review\n"
        io << "                      (auto, reject, delete, warn, ignore)\n"
        io << "  --dry-run           Dry run (clean, inline-accept)"
      end
    end
  end
end
