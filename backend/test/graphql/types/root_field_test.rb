require "test_helper"

module Types
  class RootFieldTest < ActiveSupport::TestCase
    def test_requires_access
      assert_raises(ArgumentError) { Types::RootField.new(name: :thing, type: String, null: true) }
    end

    def test_keeps_access
      assert_equal [ :user ], Types::RootField.new(name: :thing, type: String, null: true, access: :user).access
    end
  end
end
