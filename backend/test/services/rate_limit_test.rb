require "test_helper"

class RateLimitTest < ActiveSupport::TestCase
  def test_allows_calls_up_to_the_limit
    3.times { refute RateLimit.exceeded?("test", by: "a", to: 3, within: 1.minute) }

    assert RateLimit.exceeded?("test", by: "a", to: 3, within: 1.minute)
  end

  def test_counts_each_key_separately
    4.times { RateLimit.exceeded?("test", by: "a", to: 3, within: 1.minute) }

    refute RateLimit.exceeded?("test", by: "b", to: 3, within: 1.minute)
    refute RateLimit.exceeded?("other", by: "a", to: 3, within: 1.minute)
  end

  def test_resets_after_the_window
    4.times { RateLimit.exceeded?("test", by: "a", to: 3, within: 1.minute) }

    travel 2.minutes do
      refute RateLimit.exceeded?("test", by: "a", to: 3, within: 1.minute)
    end
  end
end
