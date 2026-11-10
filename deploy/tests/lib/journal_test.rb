require_relative "../test_helper"

class JournalTest < Minitest::Test
  def test_recent_counts_warnings_and_summarizes_rails_errors
    error = JSON.generate(type: "NoMethodError", message: "undefined\n  method", fingerprint: "abc123")
    Cmd.expects(:ssh).with("journalctl -u api -p warning..alert --since '15 min ago' --no-pager --output cat | wc -l", quiet: true).returns("4\n")
    Cmd.expects(:ssh).with("journalctl -u api -p warning..alert --since '15 min ago' --no-pager --output short-iso -n 3", quiet: true).returns(
      "2026-11-07T12:10:00-0800 droplet api[1]: RAILS_ERROR #{error}\n\n2026-11-07T12:11:00-0800 droplet api[1]: AUTH_FAILURE {}\n",
    )

    assert_equal(
      [
        4,
        [
          "2026-11-07T12:10:00-0800 droplet api[1]: NoMethodError: undefined method (abc123)",
          "2026-11-07T12:11:00-0800 droplet api[1]: AUTH_FAILURE {}",
        ],
      ],
      Journal.recent("api"),
    )
  end

  def test_summarize_truncates_long_messages
    line = "api: RAILS_ERROR #{JSON.generate(type: "RuntimeError", message: "x" * 250, fingerprint: "f")}"

    assert_equal "api: RuntimeError: #{"x" * 197}... (f)", Journal.summarize(line)
  end

  def test_summarize_keeps_messages_at_the_limit
    line = "api: RAILS_ERROR #{JSON.generate(type: "RuntimeError", message: "x" * 200, fingerprint: "f")}"

    assert_equal "api: RuntimeError: #{"x" * 200} (f)", Journal.summarize(line)
  end

  def test_summarize_returns_unparseable_lines
    assert_equal "api: RAILS_ERROR {broken", Journal.summarize("api: RAILS_ERROR {broken")
    assert_equal "api: plain warning", Journal.summarize("api: plain warning")
  end
end
