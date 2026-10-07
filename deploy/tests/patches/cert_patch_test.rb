require_relative "../test_helper"

class CertPatchTest < Minitest::Test
  def test_needed
    Cmd.expects(:ssh).returns(certificate(Subdomains.domains))
    refute CertPatch.needed?

    CertPatch.instance_variable_set(:@certificate, nil)
    Cmd.expects(:ssh).returns(certificate([ "other.com" ]))
    assert CertPatch.needed?

    CertPatch.instance_variable_set(:@certificate, nil)
    Cmd.expects(:ssh).returns("invalid")
    assert CertPatch.needed?
  end

  def test_apply
    commands = []
    Cmd.stubs(:ssh).with do |command, *|
      commands << command
      ![ "which nginx", "which certbot" ].include?(command) && !command.start_with?("systemctl show")
    end.returns("")
    Cmd.expects(:ssh).with("which nginx").returns("/usr/sbin/nginx")
    Cmd.expects(:ssh).with("which certbot").returns("")
    Cmd.expects(:ssh).with(regexp_matches(/\Asystemctl show/))
      .returns("LoadState=loaded\nActiveState=active\nFreezerState=running\n")
    Cmd.expects(:ssh_write).with("/etc/nginx/nginx.conf", "nginx", sudo: true)
    Req.expects(:call).returns("nginx")

    CertPatch.apply

    assert_includes commands, "sudo systemctl stop nginx.service"
    assert_includes commands, "sudo fuser -k 80/tcp || true"
    assert_includes commands, "sudo nginx -t"
    assert_includes commands, "sudo snap install --classic certbot"
    assert_includes commands, "sudo ln -s /snap/bin/certbot /usr/bin/certbot"
    assert commands.any? { |command| command.include?("--cert-name example.com") && command.include?("-d jobs.example.com") }
  end

  private

  def certificate(domains)
    "notAfter=Aug 30 00:00:00 2099 GMT\nX509v3 Subject Alternative Name:\n #{domains.map { |domain| "DNS:#{domain}" }.join(", ")}"
  end
end
