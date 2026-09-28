require_relative "../test_helper"

class CoreExtensionsTest < Minitest::Test
  def test_presence
    assert nil.blank?
    assert false.blank?
    assert " \n".blank?
    assert [].blank?
    refute true.blank?
    refute 0.blank?
    assert "value".present?
  end

  def test_string_conversion
    assert_equal "http_response_code", "HTTPResponse-Code".underscore
    assert_equal "Hello World", "hello world".as_title
  end

  def test_string_styles
    assert_equal "\e[31mtext\e[0m", "text".red
    assert_equal "\e[44mtext\e[0m", "text".bg_blue
    assert_equal "\e[1mtext\e[22m", "text".bold
    assert_equal "\e[4mtext\e[24m", "text".underline
  end
end
