ENV["RAILS_ENV"] = "test"
require "test_safety"
require_relative "../config/environment"
require "rails/test_help"
require "mocha/minitest"
require "webmock/minitest"

ENV["CRYPT_KEY"] = "test_key_123"
ENV["JWT_SECRET"] = "test_jwt_secret"

module ActiveSupport
  class TestCase
    parallelize(workers: 4, threshold: 0)

    def setup
      WebMock.reset!
      WebMock::StubRegistry.instance.instance_variable_get(:@request_stubs).clear
      WebMock.disable_net_connect!
    end
  end
end
