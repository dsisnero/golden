require "json"
require "option_parser"
require "./review"

module Golden
  module CLI
    def self.dispatch(args : Array(String)) : String
      return usage if args.empty?

      command = args.first
      remaining = args[1..]

      snapshot_dir = nil
      json_output = false
      dry_run = false
      spec_cmd = "crystal spec"

      parser = OptionParser.new do |opts|
        opts.on("--snapshot DIR", "") { |dir| snapshot_dir = dir }
        opts.on("--json", "") { json_output = true }
        opts.on("--dry-run", "") { dry_run = true }
        opts.on("--spec-cmd CMD", "") { |cmd| spec_cmd = cmd }
        opts.invalid_option { }
      end
      parser.parse(remaining)

      case command
      when "review"
        format_review(Golden.review!(snapshot_dir))
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
        format_review(Golden.test_and_review!(spec_cmd, snapshot_dir))
      when "show"
        show_snapshot_cli(remaining)
      else
        usage
      end
    rescue e : OptionParser::InvalidOption
      "Error: #{e.message}"
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
        io << "  show <path>         Display snapshot contents\n\n"
        io << "Options:\n"
        io << "  --snapshot DIR      Snapshot directory\n"
        io << "  --spec-cmd CMD      Spec command (default: crystal spec)\n"
        io << "  --dry-run           Dry run (for clean)"
      end
    end
  end
end
