class Card
  COMMANDS = %w[
    create
    show
    list
    move
    edit
    comment
    comment-edit
    comment-delete
    link
    unlink
    tag
    untag
    relate
    unrelate
  ].freeze
  BOOLEAN_FLAGS = %w[
    raw
    clear_priority
    clear_estimate
    clear_assignee
    clear_due
    clear_project
    clear_parent
  ].freeze
  PRIORITIES = {
    "none" => 0,
    "urgent" => 1,
    "high" => 2,
    "medium" => 3,
    "normal" => 3,
    "low" => 4,
  }.freeze
  PRIORITY_LABELS = {
    0 => "none",
    1 => "urgent",
    2 => "high",
    3 => "medium",
    4 => "low",
  }.freeze

  class << self
    def call(command, *args, **options)
      raise "Unknown command #{command.inspect}, expected one of #{COMMANDS.join(", ")}" unless COMMANDS.include?(command)

      args, options = split_argv(args) if options.blank?
      Linear.with_team(options[:team]) { dispatch(command, args, options) }
    end

    def split_argv(argv)
      positionals = []
      options = {}
      i = 0
      args = argv.map(&:to_s)
      while i < args.length
        arg = args[i]
        unless arg.start_with?("--")
          positionals << arg
          i += 1
          next
        end

        key = arg.delete_prefix("--").tr("-", "_")
        if BOOLEAN_FLAGS.include?(key)
          options[key.to_sym] = true
          i += 1
          next
        end

        value = args[i + 1]
        raise "Missing value for #{arg}" if value.blank? || value.start_with?("--")

        options[key.to_sym] = value
        i += 2
      end
      [ positionals, options ]
    end

    private

    def dispatch(command, args, options)
      case command
      when "create"
        create(args, options)
      when "list"
        list(options)
      when "comment-edit"
        comment_edit(args, options)
      when "comment-delete"
        comment_delete(args)
      else
        identifier, *rest = args
        item = Linear.issue(identifier)
        case command
        when "show"
          show(item, options)
        when "move"
          move(item, rest)
        when "edit"
          edit(item, options)
        when "comment"
          comment(item, rest, options)
        when "link"
          link(item, rest)
        when "unlink"
          unlink(item, rest)
        when "tag"
          Linear.tag(item, rest.first)
          puts "tagged #{Linear.identifier(item)} with #{rest.first}"
        when "untag"
          Linear.untag(item, rest.first)
          puts "untagged #{rest.first} from #{Linear.identifier(item)}"
        when "relate"
          relate(item, rest)
        when "unrelate"
          unrelate(item, rest)
        end
      end
    end

    def create(args, options)
      title, body, column = args
      raise "Title is blank" if title.blank?

      column = (column.present? ? column : "backlog").to_s.downcase
      assert_column!(column)
      item = Linear.create(title, body, column, parent: options[:parent])
      puts "#{Linear.identifier(item)} #{Linear.url(item)}"
    end

    def list(options)
      column = options[:column]
      assert_column!(column.to_s.downcase) if column.present?
      Linear.list(column:, tag: options[:tag], search: options[:search]).each do |item|
        puts "#{Linear.identifier(item)}  #{Linear.column(item)}  #{item[:title]}"
      end
    end

    def show(item, options)
      if options[:raw]
        $stdout.write(item[:description].to_s)
        return
      end

      puts describe(item)
    end

    def move(item, args)
      column = args.first.to_s.downcase
      assert_column!(column)
      Linear.move(item, column)
      puts "moved #{Linear.identifier(item)} to #{column}"
    end

    def edit(item, options)
      body = markdown_body(options)
      input = edit_input(item, options, body)
      raise "Nothing to update" if input.blank?

      result = Linear.update(item, input)
      puts "updated #{Linear.identifier(item)}"
      return if body.blank?

      stored = result.dig(:issue, :description).to_s
      return if stored == body

      if Linear.normalize_description(stored) == Linear.normalize_description(body)
        puts "Linear normalized the description."
      else
        puts "Linear stored a different description:"
        $stdout.write(stored)
        puts unless stored.end_with?("\n")
      end
    end

    def comment(item, args, options)
      body = markdown_body(options, args.first)
      raise "Comment body is blank" if body.blank?

      Linear.comment(item, body, parent: options[:reply])
      puts "commented on #{Linear.identifier(item)}"
    end

    def comment_edit(args, options)
      id = args.first
      raise "Comment id is blank" if id.blank?

      body = markdown_body(options)
      raise "Comment body is blank" if body.blank?

      assert_own_comment!(id)
      Linear.comment_update(id, body)
      puts "updated comment #{id}"
    end

    def comment_delete(args)
      id = args.first
      raise "Comment id is blank" if id.blank?

      assert_own_comment!(id)
      Linear.comment_delete(id)
      puts "deleted comment #{id}"
    end

    def link(item, args)
      url, title = args
      raise "Link url is blank" if url.blank?

      if Linear.link(item, url, title.blank? ? nil : title)
        puts "linked #{url} to #{Linear.identifier(item)}"
      else
        puts "already linked #{url} to #{Linear.identifier(item)}"
      end
    end

    def unlink(item, args)
      url = args.first
      raise "Link url is blank" if url.blank?

      Linear.unlink(item, url)
      puts "unlinked #{url} from #{Linear.identifier(item)}"
    end

    def relate(item, args)
      type, other = args
      raise "Related card is blank" if other.blank?

      Linear.relate(item, type, other)
      puts "related #{Linear.identifier(item)} #{type} #{other}"
    end

    def unrelate(item, args)
      other = args.first
      raise "Related card is blank" if other.blank?

      Linear.unrelate(item, other)
      puts "unrelated #{Linear.identifier(item)} from #{other}"
    end

    def edit_input(item, options, body)
      conflicts = [
        [ :priority, :clear_priority ],
        [ :estimate, :clear_estimate ],
        [ :assignee, :clear_assignee ],
        [ :due, :clear_due ],
        [ :project, :clear_project ],
        [ :parent, :clear_parent ],
      ]
      conflicts.each do |set_key, clear_key|
        next unless options[set_key].present? && options[clear_key]

        raise "Cannot both set and clear #{set_key}"
      end

      input = {}
      input[:title] = options[:title] if options[:title].present?
      if body.present?
        guard_description!(item, options)
        input[:description] = body
      end
      input[:priority] = parse_priority(options[:priority]) if options[:priority].present?
      input[:priority] = 0 if options[:clear_priority]
      input[:estimate] = parse_estimate(options[:estimate]) if options[:estimate].present?
      input[:estimate] = nil if options[:clear_estimate]
      input[:assigneeId] = Linear.user_id(options[:assignee]) if options[:assignee].present?
      input[:assigneeId] = nil if options[:clear_assignee]
      input[:dueDate] = parse_due(options[:due]) if options[:due].present?
      input[:dueDate] = nil if options[:clear_due]
      input[:projectId] = Linear.project_id(options[:project]) if options[:project].present?
      input[:projectId] = nil if options[:clear_project]
      input[:parentId] = options[:parent] if options[:parent].present?
      input[:parentId] = nil if options[:clear_parent]
      input
    end

    def guard_description!(item, options)
      expected_file = options[:expect_file]
      expected_hash = options[:expect_hash]
      if expected_file.blank? && expected_hash.blank?
        raise "Pass --expect-file or --expect-hash to update the description"
      end

      current = item[:description].to_s
      if expected_file.present? && current != File.read(expected_file)
        raise "Description changed since it was read; refusing to overwrite"
      end
      if expected_hash.present? && !Linear.description_hash(current).casecmp?(expected_hash.to_s)
        raise "Description changed since it was read; refusing to overwrite"
      end
    end

    def markdown_body(options, positional = nil)
      file = options[:body_file]
      flag = options[:body]
      sources = []
      sources << "argument" if positional.present?
      sources << "--body" if flag.present?
      sources << "--body-file" if file.present?
      raise "Pass only one of a body argument, --body, or --body-file" if sources.size > 1

      return File.read(file) if file.present?
      return flag if flag.present?

      positional
    end

    def assert_own_comment!(id)
      comment = Linear.comment_record(id)
      raise "Comment #{id.inspect} not found" if comment.blank?

      key = comment.dig(:issue, :team, :key).to_s
      unless key.blank? || key.casecmp?(Linear.team_key)
        raise "Comment #{id} is on a card in team #{key.inspect}, expected #{Linear.team_key.inspect}"
      end

      owner = comment.dig(:user, :id)
      raise "Comment #{id} has no author" if owner.blank?
      raise "Comment #{id} was not created by you" unless owner == Linear.viewer.fetch(:id)
    end

    def assert_column!(column)
      unless Linear::STATUSES.any? { |status| status[:name].downcase == column }
        raise "Unknown column #{column.inspect}, expected one of #{Linear::STATUSES.map { |status| status[:name].downcase }.join(", ")}"
      end
    end

    def parse_priority(value)
      return value.to_i if value.to_s.match?(/\A[0-4]\z/)

      found = PRIORITIES[value.to_s.downcase]
      raise "Unknown priority #{value.inspect}, expected none, urgent, high, medium, low, or 0-4" if found.nil?

      found
    end

    def parse_estimate(value)
      raise "Estimate #{value.inspect} is not an integer" unless value.to_s.match?(/\A\d+\z/)

      value.to_i
    end

    def parse_due(value)
      raise "Due date #{value.inspect} must be YYYY-MM-DD" unless value.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      value.to_s
    end

    def describe(item)
      lines = [
        "#{Linear.identifier(item)}: #{item[:title]}",
        "State: #{item.dig(:state, :name)}",
      ]
      priority = item[:priority]
      if !priority.nil? && priority.to_i != 0
        lines << "Priority: #{PRIORITY_LABELS[priority.to_i] || priority}"
      end
      lines << "Estimate: #{item[:estimate]}" unless item[:estimate].nil?
      assignee = item.dig(:assignee, :displayName) || item.dig(:assignee, :name)
      lines << "Assignee: #{assignee}" if assignee.present?
      lines << "Due: #{item[:dueDate]}" if item[:dueDate].present?
      lines << "Project: #{item.dig(:project, :name)}" if item.dig(:project, :name).present?
      if item.dig(:parent, :identifier).present?
        lines << "Parent: #{item.dig(:parent, :identifier)} #{item.dig(:parent, :title)}"
      end
      lines << "Tags: #{nodes(item, :labels).map { |label| label[:name] }.join(", ")}"
      lines << "URL: #{Linear.url(item)}"
      lines << "Description hash: #{Linear.description_hash(item[:description])}"
      children = nodes(item, :children)
      if children.present?
        lines << ""
        lines << "Children:"
        children.each do |child|
          lines << "- #{child[:identifier]}: #{child[:title]} (#{child.dig(:state, :name)})"
        end
      end
      relations = relation_lines(item)
      if relations.present?
        lines << ""
        lines << "Relations:"
        lines.concat(relations)
      end
      links = nodes(item, :attachments)
      if links.present?
        lines << ""
        lines << "Links:"
        links.each { |link| lines << "- #{link[:title]}: #{link[:url]}" }
      end
      lines << ""
      lines << "Description:"
      lines << item[:description].to_s
      nodes(item, :comments).sort_by { |comment| comment[:createdAt].to_s }.each do |comment|
        lines << ""
        author = comment.dig(:user, :name) || "unknown"
        parent = comment.dig(:parent, :id)
        prefix = comment[:id].present? ? "Comment #{comment[:id]}" : "Comment"
        prefix = "#{prefix} (reply to #{parent})" if parent.present?
        lines << "#{prefix} by #{author} at #{comment[:createdAt]}:"
        lines << comment[:body].to_s
      end
      lines.join("\n")
    end

    def relation_lines(item)
      lines = []
      seen = []
      nodes(item, :relations).each do |rel|
        other = rel[:relatedIssue]
        next if other.blank?

        type = rel[:type].to_s
        label = type == "duplicate" ? "duplicate of" : type
        lines << "- #{label} #{other[:identifier]}: #{other[:title]}"
        seen << other[:identifier]
      end
      nodes(item, :inverseRelations).each do |rel|
        other = rel[:issue]
        next if other.blank?
        next if seen.include?(other[:identifier])

        type = rel[:type].to_s
        label = case type
        when "blocks" then "blocked by"
        when "duplicate" then "duplicated by"
        else type
        end
        lines << "- #{label} #{other[:identifier]}: #{other[:title]}"
      end
      lines
    end

    def nodes(item, key)
      item.dig(key, :nodes) || []
    end
  end
end
