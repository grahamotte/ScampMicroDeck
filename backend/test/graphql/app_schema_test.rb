require "test_helper"

class AppSchemaTest < ActiveSupport::TestCase
  class Probe < Types::BaseObject
    graphql_name "AppSchemaTestProbe"
    field_class Types::RootField

    field :missing, String, access: :public
    field :invalid, String, access: :public

    def missing = User.find(SecureRandom.uuid)
    def invalid = User.create!(email: "", password: "password123")
  end

  class ProbeSchema < AppSchema
    query Probe
  end

  def test_unauthorized_root_field_returns_unauthenticated_error
    error = graphql_error("{ viewer { id } }", scopes: [])

    assert_equal "unauthorized", error["message"]
    assert_equal "UNAUTHENTICATED", error.dig("extensions", "code")
  end

  def test_missing_record_returns_not_found
    error = ProbeSchema.execute("{ missing }", context: { scopes: [] }).to_h["errors"].first

    assert_equal "User not found", error["message"]
    assert_equal "NOT_FOUND", error.dig("extensions", "code")
  end

  def test_invalid_record_returns_invalid
    error = ProbeSchema.execute("{ invalid }", context: { scopes: [] }).to_h["errors"].first

    assert_equal "Email can't be blank", error["message"]
    assert_equal "INVALID", error.dig("extensions", "code")
  end

  def test_unhandled_errors_raise
    error = assert_raises(RuntimeError) { execute_graphql("mutation { triggerError }", scopes: []) }

    assert_equal "Test backend error", error.message
  end

  def test_rejects_deep_queries
    query = "{ __schema { types { fields { type { #{"ofType { " * 12}name#{" }" * 12} } } } } }"

    assert_match "exceeds max depth", graphql_error(query)["message"]
  end

  def test_every_root_field_declares_access
    [ AppSchema.query, AppSchema.mutation ].each do |type|
      type.fields.each_value do |field|
        assert_kind_of Types::RootField, field
        assert_predicate field.access, :present?, "#{type.graphql_name}.#{field.name} has no access"
      end
    end
  end

  def test_public_root_fields
    public_fields = [ AppSchema.query, AppSchema.mutation ].flat_map do |type|
      type.fields.values.select { |field| field.access.include?(:public) }.map { |field| "#{type.graphql_name}.#{field.name}" }
    end

    assert_equal [ "Query.healthCheck", "Mutation.createToken", "Mutation.triggerError" ].sort, public_fields.sort
  end
end
