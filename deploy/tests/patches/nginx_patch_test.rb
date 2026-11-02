require_relative "../test_helper"

class NginxPatchTest < Minitest::Test
  def test_nginx_config
    config = NginxPatch.send(:nginx_config)

    assert_includes config, "server_name app.example.com hc.example.com api.example.com jobs.example.com;"
    assert_includes config, "root /var/www/example.com/frontend/dist/app"
    assert_includes config, "root /var/www/example.com/frontend/dist/hc"
    refute_includes config, "location /api/"
    assert_includes config, 'location ~ ^/(apple-touch-icon[^/]*\\.png|favicon[^/]*\\.(ico|png))$'
    refute_match(/\s(www\.)?example\.com[\s;]/, config)
    assert_includes config, "server_name api.example.com;"
    assert_includes config, "server_name jobs.example.com;"
    assert_equal [ "http://127.0.0.1:3000" ] * 2, config.scan(/proxy_pass ([^;]+);/).flatten
    assert_equal [ "proxy_set_header X-Request-Id $request_id;" ] * 2, config.scan(/proxy_set_header X-Request-Id [^;]+;/)
  end

  def test_rejects_unknown_hosts
    config = NginxPatch.send(:nginx_config)

    assert_match(/server \{\s+listen 80 default_server;\s+listen \[::\]:80 default_server;\s+listen 443 ssl default_server;\s+http2 on;\s+ssl_reject_handshake on;\s+return 444;\s+\}/, config)
    assert_equal 3, config.scan("default_server").size
  end

  def test_enables_http2_with_its_own_directive
    config = NginxPatch.send(:nginx_config)
    servers = config.scan(/listen 443 ssl( default_server)?;\s+http2 on;/).size

    assert_operator servers, :>, 0
    assert_equal servers, config.scan("listen 443").size
    refute_match(/listen [^;]*http2/, config)
  end

  def test_logs_to_journal
    config = NginxPatch.send(:nginx_config)

    assert_includes config, "error_log syslog:server=unix:/dev/log,tag=nginx,nohostname warn;"
    assert_includes config, "access_log syslog:server=unix:/dev/log,tag=nginx_access,severity=info,nohostname journal;"
    assert_includes config, '"status":$status,"method":"$request_method","host":"$host","path":"$uri"'
    assert_includes config, '"ip":"$remote_addr","ua":"$http_user_agent","bytes":$body_bytes_sent,"duration":$request_time,"request_id":"$request_id"'
    assert_includes config, "log_format journal escape=json"
    refute_includes config, "/var/log/nginx"
    assert_match(/location \/nginx_status \{\s+stub_status on;\s+access_log off;/, config)
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
