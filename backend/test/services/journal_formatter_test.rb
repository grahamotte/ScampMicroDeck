require "test_helper"

class JournalFormatterTest < ActiveSupport::TestCase
  def setup
    super
    @output = StringIO.new
    @logger = ActiveSupport::TaggedLogging.logger(@output)
  end

  def test_prefixes_syslog_priorities
    JournalFormatter.install(@logger)

    @logger.debug("debug")
    @logger.info("info")
    @logger.warn("warn")
    @logger.error("error")
    @logger.fatal("fatal")
    @logger.unknown("unknown")

    assert_equal [ "<7>debug", "<6>info", "<4>warn", "<3>error", "<2>fatal", "<2>unknown" ], @output.string.lines.map(&:chomp)
  end

  def test_writes_one_line_per_message_with_tags
    JournalFormatter.install(@logger)

    @logger.tagged("abc") { @logger.error("first\nsecond\n") }

    assert_equal "<3>[abc] first\\nsecond\n", @output.string
  end

  def test_installs_on_broadcasts_once
    other = StringIO.new
    broadcast = ActiveSupport::BroadcastLogger.new(@logger, ActiveSupport::TaggedLogging.logger(other))

    JournalFormatter.install(broadcast)
    JournalFormatter.install(broadcast)
    broadcast.warn("both")

    assert_equal "<4>both\n", @output.string
    assert_equal "<4>both\n", other.string
  end

  def test_leaves_other_loggers_unchanged
    @logger.error("plain\nlines")

    assert_equal "plain\nlines\n", @output.string
  end
end
