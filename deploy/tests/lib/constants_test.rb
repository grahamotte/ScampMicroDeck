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

  def test_server_env_drops_operator_only_keys
    File.write(
      Constants.local_env_path,
      [
        "# Production",
        "APPLE_KEY_ID='key'",
        "BACKUP_BUCKET='backups'",
        "CLOUDFLARE_TOKEN='cloudflare'",
        "DEPLOY_PASSWORD='password'",
        "DEPLOY_SSH_KEY_BASE64='private'",
        "DEPLOY_SSH_KEY_PUB='public'",
        "DEPLOY_USER='deploy'",
        "DIGITAL_OCEAN_TOKEN='digital-ocean'",
        "export JWT_SECRET='jwt'",
        "RAILS_ENV='production'",
        "",
      ].join("\n"),
    )

    assert_equal(
      "# Production\nBACKUP_BUCKET='backups'\nDEPLOY_USER='deploy'\nexport JWT_SECRET='jwt'\nRAILS_ENV='production'\n",
      Constants.server_env,
    )
  end

  def test_server_env_uses_the_config_list_of_operator_only_keys
    config = JSON.parse(File.read(Constants.config_path)).merge("operatorOnlyEnvKeys" => [ "PUBLISH_*", "RAILS_ENV" ])
    File.write(Constants.config_path, JSON.generate(config))
    Constants.instance_variable_set(:@config, nil)
    File.write(Constants.local_env_path, "APPLE_TEAM_ID=team\nNODE_ENV=production\nPUBLISH_TOKEN=token\nRAILS_ENV=production\n")

    assert_equal [ "PUBLISH_*", "RAILS_ENV" ], Constants.operator_only_env_keys
    assert_equal "APPLE_TEAM_ID=team\nNODE_ENV=production\n", Constants.server_env
  end

  def test_server_env_requires_the_config_list_of_operator_only_keys
    config = JSON.parse(File.read(Constants.config_path)).except("operatorOnlyEnvKeys")
    File.write(Constants.config_path, JSON.generate(config))
    Constants.instance_variable_set(:@config, nil)

    assert_raises(KeyError) { Constants.server_env }
  end

  def test_ssh_key_decodes_its_base64_value
    previous = ENV["DEPLOY_SSH_KEY_BASE64"]
    ENV["DEPLOY_SSH_KEY_BASE64"] = [ "-----BEGIN KEY-----\nbody\n-----END KEY-----\n" ].pack("m0")

    assert_equal "-----BEGIN KEY-----\nbody\n-----END KEY-----\n", Constants.ssh_key

    ENV["DEPLOY_SSH_KEY_BASE64"] = "not base64!"

    assert_raises(ArgumentError) { Constants.ssh_key }
  ensure
    ENV["DEPLOY_SSH_KEY_BASE64"] = previous
  end

  def test_config_values
    assert_equal File.join(@deploy_test_dir, "config.json"), Constants.config_path
    assert_equal "example.com", Constants.domain
    assert_equal "test-region", Constants.instance_region
    assert_equal "test-size", Constants.instance_size
    assert_equal "app_production", Constants.db_name
  end

  def test_redirect_and_mail_domains
    assert_equal [], Constants.redirect_domains
    assert_equal [ "example.com" ], Constants.mail_domains

    File.write(Constants.config_path, JSON.generate(domain: "example.com", redirectDomains: [ "example.net" ]))
    Constants.instance_variable_set(:@config, nil)

    assert_equal [ "example.net" ], Constants.redirect_domains
    assert_equal [ "example.com", "example.net" ], Constants.mail_domains
  end

  def test_deploy_ref
    previous = ENV.delete("DEPLOY_REF")
    assert_equal "origin/master", Constants.deploy_ref

    ENV["DEPLOY_REF"] = ""
    assert_equal "origin/master", Constants.deploy_ref

    ENV["DEPLOY_REF"] = "HEAD"
    assert_equal "HEAD", Constants.deploy_ref
  ensure
    ENV["DEPLOY_REF"] = previous
  end

  def test_domain_is_required
    File.write(Constants.config_path, JSON.generate(domain: ""))
    Constants.instance_variable_set(:@config, nil)

    error = assert_raises(RuntimeError) { Constants.domain }

    assert_equal "config.json domain is required to deploy", error.message
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
