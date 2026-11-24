class GraphqlContext
  def self.build(request)
    bearer = request.headers["Authorization"]&.split&.last
    auth_method = User.api_token?(bearer) ? :api_token : :jwt
    current_user = auth_method == :api_token ? User.find_by_api_token(bearer) : Token.verify(bearer || request.session[:jwt])

    {
      current_user:,
      auth_method: current_user.present? ? auth_method : nil,
      scopes: current_user.present? ? [ :user ] : [],
      request:,
    }
  end
end
