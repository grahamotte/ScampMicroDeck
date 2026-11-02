require "test_helper"

class HcJobTest < ActiveSupport::TestCase
  def test_schedule_interval
    assert_equal "every 1 hour", HcJob.schedule_interval
  end

  def test_concurrency_is_separate_from_other_jobs
    assert_equal({ total_limit: 1, key: "hc" }, HcJob.good_job_concurrency_config)
    assert_equal({ total_limit: 1, key: "all" }, ApplicationJob.good_job_concurrency_config)
  end

  def test_perform
    assert_equal 1, HcJob.new.perform
  end
end
