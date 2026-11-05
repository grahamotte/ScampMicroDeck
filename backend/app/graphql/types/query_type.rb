module Types
  class QueryType < Types::BaseObject
    graphql_name "Query"
    field_class Types::RootField

    field :viewer, Types::UserType, null: false, access: :user, description: "The signed-in user."
    field :health_check, Types::HealthCheckType, null: false, access: :public, description: "Enqueues HcJob and reports clock readings. Limited to 120 calls a minute per IP." do
      argument :frontend_time, String, required: false
    end

    def viewer = context[:current_user]

    def health_check(frontend_time: nil)
      if RateLimit.exceeded?("health_check", by: context[:request].remote_ip, to: 120, within: 1.minute)
        raise GraphQL::ExecutionError.new("too many requests", extensions: { code: "RATE_LIMITED" })
      end

      HcJob.perform_later
      { frontend_time: }
    end
  end
end
