require "test_helper"

module Types
  class QueryTypeTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    def test_viewer
      assert_equal({ "id" => graphql_user.id, "email" => graphql_user.email }, graphql_data("{ viewer { id email } }")["viewer"])
    end

    def test_viewer_requires_a_user
      assert_equal "UNAUTHENTICATED", graphql_error("{ viewer { id } }", scopes: []).dig("extensions", "code")
    end

    def test_health_check_enqueues_hc_job
      assert_enqueued_with(job: HcJob) { graphql_data("{ healthCheck { frontendTime } }", scopes: []) }
    end

    def test_health_check_limits_requests_per_ip
      120.times { execute_graphql("{ healthCheck { frontendTime } }", scopes: []) }

      error = graphql_error("{ healthCheck { frontendTime } }", scopes: [])

      assert_equal "too many requests", error["message"]
      assert_equal "RATE_LIMITED", error.dig("extensions", "code")
      assert graphql_data("{ healthCheck { frontendTime } }", scopes: [], request: graphql_request(remote_addr: "10.0.0.1"))
    end
  end
end
