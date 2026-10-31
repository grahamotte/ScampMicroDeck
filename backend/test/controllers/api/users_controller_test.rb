require "test_helper"

module Api
  class UsersControllerTest < ActionController::TestCase
    tests UsersController

    def setup
      super
      @user = User.create!(email: "user@example.com", password: "password123")
    end

    def test_jwt_returns_a_token
      post :jwt, params: { email: "User@example.com", password: "password123" }

      assert_response :success
      assert_equal @user, Token.verify(response.parsed_body.fetch("token"))
    end

    def test_jwt_rejects_a_bad_password
      post :jwt, params: { email: @user.email, password: "wrongpassword" }

      assert_response :unauthorized
      assert_equal({ "error" => "bad email/password" }, response.parsed_body)
    end

    def test_jwt_rejects_an_unknown_email
      post :jwt, params: { email: "nope@example.com", password: "password123" }

      assert_response :unauthorized
    end

    def test_jwt_rejects_missing_params
      post :jwt

      assert_response :unauthorized
    end
  end
end
