require "bubbles"

module Golden
  class ReviewItem
    include Bubbles::List::DefaultItem

    getter name : String
    getter path : String

    def initialize(@name : String, @path : String)
    end

    def title : String
      @name
    end

    def description : String
      "pending"
    end

    def filter_value : String
      @name
    end
  end

  class ReviewModel
    include Tea::Model

    getter actions : Array(Tuple(String, String))
    getter list : Bubbles::List::Model

    def initialize(@pending : Array(String), @dir : String = Golden.dir)
      @actions = [] of Tuple(String, String)

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

    def init : Tea::Cmd?
      nil
    end

    def update(msg : Tea::Msg) : {Tea::Model, Tea::Cmd?}
      case msg
      when Tea::Key
        case msg.text
        when "y"
          accept_current
          @list.cursor_down
          return {self, nil}
        when "n"
          reject_current
          @list.cursor_down
          return {self, nil}
        when "q"
          return {self, Tea.quit}
        end
      end

      @list, cmd = @list.update(msg)
      {self, cmd}
    end

    def view : Tea::View
      content = String.build do |s|
        s << "Reviewing Pending Snapshots\n\n"
        s << @list.view
        s << "\n[y] Accept  [n] Reject  [j/k] Navigate  [q] Quit"
      end
      Tea::View.new(content)
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
    final_model, err = program.run
    if final_model
      final_model.as(ReviewModel).actions
    else
      [] of Tuple(String, String)
    end
  end
end
