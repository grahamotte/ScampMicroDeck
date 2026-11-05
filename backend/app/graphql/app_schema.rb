class AppSchema < GraphQL::Schema
  query Types::QueryType
  mutation Types::MutationType

  use GraphQL::Dataloader

  max_depth 15

  rescue_from(ActiveRecord::RecordNotFound) do |error|
    raise GraphQL::ExecutionError.new("#{error.model || "record"} not found", extensions: { code: "NOT_FOUND" })
  end

  rescue_from(ActiveRecord::RecordInvalid) do |error|
    raise GraphQL::ExecutionError.new(error.record.errors.full_messages.to_sentence, extensions: { code: "INVALID" })
  end

  def self.unauthorized_field(_error)
    raise GraphQL::ExecutionError.new("unauthorized", extensions: { code: "UNAUTHENTICATED" })
  end
end
