module Api
  class UsersController < AuthorizedController
    skip_before_action :authorize, only: [ :jwt ]

    rate_limit to: 10, within: 1.minute, only: :jwt, with: :too_many_attempts
    rate_limit to: 10, within: 15.minutes, only: :jwt, with: :too_many_attempts, name: "email", by: -> { User.normalize_value_for(:email, params[:email].to_s) }

    def jwt
      token = Token.make(params[:email].to_s, params[:password].to_s)

      if token.blank?
        render json: { error: "bad email/password" }, status: :unauthorized
      else
        render json: { token: }
      end
    end

    private

    def too_many_attempts
      render json: { error: "too many attempts" }, status: :too_many_requests
    end
  end
end
