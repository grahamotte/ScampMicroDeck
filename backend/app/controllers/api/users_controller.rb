module Api
  class UsersController < AuthorizedController
    skip_before_action :authorize, only: [ :jwt ]

    def jwt
      token = Token.make(params[:email].to_s, params[:password].to_s)

      if token.blank?
        render json: { error: "bad email/password" }, status: :unauthorized
      else
        render json: { token: }
      end
    end
  end
end
