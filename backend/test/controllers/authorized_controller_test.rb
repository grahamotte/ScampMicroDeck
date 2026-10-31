require "test_helper"

class TestAuthorizedController < AuthorizedController
  skip_before_action :authorize, only: [ :open ]

  def index
    render json: { email: current_user.email }
  end

  def open
    head :ok
  end
end

class AuthorizedControllerTest < ActionController::TestCase
  tests TestAuthorizedController

  def setup
    super
    @routes = ActionDispatch::Routing::RouteSet.new
    @routes.draw do
      get "index" => "test_authorized#index"
      get "open" => "test_authorized#open"
    end
    @user = User.create!(email: "user@example.com", password: "password123")
    @token = Token.generate_for_user(@user)
  end

  def test_authorizes_header_token
    @request.headers["Authorization"] = "Bearer #{@token}"

    get :index

    assert_response :ok
    assert_equal({ "email" => @user.email }, response.parsed_body)
  end

  def test_authorizes_session_token
    get :index, session: { jwt: @token }

    assert_response :ok
  end

  def test_rejects_invalid_token
    @request.headers["Authorization"] = "Bearer invalid"

    get :index

    assert_response :unauthorized
    assert_nil response.headers["refresh-token"]
  end

  def test_rejects_missing_token
    get :index

    assert_response :unauthorized
  end

  def test_sets_refresh_token
    @request.headers["Authorization"] = "Bearer #{@token}"

    get :index

    assert_equal @user, Token.verify(response.headers["refresh-token"])
  end

  def test_skips_refresh_token_without_user
    get :open

    assert_response :ok
    assert_nil response.headers["refresh-token"]
  end
end
