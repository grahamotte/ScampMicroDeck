module Types
  class HealthCheckType < Types::BaseObject
    graphql_name "HealthCheck"
    description "Clock readings from each tier."

    field :frontend_time, String, description: "The frontendTime argument, echoed back."
    field :backend_time, GraphQL::Types::ISO8601DateTime, null: false
    field :database_time, GraphQL::Types::ISO8601DateTime, null: false
    field :hc_job_finished_at, GraphQL::Types::ISO8601DateTime, description: "When HcJob last finished."

    def frontend_time = object[:frontend_time]
    def backend_time = Time.current
    def database_time = ActiveRecord::Base.connection.execute("SELECT NOW()")[0]["now"].utc

    def hc_job_finished_at
      return if ActiveRecord::Base.connection.data_source_exists?("good_job_executions").blank?

      GoodJob::Execution.finished.where(job_class: "HcJob").order(finished_at: :desc).pick(:finished_at)&.utc
    end
  end
end
