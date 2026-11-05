require "test_helper"

module Api
  class NoopControllerTest < ActionController::TestCase
    tests NoopController

    def test_ping
      get :ping

      assert_response :success
      assert_equal({ "message" => "pong" }, response.parsed_body)
    end
  end
end
