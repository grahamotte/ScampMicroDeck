require_relative "test_helper"

class CoreExtensionsTest < Minitest::Test
  def test_presence
    assert nil.blank?
    assert false.blank?
    assert " \n".blank?
    assert [].blank?
    assert({}.blank?)
    refute true.blank?
    refute 0.blank?
    refute "value".blank?
    refute [ 1 ].blank?
    assert "value".present?
    refute nil.present?
  end
end
