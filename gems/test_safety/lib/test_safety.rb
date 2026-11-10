require "socket"

begin
  require "minitest"
rescue LoadError
  nil
end

class UnsafeTestOperation < StandardError; end

module TestSafety
  ROOT = File.expand_path("../../..", __dir__)

  module SleepStub
    def sleep(duration = nil)
      return super unless File.expand_path(caller_locations(1, 1).first.path).start_with?("#{TestSafety::ROOT}/")

      duration
    end
  end

  module CommandGuard
    def system(*) = raise UnsafeTestOperation, "System commands must be stubbed in tests"
    def exec(*) = raise UnsafeTestOperation, "System commands must be stubbed in tests"
    def spawn(*) = raise UnsafeTestOperation, "System commands must be stubbed in tests"
    def fork(*)
      return super if caller_locations.any? do |location|
        location.path.end_with?("/active_support/testing/parallelization/worker.rb") ||
          location.path.end_with?("/minitest/parallel_fork.rb")
      end

      raise UnsafeTestOperation, "System commands must be stubbed in tests"
    end

    define_method(:"`") do |*|
      raise UnsafeTestOperation, "System commands must be stubbed in tests"
    end
  end

  module PopenGuard
    def popen(*) = raise UnsafeTestOperation, "System commands must be stubbed in tests"
  end

  module NetworkGuard
    def new(*) = raise UnsafeTestOperation, "Network calls must be stubbed in tests"
    def open(*) = raise UnsafeTestOperation, "Network calls must be stubbed in tests"
    def tcp(*) = raise UnsafeTestOperation, "Network calls must be stubbed in tests"
    def udp(*) = raise UnsafeTestOperation, "Network calls must be stubbed in tests"
  end
end

Minitest::Assertions.diff = false if defined?(Minitest::Assertions)
ENV["EDITOR"] ||= "vi"

Kernel.prepend(TestSafety::SleepStub)
Kernel.singleton_class.prepend(TestSafety::SleepStub)
Kernel.prepend(TestSafety::CommandGuard)
Kernel.singleton_class.prepend(TestSafety::CommandGuard)
Process.singleton_class.prepend(TestSafety::CommandGuard)
IO.singleton_class.prepend(TestSafety::PopenGuard)
Socket.singleton_class.prepend(TestSafety::NetworkGuard)
TCPSocket.singleton_class.prepend(TestSafety::NetworkGuard)
UDPSocket.singleton_class.prepend(TestSafety::NetworkGuard)
