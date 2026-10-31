class Token
  LIFETIME = 99.days

  class << self
    def make(email, password)
      user = User.find_by(email:)
      return if user.blank? || password.blank? || !user.authenticate(password)

      generate_for_user(user)
    end

    def generate_for_user(user)
      return if user.blank?

      JWT.encode({ user_id: user.id, email: user.email, exp: LIFETIME.from_now.to_i }, secret)
    end

    def verify(token)
      return if token.blank?

      User.find_by(id: JWT.decode(token, secret).first["user_id"])
    rescue JWT::DecodeError
      nil
    end

    private

    def secret
      ENV.fetch("JWT_SECRET")
    end
  end
end
