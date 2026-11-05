require "test_helper"

class GraphqlContextTest < ActiveSupport::TestCase
  def setup
    super
    @user = User.create!(email: "context@example.com", password: "password123")
  end

  def build(headers: {}, session: {})
    request = ActionDispatch::TestRequest.create(headers.transform_keys { |key| "HTTP_#{key.upcase.tr("-", "_")}" })
    request.session = session
    GraphqlContext.build(request)
  end

  def test_bearer_jwt_signs_in_user
    context = build(headers: { "Authorization" => "Bearer #{Token.generate_for_user(@user)}" })

    assert_equal @user, context[:current_user]
    assert_equal [ :user ], context[:scopes]
    assert_kind_of ActionDispatch::Request, context[:request]
  end

  def test_api_token_signs_in_user
    token = @user.generate_api_token!

    context = build(headers: { "Authorization" => "Bearer #{token}" })

    assert_equal @user, context[:current_user]
    assert_equal [ :user ], context[:scopes]
  end

  def test_wrong_api_token_has_no_scopes
    @user.generate_api_token!

    context = build(headers: { "Authorization" => "Bearer #{Settings.api_token_prefix}_#{@user.id}_wrong" })

    assert_nil context[:current_user]
    assert_empty context[:scopes]
  end

  def test_session_jwt_signs_in_user
    assert_equal @user, build(session: { jwt: Token.generate_for_user(@user) })[:current_user]
  end

  def test_invalid_or_missing_jwt_has_no_scopes
    [ build(headers: { "Authorization" => "Bearer nope" }), build ].each do |context|
      assert_nil context[:current_user]
      assert_empty context[:scopes]
    end
  end
end
