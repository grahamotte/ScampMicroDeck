require_relative "../test_helper"

class CmdTest < Minitest::Test
  def test_local_escapes_arguments_and_returns_output
    Cmd.expects(:`).with("echo hello\\ world").returns("hello world\n")
    result = nil

    output, = capture_io { result = PublishTestMethods::CMD_LOCAL.call("echo ?", "hello world") }

    assert_equal "hello world\n", result
    assert_includes output, "CMD echo hello\\ world"
  end

  def test_local_raises_when_command_fails
    Cmd.expects(:`).with("false").returns("")
    Cmd.stubs(:command_succeeded?).returns(false)

    error = assert_raises(RuntimeError) { PublishTestMethods::CMD_LOCAL.call("false") }

    assert_equal "Command failed: false", error.message
  end
end
