require_relative "../test_helper"

class CmdTest < Minitest::Test
  def test_local_escapes_arguments_and_returns_output
    Cmd.expects(:`).with("echo hello\\ world").returns("hello world\n")
    result = nil

    output, = capture_io { result = DeployTestMethods::CMD_LOCAL.call("echo ?", "hello world") }

    assert_equal "hello world\n", result
    assert_includes output, "CMD echo hello\\ world"
  end

  def test_local_raises_when_command_fails
    Cmd.expects(:`).with("false").returns("")
    Cmd.stubs(:command_succeeded?).returns(false)

    error = assert_raises(RuntimeError) { DeployTestMethods::CMD_LOCAL.call("false") }

    assert_equal "Command failed: false", error.message
  end

  def test_ssh_returns_utf8_output_split_across_chunks
    stub_ssh([ :data, "x\na\xE2\x80" ], [ :data, "\xA6b\n" ], code: 0)

    result = DeployTestMethods::CMD_SSH.call("psql -c ?", "select 'a…b'", quiet: true)

    assert_equal Encoding::UTF_8, result.encoding
    assert_equal "x\na…b\n", result
  end

  def test_ssh_sends_escaped_command
    channel = stub_ssh([ :data, "ok" ], code: 0)

    capture_io { DeployTestMethods::CMD_SSH.call("echo ?", "a…b") }

    assert_equal "echo a\\…b", channel.command
  end

  def test_ssh_raises_with_output_when_command_fails
    stub_ssh([ :extended_data, "ERROR:  column \xE2\x80\xA6 does not exist\n" ], code: 1)

    error = assert_raises(Cmd::SshError) { DeployTestMethods::CMD_SSH.call("psql", quiet: true) }

    assert_equal "SSH command failed: psql", error.message
    assert_equal "ERROR:  column … does not exist\n", error.output
  end

  def test_ssh_prints_output_unless_quiet
    stub_ssh([ :data, "out\n" ], [ :extended_data, "err\n" ], code: 0)
    result = nil

    output, = capture_io { result = DeployTestMethods::CMD_SSH.call("ls") }

    assert_includes output, "SSH ls"
    assert_includes output, "out\nerr\n"
    assert_equal "out\nerr\n", result
  end

  private

  class FakeChannel
    attr_reader :command

    def initialize(events, code)
      @events = events
      @code = code
      @handlers = {}
    end

    def exec(command)
      @command = command
      yield
    end

    def on_data(&block) = @handlers[:data] = block

    def on_extended_data(&block) = @handlers[:extended_data] = block

    def on_request(_, &block) = @handlers[:exit] = block

    def run
      @events.each do |type, x|
        x = x.b
        type == :data ? @handlers[:data].call(self, x) : @handlers[:extended_data].call(self, 1, x)
      end
      @handlers[:exit].call(self, Net::SSH::Buffer.from(:long, @code))
    end
  end

  class FakeSession
    def initialize(channel)
      @channel = channel
    end

    def open_channel = yield(@channel)

    def loop = @channel.run
  end

  def stub_ssh(*events, code:)
    channel = FakeChannel.new(events, code)
    Req.stubs(:call).returns(
      droplets: [ { name: "example.com", networks: { v4: [ { type: "public", ip_address: "203.0.113.1" } ] } } ],
    )
    Net::SSH.expects(:start)
      .with("203.0.113.1", "deploy", keys: [ Constants.ssh_key_path ], keys_only: true)
      .yields(FakeSession.new(channel))
    channel
  end
end
