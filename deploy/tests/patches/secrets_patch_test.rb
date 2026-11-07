require_relative "../test_helper"

class SecretsPatchTest < Minitest::Test
  def test_always_writes_only_server_keys_privately_and_removes_operator_copies
    File.write(Constants.local_env_path, "CLOUDFLARE_TOKEN=cloudflare\nDEPLOY_SSH_KEY_BASE64=private\nRAILS_ENV=production\n")
    commands = []
    writes = []
    Cmd.stubs(:ssh).with { |*args, **| commands << args; true }
    Cmd.stubs(:ssh_write).with { |path, content, **| writes << [ path, content ]; true }

    SecretsPatch.always

    assert_equal [ [ Constants.remote_env_path, "RAILS_ENV=production\n" ] ], writes
    assert_equal(
      [
        [
          "umask 077 && touch ? && sudo chgrp ? ? && chmod 640 ?",
          Constants.remote_env_path,
          "app",
          Constants.remote_env_path,
          Constants.remote_env_path,
        ],
        [ "rm -f ? ? ?", Constants.remote_env_prod_path, "/home/deploy/.env", "/home/deploy/.ssh/id_rsa" ],
      ],
      commands,
    )
  end
end
