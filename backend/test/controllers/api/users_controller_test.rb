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

    def test_jwt_limits_attempts_per_ip
      10.times { |i| post :jwt, params: { email: "user#{i}@example.com", password: "wrongpassword" } }
      post :jwt, params: { email: @user.email, password: "password123" }

      assert_response :too_many_requests
      assert_equal({ "error" => "too many attempts" }, response.parsed_body)
    end

    def test_jwt_limits_attempts_per_email
      10.times do |i|
        request.remote_addr = "10.0.0.#{i}"
        post :jwt, params: { email: " USER@example.com", password: "wrongpassword" }
      end
      request.remote_addr = "10.0.1.1"
      post :jwt, params: { email: @user.email, password: "password123" }

      assert_response :too_many_requests
    end

    def test_jwt_allows_other_emails_from_other_ips_after_an_email_is_limited
      10.times do |i|
        request.remote_addr = "10.0.0.#{i}"
        post :jwt, params: { email: "nope@example.com", password: "wrongpassword" }
      end
      request.remote_addr = "10.0.1.1"
      post :jwt, params: { email: @user.email, password: "password123" }

      assert_response :success
    end
  end
end
