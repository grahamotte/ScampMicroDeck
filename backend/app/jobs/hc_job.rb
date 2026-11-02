class HcJob < ApplicationJob
  schedule "every 1 hour"

  good_job_control_concurrency_with total_limit: 1, key: "hc"

  def perform
    sleep 1
  end
end
