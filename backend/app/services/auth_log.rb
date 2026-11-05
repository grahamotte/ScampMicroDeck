module AuthLog
  MARKER = "AUTH_FAILURE".freeze

  def self.warn(event, **fields)
    Rails.logger.warn(body(event, **fields))
  end

  def self.body(event, **fields)
    "#{MARKER} #{JSON.generate(event:, **fields)}"
  end
end
