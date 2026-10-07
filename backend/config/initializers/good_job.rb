dashboard_username = ENV.fetch("DASHBOARD_USERNAME", "admin")
dashboard_password = ENV.fetch("DASHBOARD_PASSWORD", "coolbeans")

GoodJob::Engine.middleware.use(Rack::Auth::Basic) do |username, password|
  ActiveSupport::SecurityUtils.secure_compare(dashboard_username, username) & ActiveSupport::SecurityUtils.secure_compare(dashboard_password, password)
end

Rails.application.configure do
  config.good_job.queues = ENV.fetch("GOOD_JOB_QUEUES", "*")
  config.good_job.max_threads = ENV.fetch("GOOD_JOB_MAX_THREADS", "2").to_i
  config.good_job.poll_interval = ENV.fetch("GOOD_JOB_POLL_INTERVAL", "0.1").to_f
  config.good_job.enable_cron = ENV.fetch("GOOD_JOB_ENABLE_CRON", "false") == "true"
  config.good_job.cron_graceful_restart_period = 5.minutes
  config.good_job.cron = {}
  config.good_job.on_thread_error = ->(error) { Rails.error.report(error, handled: false, source: "good_job") }
end

Rails.application.config.after_initialize do
  db_ready = begin
    ActiveRecord::Base.connection_pool.with_connection { |c| c.table_exists?("good_jobs") }
  rescue
    false
  end

  if db_ready && !defined?(Rails::Console)
    GoodJob::Job.where(finished_at: nil).find_each { |j| j.discard_job("discarded due to deploy") }
  end

  scheduled_tasks = Dir[Rails.root.join("app/jobs/**/*_job.rb")]
    .reject { |path| path.end_with?("application_job.rb") }
    .each { |path| require_dependency(path) }
    .map do |path|
      relative_path = path.sub("#{Rails.root.join("app/jobs")}/", "").sub(".rb", "")
      class_name = relative_path.camelize
      klass = class_name.safe_constantize
      next if klass.blank?
      schedule = klass.schedule_interval
      next if schedule.blank?
      [ class_name.gsub("::", ""), { cron: schedule, class: class_name } ]
    end
    .compact
    .to_h

  Rails.application.config.good_job.cron = scheduled_tasks.transform_values do |task|
    {
      cron: task.fetch(:cron),
      class: task.fetch(:class),
      enabled_by_default: -> { Rails.env.production? },
    }
  end
end
