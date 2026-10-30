require_relative "../test_helper"

class NginxPatchTest < Minitest::Test
  def test_nginx_config
    config = NginxPatch.send(:nginx_config)

    assert_includes config, "server_name app.example.com hc.example.com api.example.com jobs.example.com;"
    assert_includes config, "root /var/www/example.com/frontend/dist/app"
    assert_includes config, "root /var/www/example.com/frontend/dist/hc"
    refute_includes config, "location /api/"
    refute_match(/\s(www\.)?example\.com[\s;]/, config)
    assert_includes config, "server_name api.example.com;"
    assert_includes config, "server_name jobs.example.com;"
    assert_equal [ "http://127.0.0.1:3000" ] * 2, config.scan(/proxy_pass ([^;]+);/).flatten
  end

  def test_always
    commands = []
    definition = nil
    Cmd.stubs(:ssh).with do |command, *|
      commands << command
      command != "which nginx" && !command.start_with?("systemctl show")
    end.returns("")
    Cmd.expects(:ssh).with("which nginx").returns("/usr/sbin/nginx")
    Cmd.expects(:ssh).with(regexp_matches(/\Asystemctl show/))
      .returns("LoadState=loaded\nActiveState=active\nFreezerState=running\n")
    Cmd.expects(:ssh_write).with do |path, content, sudo:|
      definition = content
      path == "/etc/nginx/nginx.conf" && sudo
    end

    NginxPatch.always

    assert_includes definition, "worker_processes 2"
    assert_equal [ "http://127.0.0.1:3000" ] * 2, definition.scan(/proxy_pass ([^;]+);/).flatten
    assert_includes commands, "sudo systemctl stop nginx.service"
    assert_includes commands, "sudo systemctl start nginx.service"
  end
end
