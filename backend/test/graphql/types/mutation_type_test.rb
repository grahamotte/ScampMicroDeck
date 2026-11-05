require "test_helper"

module Types
  class MutationTypeTest < ActiveSupport::TestCase
    def mutate(query, **options) = graphql_data("mutation { #{query} }", **options)

    def create_token(email, password, **options)
      execute_graphql("mutation { createToken(email: \"#{email}\", password: \"#{password}\") }", scopes: [], **options)
    end

    def test_create_token
      user = User.create!(email: "user@example.com", password: "password123")

      token = mutate("createToken(email: \"User@example.com\", password: \"password123\")", scopes: [])["createToken"]

      assert_equal user, Token.verify(token)
    end

    def test_create_token_rejects_bad_credentials
      User.create!(email: "user@example.com", password: "password123")

      [ [ "user@example.com", "wrong" ], [ "nope@example.com", "password123" ], [ "", "" ] ].each do |email, password|
        error = create_token(email, password)["errors"].first

        assert_equal "bad email/password", error["message"]
        assert_equal "UNAUTHENTICATED", error.dig("extensions", "code")
      end
    end

    def test_create_token_limits_attempts_per_ip
      User.create!(email: "user@example.com", password: "password123")
      10.times { |i| create_token("user#{i}@example.com", "wrong") }

      error = create_token("user@example.com", "password123")["errors"].first

      assert_equal "too many attempts", error["message"]
      assert_equal "RATE_LIMITED", error.dig("extensions", "code")
    end

    def test_create_token_limits_attempts_per_email
      User.create!(email: "user@example.com", password: "password123")
      10.times { |i| create_token(" USER@example.com", "wrong", request: graphql_request(remote_addr: "10.0.0.#{i}")) }

      error = create_token("user@example.com", "password123", request: graphql_request(remote_addr: "10.0.1.1"))["errors"].first

      assert_equal "RATE_LIMITED", error.dig("extensions", "code")
    end

    def test_create_token_allows_other_emails_after_an_email_is_limited
      user = User.create!(email: "user@example.com", password: "password123")
      10.times { |i| create_token("nope@example.com", "wrong", request: graphql_request(remote_addr: "10.0.0.#{i}")) }

      token = create_token("user@example.com", "password123", request: graphql_request(remote_addr: "10.0.1.1")).dig("data", "createToken")

      assert_equal user, Token.verify(token)
    end

    def test_create_and_revoke_api_token
      token = mutate("createApiToken")["createApiToken"]

      assert_equal graphql_user, User.find_by_api_token(token)
      assert graphql_data("{ viewer { apiToken } }").dig("viewer", "apiToken")

      assert mutate("revokeApiToken")["revokeApiToken"]
      assert_nil User.find_by_api_token(token)
      refute graphql_data("{ viewer { apiToken } }").dig("viewer", "apiToken")
    end

    def test_api_token_mutations_require_a_user
      [ "createApiToken", "revokeApiToken" ].each do |field|
        assert_equal "UNAUTHENTICATED", graphql_error("mutation { #{field} }", scopes: []).dig("extensions", "code")
      end
    end

    def test_trigger_error_raises
      error = assert_raises(RuntimeError) { execute_graphql("mutation { triggerError }", scopes: []) }

      assert_equal "Test backend error", error.message
    end
  end
end
