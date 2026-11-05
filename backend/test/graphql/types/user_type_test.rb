require "test_helper"

module Types
  class UserTypeTest < ActiveSupport::TestCase
    def test_fields
      data = graphql_data("{ viewer { id email apiToken } }")["viewer"]

      assert_equal({ "id" => graphql_user.id, "email" => graphql_user.email, "apiToken" => false }, data)
    end

    def test_api_token_reports_whether_one_exists
      graphql_user.generate_api_token!

      assert graphql_data("{ viewer { apiToken } }").dig("viewer", "apiToken")
    end
  end
end
