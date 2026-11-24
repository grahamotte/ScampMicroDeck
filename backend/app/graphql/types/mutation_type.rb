module Types
  class MutationType < Types::BaseObject
    graphql_name "Mutation"
    field_class Types::RootField

    field :create_token, String, null: false, access: :public, description: "Sign in and get a JWT that lasts 7 days. Send it as \"Authorization: Bearer <token>\". Each response to a request signed in with a JWT returns a fresh one in the refresh-token header." do
      argument :email, String
      argument :password, String
    end

    field :create_api_token, String, null: false, access: :user, description: "Create or replace the signed-in user's API token. It does not expire, is deleted when the password changes or the user's tokens are revoked, and works like a JWT in \"Authorization: Bearer <token>\", except that its responses carry no refresh-token header. It is returned only once; only a hash is stored."
    field :revoke_api_token, Boolean, null: false, access: :user, description: "Delete the signed-in user's API token."
    field :trigger_error, Boolean, null: false, access: :public, description: "Raise a test backend error. Limited to 5 calls a minute per IP."

    def create_token(email:, password:)
      request = context[:request]
      if RateLimit.exceeded?("create_token", by: request.remote_ip, to: 10, within: 1.minute) ||
          RateLimit.exceeded?("create_token:email", by: User.normalize_value_for(:email, email), to: 10, within: 15.minutes)
        raise GraphQL::ExecutionError.new("too many attempts", extensions: { code: "RATE_LIMITED" })
      end

      Token.make(email, password).presence || begin
        AuthLog.warn("bad_credentials", operation: "createToken", ip: request.remote_ip, email: User.normalize_value_for(:email, email))
        raise GraphQL::ExecutionError.new("bad email/password", extensions: { code: "UNAUTHENTICATED" })
      end
    end

    def create_api_token = context[:current_user].generate_api_token!

    def revoke_api_token
      context[:current_user].revoke_api_token!
      true
    end

    def trigger_error
      if RateLimit.exceeded?("trigger_error", by: context[:request].remote_ip, to: 5, within: 1.minute)
        raise GraphQL::ExecutionError.new("too many requests", extensions: { code: "RATE_LIMITED" })
      end

      raise "Test backend error"
    end
  end
end
