require "test_helper"

module Types
  class BaseFieldTest < ActiveSupport::TestCase
    class Owner < Types::BaseObject
      graphql_name "BaseFieldTestOwner"
    end

    def field(**options)
      Types::BaseField.new(name: :thing, type: String, owner: Owner, null: true, **options)
    end

    def context(scopes)
      GraphQL::Query.new(AppSchema, "{ __typename }", context: { scopes: }).context
    end

    def test_fields_without_access_are_open
      field = field()

      assert_nil field.access
      assert field.authorized?(nil, {}, context([]))
    end

    def test_public_access_is_open
      assert field(access: :public).authorized?(nil, {}, context([]))
    end

    def test_access_requires_a_matching_scope
      field = field(access: [ :user, :stars ])

      assert_equal [ :user, :stars ], field.access
      assert field.authorized?(nil, {}, context([ :stars ]))
      refute field.authorized?(nil, {}, context([ :files ]))
      refute field.authorized?(nil, {}, context(nil))
    end
  end
end
