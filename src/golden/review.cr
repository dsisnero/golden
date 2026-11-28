require "bubbles"

module Golden
  # Shared diff rendering for review items.
  module DiffRendering
    extend self

    def build_inline_diff(diff : Similar::TextDiff(String)) : String
      has_changes = diff.ops.any? { |op| op.tag != Similar::DiffTag::Equal }
      return "" unless has_changes

      String.build do |io|
        diff.ops.each do |op|
          tag = op.tag
          if tag == Similar::DiffTag::Equal || tag == Similar::DiffTag::Insert || tag == Similar::DiffTag::Delete
            diff.iter_changes(op).each do |change|
              append_change_line(io, change)
            end
          else
            inline_changes = diff.iter_inline_changes(op)
            inline_changes.each do |inline_change|
              inline_change.values.each do |emphasized, value|
                if emphasized
                  io << "\e[1m\e[4m" << value << "\e[0m"
                else
                  io << value
                end
              end
            end
          end
        end
      end
    end

    private def append_change_line(io : IO, change : Similar::Change(String))
      case change.tag
      when Similar::ChangeTag::Equal
        io << change.value
      when Similar::ChangeTag::Insert
        io << "\e[32m" << change.value << "\e[0m"
      when Similar::ChangeTag::Delete
        io << "\e[31m" << change.value << "\e[0m"
      end
    end
  end

  # Shared source-context rendering for review items.
  module SourceContext
    extend self

    def read(file : String, line : Int32) : String
      return "" unless File.exists?(file)
      lines = File.read_lines(file)
      return "" if lines.empty?
      start = {line - 4, 0}.max
      end_idx = {start + 3, lines.size}.min
      lines[start...end_idx].each_with_index.map do |text, index|
        number = start + index + 1
        prefix = number == line ? "=>" : "  "
        "#{prefix} #{number}: #{text}"
      end.join("\n")
    end
  end

  class ReviewItem
    include Bubbles::List::DefaultItem

    getter name : String
    getter path : String
    getter new_content : String
    getter old_content : String?
    getter? has_existing : Bool
    getter diff : String
    getter metadata_line : Int32?
    getter metadata_source_file : String?
    getter source_context : String
    getter inline_diff : String

    def initialize(@name : String, @path : String)
      @new_content = File.read(@path)
      golden_path = @path.rchop(".new")
      @has_existing = File.exists?(golden_path)
      if @has_existing
        old = File.read(golden_path)
        @old_content = old
        a = Golden.normalize(old)
        b = Golden.normalize(@new_content)
        diff_obj = Similar::TextDiff.from_lines(a, b)
        @diff = diff_obj.unified_diff.header("golden", "run").to_s
        @inline_diff = DiffRendering.build_inline_diff(diff_obj)
      else
        @old_content = nil
        @diff = "(new snapshot)"
        @inline_diff = ""
      end
      meta_path = golden_path + ".meta"
      @metadata_line = nil
      @metadata_source_file = nil
      @source_context = ""
      read_metadata(meta_path)
    end

    def title : String
      @name
    end

    def description : String
      @has_existing ? "changed" : "new"
    end

    def filter_value : String
      @name
    end

    # Stable key used to remember that this item already has a decision.
    def review_key : String
      @path
    end

    private def read_metadata(meta_path : String)
      return unless File.exists?(meta_path)
      begin
        data = JSON.parse(File.read(meta_path))
        @metadata_line = data["line"]?.try(&.as_i?)
        @metadata_source_file = data["source_file"]?.try(&.to_s)
        if sf = @metadata_source_file
          if ml = @metadata_line
            @source_context = SourceContext.read(sf, ml)
          end
        end
      rescue
      end
    end
  end

  # A pending inline snapshot shown alongside file pendings in the review TUI.
  # Accepting one patches the expected literal in the source file.
  class InlineReviewItem
    include Bubbles::List::DefaultItem

    getter pending : InlineSnapshotPending
    getter name : String
    getter file : String
    getter line : Int32
    getter old_content : String
    getter new_content : String
    getter? has_existing : Bool
    getter diff : String
    getter inline_diff : String
    getter source_context : String

    def initialize(@pending : InlineSnapshotPending)
      @name = @pending.name || "#{@pending.file}:#{@pending.line}"
      @file = @pending.file
      @line = @pending.line
      @old_content = @pending.old_content
      @new_content = @pending.new_content
      @has_existing = !@old_content.empty?
      if @has_existing
        diff_obj = Similar::TextDiff.from_lines(@old_content, @new_content)
        @diff = diff_obj.unified_diff.header(@file, "observed").to_s
        @inline_diff = DiffRendering.build_inline_diff(diff_obj)
      else
        @diff = "(new inline snapshot)"
        @inline_diff = ""
      end
      @source_context = SourceContext.read(@file, @line)
    end

    def title : String
      @name
    end

    def description : String
      @has_existing ? "inline changed" : "inline new"
    end

    def filter_value : String
      @name
    end

    def review_key : String
      "#{@file}:#{@line}"
    end
  end

  class ReviewModel
    include Tea::Model

    getter actions : Array(Tuple(String, String))
    getter list : Bubbles::List::Model
    getter items : Array(Bubbles::List::Item)
    getter? show_help : Bool = false
    getter? show_diff : Bool = false
    getter? show_info : Bool = false

    def initialize(@pending : Array(String), @dir : String = Golden.dir,
                   inline : Array(InlineSnapshotPending) = [] of InlineSnapshotPending,
                   @root : String? = nil)
      @actions = [] of Tuple(String, String)
      @decided = Set(String).new
      @viewport = Bubbles::Viewport::Model.new
      @viewport.set_width(80)
      @viewport.set_height(20)

      @items = Array(Bubbles::List::Item).new(@pending.size + inline.size)
      @pending.each do |path|
        @items << ReviewItem.new(File.basename(path, ".golden.new"), path)
      end
      inline.each do |pending|
        @items << InlineReviewItem.new(pending)
      end

      delegate = Bubbles::List.new_default_delegate
      @list = Bubbles::List::Model.new(@items, delegate, 80, 20)
      @list.show_help = false
      @list.show_filter = false
      @list.show_status_bar = false
      @list.show_pagination = false
      @list.filtering_enabled = false
      @list.show_title = false
    end

    def accepted : Int32
      @actions.count { |(_, action)| action == "accepted" }
    end

    def rejected : Int32
      @actions.count { |(_, action)| action == "rejected" }
    end

    def skipped : Int32
      @actions.count { |(_, action)| action == "skipped" }
    end

    def failed : Int32
      @actions.count { |(_, action)| action.starts_with?("failed") }
    end

    def total : Int32
      @items.size
    end

    def init : Tea::Cmd?
      nil
    end

    def update(msg : Tea::Msg) : {Tea::Model, Tea::Cmd?}
      if k = key_press(msg)
        return k
      end

      if @show_diff && msg.is_a?(Tea::Key)
        @viewport, cmd = @viewport.update(msg)
        return {self, cmd}
      end

      @list, cmd = @list.update(msg)
      {self, cmd}
    end

    private def key_press(msg : Tea::Msg) : {Tea::Model, Tea::Cmd?}?
      return unless msg.is_a?(Tea::Key)
      quit_or_batch_action(msg.text) || navigation_action(msg.text) || toggle_action(msg.text)
    end

    private def quit_or_batch_action(key : String) : {Tea::Model, Tea::Cmd?}?
      case key
      when "q" then return {self, Tea.quit}
      when "A" then accept_all_remaining; return {self, Tea.quit}
      when "R" then reject_all_remaining; return {self, Tea.quit}
      when "S" then skip_all_remaining; return {self, Tea.quit}
      end
    end

    private def navigation_action(key : String) : {Tea::Model, Tea::Cmd?}?
      case key
      when "y" then accept_current; @list.cursor_down
      when "n" then reject_current; @list.cursor_down
      when "s" then skip_current; @list.cursor_down
      when "g" then @list.go_to_start
      when "G" then @list.go_to_end
      else          return
      end
      {self, nil}
    end

    private def toggle_action(key : String) : {Tea::Model, Tea::Cmd?}?
      case key
      when "?" then @show_help = !@show_help
      when "d"
        @show_diff = !@show_diff
        update_viewport_for_current if @show_diff
      when "i" then @show_info = !@show_info
      else
        return
      end
      {self, nil}
    end

    def view : Tea::View
      if @show_info && !@show_help
        content = info_content
        return Tea::View.new(content)
      end

      if @show_diff && !@show_help
        return Tea::View.new(@viewport.view)
      end

      if @show_help
        content = String.build do |io|
          io << "Keybindings\n\n"
          io << "  y   Accept current snapshot\n"
          io << "  n   Reject current snapshot\n"
          io << "  s   Skip current snapshot\n"
          io << "  A   Accept all remaining\n"
          io << "  R   Reject all remaining\n"
          io << "  S   Skip all remaining\n"
          io << "  j/k Navigate up/down\n"
          io << "  g   Go to top\n"
          io << "  G   Go to bottom\n"
          io << "  ?   Toggle this help\n"
          io << "  q   Quit\n"
          io << "\nInline snapshots patch their source file on accept."
          io << "\nPress ? to close help."
        end
        return Tea::View.new(content)
      end

      content = String.build do |io|
        io << "Reviewing Pending Snapshots\n\n"
        io << @list.view
        io << "\n[y] Accept  [n] Reject  [s] Skip  [j/k] Navigate  [?] Help  [q] Quit"
      end
      Tea::View.new(content)
    end

    private def info_content : String
      case item = @list.selected_item
      when ReviewItem
        String.build do |io|
          io << "Snapshot Info\n\n"
          io << "  Name: #{item.name}\n"
          io << "  File: #{item.path}\n"
          if line = item.metadata_line
            io << "  Line: #{line}\n"
          end
          if sf = item.metadata_source_file
            io << "  Source: #{sf}\n"
          end
          unless item.source_context.empty?
            io << "\nSource Context:\n#{item.source_context}\n"
          end
          io << "\nPress i to close."
        end
      when InlineReviewItem
        String.build do |io|
          io << "Inline Snapshot Info\n\n"
          io << "  Name: #{item.name}\n"
          io << "  Source: #{item.file}:#{item.line}\n"
          unless item.source_context.empty?
            io << "\nSource Context:\n#{item.source_context}\n"
          end
          io << "\nAccepting patches the expected literal in this file."
          io << "\nPress i to close."
        end
      else
        "No snapshot selected."
      end
    end

    private def update_viewport_for_current
      case item = @list.selected_item
      when ReviewItem, InlineReviewItem
        content = item.inline_diff.empty? ? item.diff : item.inline_diff
        @viewport.set_content(content)
      end
    end

    private def accept_current
      if item = @list.selected_item
        accept_item(item)
      end
    end

    private def reject_current
      if item = @list.selected_item
        reject_item(item)
      end
    end

    private def skip_current
      if item = @list.selected_item
        skip_item(item)
      end
    end

    private def accept_all_remaining
      each_remaining do |item|
        accept_item(item)
      end
    end

    private def reject_all_remaining
      each_remaining do |item|
        reject_item(item)
      end
    end

    private def skip_all_remaining
      each_remaining do |item|
        skip_item(item)
      end
    end

    private def each_remaining(&)
      @items.each_with_index do |item, index|
        next if index < @list.index
        yield item
      end
    end

    private def accept_item(item : Bubbles::List::Item) : Bool
      case item
      when ReviewItem       then accept_file_item(item)
      when InlineReviewItem then accept_inline_item(item)
      else                       false
      end
    end

    private def accept_file_item(item : ReviewItem) : Bool
      return false if decided?(item)
      return false unless File.exists?(item.path)
      Golden.promote_pending!(item.path, item.name)
      record(item, "accepted")
      true
    end

    private def accept_inline_item(item : InlineReviewItem) : Bool
      return false if decided?(item)
      result = Golden.accept_inline_entry(item.pending, @dir, root: @root)
      if result.patched?
        record(item, "accepted")
        true
      else
        @actions << {item.name, "failed: #{result.error}"}
        @decided << item.review_key
        false
      end
    end

    private def reject_item(item : Bubbles::List::Item) : Bool
      case item
      when ReviewItem       then reject_file_item(item)
      when InlineReviewItem then reject_inline_item(item)
      else                       false
      end
    end

    private def reject_file_item(item : ReviewItem) : Bool
      return false if decided?(item)
      return false unless File.exists?(item.path)
      Golden.discard_pending!(item.path)
      record(item, "rejected")
      true
    end

    private def reject_inline_item(item : InlineReviewItem) : Bool
      return false if decided?(item)
      Golden.reject_inline_entry(item.pending, @dir)
      record(item, "rejected")
      true
    end

    private def skip_item(item : Bubbles::List::Item) : Bool
      case item
      when ReviewItem, InlineReviewItem
        return false if decided?(item)
        record(item, "skipped")
        true
      else
        false
      end
    end

    private def record(item : ReviewItem | InlineReviewItem, action : String)
      @actions << {item.name, action}
      @decided << item.review_key
    end

    private def decided?(item : ReviewItem | InlineReviewItem) : Bool
      @decided.includes?(item.review_key)
    end
  end

  def self.review!(dir : String? = nil, root : String? = nil)
    search_dir = dir || @@settings.dir
    pending = Dir.exists?(search_dir) ? Dir.glob(File.join(search_dir, "**/*.golden.new")).sort : [] of String
    inline = pending_inline_snapshots(search_dir).sort_by { |entry| {entry.file, entry.line} }
    return [] of Tuple(String, String) if pending.empty? && inline.empty?

    model = ReviewModel.new(pending, search_dir, inline, root: root)
    program = Tea.new_program(model, Tea.with_alt_screen)
    final_model, _ = program.run
    if final_model
      final_model.as(ReviewModel).actions
    else
      [] of Tuple(String, String)
    end
  end
end
