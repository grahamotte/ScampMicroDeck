require "test_helper"

module Types
  class HealthCheckTypeTest < ActiveSupport::TestCase
    def test_reports_times
      finished_at = Time.zone.parse("2026-05-14T20:23:19Z")
      GoodJob::Execution.create!(active_job_id: SecureRandom.uuid, job_class: "HcJob", queue_name: "default", serialized_params: {}, scheduled_at: finished_at, finished_at:)

      data = graphql_data("{ healthCheck(frontendTime: \"frontend\") { frontendTime backendTime databaseTime hcJobFinishedAt } }", scopes: []).fetch("healthCheck")

      assert_equal "frontend", data["frontendTime"]
      assert_equal finished_at.iso8601(3), data["hcJobFinishedAt"]
      assert Time.iso8601(data["backendTime"])
      assert Time.iso8601(data["databaseTime"])
    end

    def test_hc_job_finished_at_is_null_without_runs
      assert_nil graphql_data("{ healthCheck { frontendTime hcJobFinishedAt } }", scopes: []).dig("healthCheck", "hcJobFinishedAt")
    end
  end
end
