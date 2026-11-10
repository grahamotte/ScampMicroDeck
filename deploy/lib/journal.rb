class Journal
  RECENT = "15 min ago"
  MESSAGE_LIMIT = 200

  class << self
    def recent(service)
      count = Cmd
        .ssh("journalctl -u #{service} -p warning..alert --since '#{RECENT}' --no-pager --output cat | wc -l", quiet: true)
        .strip
        .to_i
      lines = Cmd
        .ssh("journalctl -u #{service} -p warning..alert --since '#{RECENT}' --no-pager --output short-iso -n 3", quiet: true)
        .lines
        .map(&:strip)
        .reject(&:blank?)
        .map { |line| summarize(line) }

      [ count, lines ]
    end

    def summarize(line)
      prefix, payload = line.split("RAILS_ERROR ", 2)
      return line if payload.blank?

      error = JSON.parse(payload)
      "#{prefix}#{error["type"]}: #{truncate(error["message"].to_s.gsub(/\s+/, " "))} (#{error["fingerprint"]})"
    rescue JSON::ParserError
      line
    end

    private

    def truncate(text)
      text.length > MESSAGE_LIMIT ? "#{text[0, MESSAGE_LIMIT - 3]}..." : text
    end
  end
end
