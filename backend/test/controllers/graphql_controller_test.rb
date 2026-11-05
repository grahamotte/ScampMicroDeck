require "test_helper"

class GraphqlControllerTest < ActionController::TestCase
  tests GraphqlController

  def setup
    super
    @user = User.create!(email: "user@example.com", password: "password123")
  end

  def test_executes_query_with_jwt_and_returns_refresh_token
    @request.headers["Authorization"] = "Bearer #{Token.generate_for_user(@user)}"

    post :execute, params: { query: "{ viewer { email } }" }, as: :json

    assert_response :success
    assert_equal({ "data" => { "viewer" => { "email" => @user.email } } }, response.parsed_body)
    assert_equal @user, Token.verify(response.headers["refresh-token"])
  end

  def test_executes_query_with_session_jwt
    post :execute, params: { query: "{ viewer { email } }" }, session: { jwt: Token.generate_for_user(@user) }, as: :json

    assert_equal({ "data" => { "viewer" => { "email" => @user.email } } }, response.parsed_body)
  end

  def test_executes_query_with_api_token
    @request.headers["Authorization"] = "Bearer #{@user.generate_api_token!}"

    post :execute, params: { query: "{ viewer { email } }" }, as: :json

    assert_equal({ "data" => { "viewer" => { "email" => @user.email } } }, response.parsed_body)
  end

  def test_rejects_revoked_jwt
    token = Token.generate_for_user(@user)
    @user.revoke_tokens!
    @request.headers["Authorization"] = "Bearer #{token}"

    post :execute, params: { query: "{ viewer { email } }" }, as: :json

    assert_nil response.headers["refresh-token"]
    assert_equal "UNAUTHENTICATED", response.parsed_body.dig("errors", 0, "extensions", "code")
  end

  def test_omits_refresh_token_when_signed_out
    post :execute, params: { query: "{ viewer { email } }" }, as: :json

    assert_response :success
    assert_nil response.headers["refresh-token"]
    assert_equal "UNAUTHENTICATED", response.parsed_body.dig("errors", 0, "extensions", "code")
  end

  def test_accepts_variables_as_object_or_string
    query = "query($time: String) { healthCheck(frontendTime: $time) { frontendTime } }"

    post :execute, params: { query:, variables: { time: "a" } }, as: :json

    assert_equal({ "healthCheck" => { "frontendTime" => "a" } }, response.parsed_body["data"])

    post :execute, params: { query:, variables: { time: "b" }.to_json }, as: :json

    assert_equal({ "healthCheck" => { "frontendTime" => "b" } }, response.parsed_body["data"])
  end

  def test_passes_operation_name
    post :execute, params: { query: "query A { healthCheck { frontendTime } } query B { viewer { id } }", operationName: "A" }, as: :json

    assert_equal({ "healthCheck" => { "frontendTime" => nil } }, response.parsed_body["data"])
  end

  def test_introspection_is_public
    post :execute, params: { query: "{ __schema { queryType { name } mutationType { name } } }" }, as: :json

    assert_equal({ "queryType" => { "name" => "Query" }, "mutationType" => { "name" => "Mutation" } }, response.parsed_body.dig("data", "__schema"))
  end

  def test_routes_post_graphql
    assert_routing({ method: "post", path: "/graphql" }, { controller: "graphql", action: "execute" })
  end
end
