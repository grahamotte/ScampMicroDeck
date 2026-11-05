class RateLimit
  def self.exceeded?(name, by:, to:, within:)
    count = Rails.cache.increment("rate-limit:#{name}:#{by}", 1, expires_in: within)
    count.present? && count > to
  end
end
