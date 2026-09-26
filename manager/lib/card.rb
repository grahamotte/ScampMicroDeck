class Card
  COMMANDS = %w[create show move comment link tag untag].freeze

  class << self
    def call(command, *args)
      raise "Unknown command #{command.inspect}, expected one of #{COMMANDS.join(", ")}" unless COMMANDS.include?(command)

      if command == "create"
        title, body, column = args
        raise "Title is blank" if title.blank?

        column = (column.present? ? column : "backlog").to_s.downcase
        unless Linear::STATUSES.any? { |status| status[:name].downcase == column }
          raise "Unknown column #{column.inspect}, expected one of #{Linear::STATUSES.map { |status| status[:name].downcase }.join(", ")}"
        end

        item = Linear.create(title, body, column)
        puts "#{Linear.identifier(item)} #{Linear.url(item)}"
        return
      end

      identifier, *args = args
      item = Linear.issue(identifier)
      case command
      when "show"
        puts describe(item)
      when "move"
        column = args.first.to_s.downcase
        unless Linear::STATUSES.any? { |status| status[:name].downcase == column }
          raise "Unknown column #{column.inspect}, expected one of #{Linear::STATUSES.map { |status| status[:name].downcase }.join(", ")}"
        end

        Linear.move(item, column)
        puts "moved #{Linear.identifier(item)} to #{column}"
      when "comment"
        body = args.first
        raise "Comment body is blank" if body.blank?

        Linear.comment(item, body)
        puts "commented on #{Linear.identifier(item)}"
      when "link"
        url, title = args
        raise "Link url is blank" if url.blank?

        Linear.link(item, url, title.blank? ? nil : title)
        puts "linked #{url} to #{Linear.identifier(item)}"
      when "tag"
        Linear.tag(item, args.first)
        puts "tagged #{Linear.identifier(item)} with #{args.first}"
      when "untag"
        Linear.untag(item, args.first)
        puts "untagged #{args.first} from #{Linear.identifier(item)}"
      end
    end

    private

    def describe(item)
      lines = [
        "#{Linear.identifier(item)}: #{item[:title]}",
        "State: #{item.dig(:state, :name)}",
        "Tags: #{nodes(item, :labels).map { |label| label[:name] }.join(", ")}",
        "URL: #{Linear.url(item)}",
      ]
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
        lines << "Comment by #{comment.dig(:user, :name) || "unknown"} at #{comment[:createdAt]}:"
        lines << comment[:body].to_s
      end
      lines.join("\n")
    end

    def nodes(item, key)
      item.dig(key, :nodes) || []
    end
  end
end
