class GraphqlContext
  def self.build(request)
    bearer = request.headers["Authorization"]&.split&.last
    current_user = User.api_token?(bearer) ? User.find_by_api_token(bearer) : Token.verify(bearer || request.session[:jwt])

    {
      current_user:,
      scopes: current_user.present? ? [ :user ] : [],
      request:,
    }
  end
end
