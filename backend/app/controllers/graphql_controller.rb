class GraphqlController < ApplicationController
  def execute
    context = GraphqlContext.build(request)
    result = AppSchema.execute(
      params[:query],
      variables:,
      operation_name: params[:operationName],
      context:,
    )
    response.headers["refresh-token"] = Token.generate_for_user(context[:current_user]) if context[:current_user].present?

    render json: result
  end

  private

  def variables
    value = params[:variables]
    return {} if value.blank?
    return JSON.parse(value) if value.is_a?(String)
    return value.to_unsafe_h if value.is_a?(ActionController::Parameters)

    value
  end
end
