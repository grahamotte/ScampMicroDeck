class RateLimit
  def self.exceeded?(name, by:, to:, within:)
    count = Rails.cache.increment("rate-limit:#{name}:#{by}", 1, expires_in: within)
    (count.present? && count > to).tap do |exceeded|
      AuthLog.warn("rate_limited", limit: name, key: by.to_s, count:, to:) if exceeded
    end
  end
end
