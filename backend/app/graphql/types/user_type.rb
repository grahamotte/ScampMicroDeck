module Types
  class UserType < Types::BaseObject
    graphql_name "User"
    description "An account that can sign in."

    field :id, ID, null: false
    field :email, String, null: false
    field :api_token, Boolean, null: false, method: :api_token?, description: "Whether the user has an API token."
  end
end
