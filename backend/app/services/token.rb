class Token
  LIFETIME = 7.days

  class << self
    def make(email, password)
      generate_for_user(User.authenticate_by(email:, password:))
    end

    def generate_for_user(user)
      return if user.blank?

      JWT.encode({ user_id: user.id, email: user.email, token_version: user.token_version, exp: LIFETIME.from_now.to_i }, secret)
    end

    def verify(token)
      return if token.blank?

      payload = JWT.decode(token, secret).first
      User.find_by(id: payload["user_id"], token_version: payload["token_version"])
    rescue JWT::DecodeError
      nil
    end

    private

    def secret
      ENV.fetch("JWT_SECRET")
    end
  end
end
