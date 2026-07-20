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
        opts.on("--snapshot DIR", "") { |d| snapshot_dir = d }
        opts.on("--json", "") { json_output = true }
        opts.on("--dry-run", "") { dry_run = true }
        opts.on("--spec-cmd CMD", "") { |c| spec_cmd = c }
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
        items = pending.map do |p|
          name = File.basename(p, ".golden.new")
          {name: name, path: p}
        end
        items.to_json
      else
        pending.join("\n")
      end
    end

    private def self.format_status(dir : String?) : String
      stats = Golden.status(dir)
      String.build do |s|
        stats.each do |key, count|
          s << "#{key}: #{count}\n"
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
      String.build do |s|
        s << "Usage: golden <command> [options]\n\n"
        s << "Commands:\n"
        s << "  review              Interactive TUI review\n"
        s << "  accept              Accept all pending snapshots\n"
        s << "  reject              Reject all pending snapshots\n"
        s << "  pending             List pending snapshots\n"
        s << "  status              Snapshot overview\n"
        s << "  clean               Remove unreferenced snapshots\n"
        s << "  test-review         Run specs then launch review\n"
        s << "  show <path>         Display snapshot contents\n\n"
        s << "Options:\n"
        s << "  --snapshot DIR      Snapshot directory\n"
        s << "  --spec-cmd CMD      Spec command (default: crystal spec)\n"
        s << "  --dry-run           Dry run (for clean)"
      end
    end
  end
end
