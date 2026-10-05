require_relative "../test_helper"

class ConstantsTest < Minitest::Test
  def test_config_values
    assert_equal File.join(@publish_test_dir, "config.json"), Constants.config_path
    assert_equal "git@github.com:example/app.git", Constants.github_repo
  end

  def test_missing_github_repo
    File.write(Constants.config_path, JSON.generate(domain: "example.com"))
    Constants.instance_variable_set(:@config, nil)

    assert_equal "", Constants.github_repo
  end

  def test_github_token_comes_from_environment
    Constants.config[:githubToken] = "local-token"

    assert_equal "github-token", Constants.github_token
  end

  def test_missing_github_token_has_actionable_error
    [ nil, "" ].each do |token|
      ENV["GITHUB_TOKEN"] = token
      error = assert_raises(RuntimeError) { Constants.github_token }
      assert_equal "Set GITHUB_TOKEN in .env.production through Mr. Moto's mise secrets", error.message
    ensure
      ENV["GITHUB_TOKEN"] = "github-token"
    end
  end

  def test_default_config_path
    Constants.config_path = nil

    assert_equal File.join(Constants.local_root, "config.json"), Constants.config_path
  end
end
