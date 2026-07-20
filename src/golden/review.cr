require "bubbles"

module Golden
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
        @inline_diff = build_inline_diff(diff_obj)
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

    private def build_inline_diff(diff : Similar::TextDiff(String)) : String
      has_changes = diff.ops.any? { |op| op.tag != Similar::DiffTag::Equal }
      return "" unless has_changes

      String.build do |sb|
        diff.ops.each do |op|
          tag = op.tag
          if tag == Similar::DiffTag::Equal || tag == Similar::DiffTag::Insert || tag == Similar::DiffTag::Delete
            diff.iter_changes(op).each do |change|
              append_change_line(sb, change)
            end
          else
            inline_changes = diff.iter_inline_changes(op)
            inline_changes.each do |ic|
              ic.values.each do |emphasized, value|
                if emphasized
                  sb << "\e[1m\e[4m" << value << "\e[0m"
                else
                  sb << value
                end
              end
            end
          end
        end
      end
    end

    private def append_change_line(sb : IO, change : Similar::Change(String))
      case change.tag
      when Similar::ChangeTag::Equal
        sb << change.value
      when Similar::ChangeTag::Insert
        sb << "\e[32m" << change.value << "\e[0m"
      when Similar::ChangeTag::Delete
        sb << "\e[31m" << change.value << "\e[0m"
      end
    end

    private def read_metadata(meta_path : String)
      return unless File.exists?(meta_path)
      begin
        data = JSON.parse(File.read(meta_path))
        @metadata_line = data["line"]?.try(&.as_i?)
        @metadata_source_file = data["source_file"]?.try(&.to_s)
        if sf = @metadata_source_file
          if ml = @metadata_line
            read_source_context(sf, ml)
          end
        end
      rescue
      end
    end

    private def read_source_context(file : String, line : Int32)
      return unless File.exists?(file)
      lines = File.read_lines(file)
      return if lines.empty?
      start = {line - 4, 0}.max
      end_idx = {start + 3, lines.size}.min
      context = lines[start...end_idx]
      @source_context = context.each_with_index.map do |line_text, index|
        line_num = start + index + 1
        prefix = line_num == line ? "=>" : "  "
        "#{prefix} #{line_num}: #{line_text}"
      end.join("\n")
    end
  end

  class ReviewModel
    include Tea::Model

    getter actions : Array(Tuple(String, String))
    getter list : Bubbles::List::Model
    getter? show_help : Bool = false
    getter? show_diff : Bool = false
    getter? show_info : Bool = false

    def initialize(@pending : Array(String), @dir : String = Golden.dir)
      @actions = [] of Tuple(String, String)
      @viewport = Bubbles::Viewport::Model.new
      @viewport.set_width(80)
      @viewport.set_height(20)

      items = Array(Bubbles::List::Item).new(@pending.size) do |i|
        name = File.basename(@pending[i], ".golden.new")
        ReviewItem.new(name, @pending[i])
      end

      delegate = Bubbles::List.new_default_delegate
      @list = Bubbles::List::Model.new(items, delegate, 80, 20)
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

    def total : Int32
      @pending.size
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
      when "?"
        @show_help = !@show_help
      when "d"
        @show_diff = !@show_diff
        update_viewport_for_current if @show_diff
      when "i"
        @show_info = !@show_info
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
        content = String.build do |s|
          s << "Keybindings\n\n"
          s << "  y   Accept current snapshot\n"
          s << "  n   Reject current snapshot\n"
          s << "  s   Skip current snapshot\n"
          s << "  A   Accept all remaining\n"
          s << "  R   Reject all remaining\n"
          s << "  S   Skip all remaining\n"
          s << "  j/k Navigate up/down\n"
          s << "  g   Go to top\n"
          s << "  G   Go to bottom\n"
          s << "  ?   Toggle this help\n"
          s << "  q   Quit\n"
          s << "\nPress ? to close help."
        end
        return Tea::View.new(content)
      end

      content = String.build do |s|
        s << "Reviewing Pending Snapshots\n\n"
        s << @list.view
        s << "\n[y] Accept  [n] Reject  [s] Skip  [j/k] Navigate  [?] Help  [q] Quit"
      end
      Tea::View.new(content)
    end

    private def info_content : String
      if item = @list.selected_item
        snap = item.as(ReviewItem)
        String.build do |s|
          s << "Snapshot Info\n\n"
          s << "  Name: #{snap.name}\n"
          s << "  File: #{snap.path}\n"
          if line = snap.metadata_line
            s << "  Line: #{line}\n"
          end
          if sf = snap.metadata_source_file
            s << "  Source: #{sf}\n"
          end
          unless snap.source_context.empty?
            s << "\nSource Context:\n#{snap.source_context}\n"
          end
          s << "\nPress i to close."
        end
      else
        "No snapshot selected."
      end
    end

    private def update_viewport_for_current
      if item = @list.selected_item
        snap = item.as(ReviewItem)
        content = snap.inline_diff.empty? ? snap.diff : snap.inline_diff
        @viewport.set_content(content)
      end
    end

    private def accept_current
      if item = @list.selected_item
        snap = item.as(ReviewItem)
        pending_path = snap.path
        golden_path = pending_path.rchop(".new")
        FileUtils.mv(pending_path, golden_path)
        Golden.write_metadata(golden_path, snap.name, nil)
        @actions << {snap.name, "accepted"}
      end
    end

    private def reject_current
      if item = @list.selected_item
        snap = item.as(ReviewItem)
        File.delete(snap.path)
        @actions << {snap.name, "rejected"}
      end
    end

    private def skip_current
      if item = @list.selected_item
        snap = item.as(ReviewItem)
        @actions << {snap.name, "skipped"}
      end
    end

    private def accept_all_remaining
      (@list.index...@pending.size).each do |i|
        snap_path = @pending[i]
        name = File.basename(snap_path, ".golden.new")
        golden_path = snap_path.rchop(".new")
        if File.exists?(snap_path)
          FileUtils.mv(snap_path, golden_path)
          Golden.write_metadata(golden_path, name, nil)
          @actions << {name, "accepted"}
        end
      end
    end

    private def reject_all_remaining
      (@list.index...@pending.size).each do |i|
        snap_path = @pending[i]
        name = File.basename(snap_path, ".golden.new")
        if File.exists?(snap_path)
          File.delete(snap_path)
          @actions << {name, "rejected"}
        end
      end
    end

    private def skip_all_remaining
      (@list.index...@pending.size).each do |i|
        snap_path = @pending[i]
        name = File.basename(snap_path, ".golden.new")
        @actions << {name, "skipped"}
      end
    end
  end

  def self.review!(dir : String? = nil)
    search_dir = dir || @@settings.dir
    unless Dir.exists?(search_dir)
      return [] of Tuple(String, String)
    end
    pending = Dir.glob(File.join(search_dir, "**/*.golden.new")).sort
    return [] of Tuple(String, String) if pending.empty?

    model = ReviewModel.new(pending, search_dir)
    program = Tea.new_program(model, Tea.with_alt_screen)
    final_model, _ = program.run
    if final_model
      final_model.as(ReviewModel).actions
    else
      [] of Tuple(String, String)
    end
  end
end
