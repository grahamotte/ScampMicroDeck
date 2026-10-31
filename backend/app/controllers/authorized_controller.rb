class AuthorizedController < ApplicationController
  before_action :authorize
  after_action :set_refresh_token

  private

  def authorize
    head :unauthorized if current_user.blank?
  end

  def current_user
    @current_user ||= Token.verify(request.headers["Authorization"]&.split&.last || session[:jwt])
  end

  def set_refresh_token
    return if current_user.blank?

    response.headers["refresh-token"] = Token.generate_for_user(current_user)
  end
end
