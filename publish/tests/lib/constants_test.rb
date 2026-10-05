require_relative "../test_helper"

class ConstantsTest < Minitest::Test
  def test_config_values
    assert_equal File.join(@publish_test_dir, "config.json"), Constants.config_path
    assert_equal "example.com", Constants.config.fetch(:domain)
  end

  def test_default_config_path
    Constants.config_path = nil

    assert_equal File.join(Constants.local_root, "config.json"), Constants.config_path
  end
end
