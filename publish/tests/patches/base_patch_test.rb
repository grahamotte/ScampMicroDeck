require_relative "../test_helper"

class NeededTestPatch < BasePatch
  class << self
    attr_accessor :calls

    def always = calls << :always
    def needed? = true
    def apply = calls << :apply
  end
end

class UnneededTestPatch < BasePatch
  class << self
    attr_accessor :calls

    def always = calls << :always
    def needed? = false
    def apply = calls << :apply
  end
end

class BasePatchTest < Minitest::Test
  def test_call_applies_when_needed
    NeededTestPatch.calls = []

    NeededTestPatch.call

    assert_equal [ :always, :apply ], NeededTestPatch.calls
  end

  def test_call_skips_apply_when_unneeded
    UnneededTestPatch.calls = []

    UnneededTestPatch.call

    assert_equal [ :always ], UnneededTestPatch.calls
  end
end
