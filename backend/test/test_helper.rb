ENV["RAILS_ENV"] = "test"
require "test_safety"
require_relative "../config/environment"
require "rails/test_help"
require "mocha/minitest"
require "webmock/minitest"

ENV["CRYPT_KEY"] = "test_key_123"
ENV["JWT_SECRET"] = "test_jwt_secret"

module GraphqlTestHelpers
  def graphql_user
    @graphql_user ||= User.create!(email: "graphql#{SecureRandom.hex(6)}@example.com", password: "password123")
  end

  def graphql_request(remote_addr: "127.0.0.1", host: "api.example.com")
    ActionDispatch::TestRequest.create("REMOTE_ADDR" => remote_addr, "HTTP_HOST" => host)
  end

  def execute_graphql(query, variables: {}, scopes: [ :user ], request: graphql_request)
    current_user = scopes.include?(:user) ? graphql_user : nil
    AppSchema.execute(query, variables:, context: { current_user:, scopes:, request: }).to_h
  end

  def graphql_data(query, **options)
    result = execute_graphql(query, **options)
    assert_nil result["errors"], result["errors"].to_json
    result.fetch("data")
  end

  def graphql_error(query, **options)
    result = execute_graphql(query, **options)
    assert result["errors"].present?, "expected errors in #{result.to_json}"
    result["errors"].first
  end
end

module ActiveSupport
  class TestCase
    include GraphqlTestHelpers

    parallelize(workers: 4, threshold: 0)

    def setup
      Rails.cache.clear
      WebMock.reset!
      WebMock::StubRegistry.instance.instance_variable_get(:@request_stubs).clear
      WebMock.disable_net_connect!
    end
  end
end
