require_relative "../test_helper"

class ConstantsTest < Minitest::Test
  def test_paths_and_values
    assert_equal "/var/www/example.com", Constants.remote_root
    assert_equal "/home/deploy", Constants.remote_home_dir
    assert_equal "/home/deploy/example.com.git", Constants.remote_git_dir
    assert_equal "/var/www/example.com/.env", Constants.remote_env_path
    assert_equal "/var/www/example.com/.env.production", Constants.remote_env_prod_path
    assert_equal File.join(@deploy_test_dir, ".env.production"), Constants.local_env_path
    assert_equal "git@github.com:example/app.git", Constants.github_repo
  end

  def test_config_values
    assert_equal File.join(@deploy_test_dir, "config.json"), Constants.config_path
    assert_equal "example.com", Constants.domain
    assert_equal "test-region", Constants.instance_region
    assert_equal "test-size", Constants.instance_size
    assert_equal "app_production", Constants.db_name
  end

  def test_default_config_path
    Constants.config_path = nil

    assert_equal File.join(Constants.local_root, "config.json"), Constants.config_path
  end

  def test_default_local_env_path
    Constants.local_env_path = nil

    assert_equal File.join(Constants.local_root, ".env.production"), Constants.local_env_path
  end
end
