require "test_helper"

module Api
  class NoopControllerTest < ActionController::TestCase
    include ActiveJob::TestHelper

    tests NoopController

    def setup
      super
      @previous_queue_adapter = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      clear_enqueued_jobs
    end

    def teardown
      clear_enqueued_jobs
      ActiveJob::Base.queue_adapter = @previous_queue_adapter
      super
    end

    def test_ping
      get :ping

      assert_response :success
      assert_equal({ "message" => "pong" }, response.parsed_body)
    end

    def test_lock
      user = User.create!(email: "user@example.com", password: "password123")
      @request.headers["Authorization"] = "Bearer #{Token.generate_for_user(user)}"

      get :lock

      assert_response :success
      assert_equal({ "message" => "load" }, response.parsed_body)
    end

    def test_hc
      finished_at = Time.zone.parse("2026-05-14T20:23:19Z")
      GoodJob::Execution.create!(
        active_job_id: SecureRandom.uuid,
        job_class: "HcJob",
        queue_name: "default",
        serialized_params: {},
        scheduled_at: finished_at,
        finished_at:,
      )

      assert_enqueued_with(job: HcJob) do
        get :hc, params: { frontend_time: "frontend" }
      end

      assert_response :success
      assert_equal "frontend", response.parsed_body.fetch("frontend_time")
      assert_equal finished_at.iso8601(3), response.parsed_body.fetch("hc_job_finished_at")
      assert Time.iso8601(response.parsed_body.fetch("backend_time"))
      assert Time.iso8601(response.parsed_body.fetch("database_time"))
    end

    def test_error
      error = assert_raises(RuntimeError) { post :error }

      assert_equal "Test backend error", error.message
    end
  end
end
